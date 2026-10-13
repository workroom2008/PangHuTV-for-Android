import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../common/app_branding.dart';
import '../types/dlna_types.dart';

/// DLNA MediaRenderer 客户端：SSDP 发现 + AVTransport + RenderingControl
/// 对齐 OHOS `DlnaClient.ets`
class DlnaClient {
  static const String ssdpAddr = '239.255.255.250';
  static const int ssdpPort = 1900;
  static const int scanMs = 4000;
  static const String avt = 'urn:schemas-upnp-org:service:AVTransport:1';
  static const String rcs = 'urn:schemas-upnp-org:service:RenderingControl:1';
  static const String renderer = 'urn:schemas-upnp-org:device:MediaRenderer:1';
  static const MethodChannel _multicastChannel = MethodChannel('com.ecohub.ecohub/multicast');

  RawDatagramSocket? _socket;
  int _scanToken = 0;
  final Map<String, DlnaDevice> _devices = {};
  final http.Client _httpClient = http.Client();

  Future<List<DlnaDevice>> discover({void Function(List<DlnaDevice>)? onUpdate}) async {
    _scanToken++;
    final token = _scanToken;
    _devices.clear();
    _closeSocket();

    if (Platform.isAndroid) {
      try {
        await _multicastChannel.invokeMethod('acquireMulticastLock');
      } catch (_) {}
    }

    const msearch = 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $ssdpAddr:$ssdpPort\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 3\r\n'
        'ST: $renderer\r\n'
        '\r\n';

    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket = socket;
      socket.broadcastEnabled = true;
      socket.multicastHops = 4;

      socket.listen((event) {
        if (event == RawSocketEvent.read && token == _scanToken) {
          final datagram = socket.receive();
          if (datagram != null) {
            final text = utf8.decode(datagram.data, allowMalformed: true);
            _handleSsdpText(text, token, onUpdate);
          }
        }
      });

      final target = InternetAddress(ssdpAddr);
      final bytes = utf8.encode(msearch);
      socket.send(bytes, target, ssdpPort);
      await Future.delayed(const Duration(milliseconds: 300));
      if (_socket != null && token == _scanToken) {
        socket.send(bytes, target, ssdpPort);
      }
    } catch (e) {
      _closeSocket();
      throw Exception('SSDP 扫描失败: $e');
    }

    await Future.delayed(const Duration(milliseconds: scanMs));
    if (token != _scanToken) return [];
    _closeSocket();
    return _listDevices();
  }

  void cancelDiscover() {
    _scanToken++;
    _closeSocket();
  }

  Future<void> cast(DlnaDevice device, String mediaUrl,
      {String title = AppBranding.defaultCastTitle,
      double startSec = 0,
      double durationSec = 0}) async {
    if (mediaUrl.trim().isEmpty) throw Exception('当前没有可投屏的地址');
    await _soapAction(device.controlURL, avt, 'SetAVTransportURI',
        _buildSetUriBody(mediaUrl, title, durationSec));
    if (startSec >= 2) {
      try {
        final hms = formatRelTime(startSec);
        await _soapAction(device.controlURL, avt, 'Seek', _buildSeekBody(hms, 'REL_TIME'));
      } catch (_) {}
    }
    await play(device);
  }

  Future<void> play(DlnaDevice device) =>
      _soapAction(device.controlURL, avt, 'Play', _buildPlayBody());

  Future<void> pause(DlnaDevice device) =>
      _soapAction(device.controlURL, avt, 'Pause', _buildPauseBody());

  Future<void> stop(DlnaDevice device) =>
      _soapAction(device.controlURL, avt, 'Stop', _buildStopBody());

  Future<void> seek(DlnaDevice device, double positionSec) async {
    final hms = formatRelTime(positionSec);
    final padded = formatRelTimePadded(positionSec);
    try {
      await _soapAction(device.controlURL, avt, 'Seek', _buildSeekBody(hms, 'REL_TIME'));
    } catch (_) {
      try {
        await _soapAction(device.controlURL, avt, 'Seek', _buildSeekBody(padded, 'REL_TIME'));
      } catch (_) {
        await _soapAction(device.controlURL, avt, 'Seek', _buildSeekBody(hms, 'ABS_TIME'));
      }
    }
  }

  Future<DlnaPositionInfo> getPositionInfo(DlnaDevice device) async {
    final xml = await _soapAction(device.controlURL, avt, 'GetPositionInfo',
        _buildGetPositionInfoBody());
    final relTime = _extractTag(xml, 'RelTime');
    var trackDuration = _extractTag(xml, 'TrackDuration');
    var durationSec = parseRelTime(trackDuration);
    if (durationSec <= 0) {
      final fromMeta = _extractAttr(xml, 'duration');
      if (fromMeta.isNotEmpty) {
        trackDuration = fromMeta;
        durationSec = parseRelTime(fromMeta);
      }
    }
    return DlnaPositionInfo(
      positionSec: parseRelTime(relTime),
      durationSec: durationSec,
      relTime: relTime,
      trackDuration: trackDuration,
    );
  }

  Future<String> getTransportInfo(DlnaDevice device) async {
    final xml = await _soapAction(device.controlURL, avt, 'GetTransportInfo',
        _buildGetTransportInfoBody());
    return _extractTag(xml, 'CurrentTransportState');
  }

  Future<int> getVolume(DlnaDevice device) async {
    if (device.renderingControlURL.isEmpty) throw Exception('设备不支持音量控制');
    final xml = await _soapAction(device.renderingControlURL, rcs, 'GetVolume',
        _buildGetVolumeBody());
    final raw = _extractTag(xml, 'CurrentVolume');
    return (int.tryParse(raw) ?? 0).clamp(0, 100);
  }

  Future<void> setVolume(DlnaDevice device, int volume) async {
    if (device.renderingControlURL.isEmpty) throw Exception('设备不支持音量控制');
    final clamped = volume.clamp(0, 100);
    await _soapAction(device.renderingControlURL, rcs, 'SetVolume',
        _buildSetVolumeBody(clamped));
  }

  static double parseRelTime(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == 'NOT_IMPLEMENTED' || trimmed == '*' || !trimmed.contains(':')) {
      return 0;
    }
    final parts = trimmed.split(':');
    if (parts.length < 2) return 0;
    final h = parts.length >= 3 ? (double.tryParse(parts[0]) ?? 0) : 0;
    final m = parts.length >= 3 ? (double.tryParse(parts[1]) ?? 0) : (double.tryParse(parts[0]) ?? 0);
    final s = parts.length >= 3 ? (double.tryParse(parts[2]) ?? 0) : (double.tryParse(parts[1]) ?? 0);
    return (h * 3600 + m * 60 + s).clamp(0, double.infinity);
  }

  static String formatRelTime(double totalSec) {
    final s = totalSec.floor().clamp(0, 8640000);
    final hours = s ~/ 3600;
    final minutes = (s % 3600) ~/ 60;
    final seconds = s % 60;
    final mm = minutes < 10 ? '0$minutes' : '$minutes';
    final ss = seconds < 10 ? '0$seconds' : '$seconds';
    return '$hours:$mm:$ss';
  }

  static String formatRelTimePadded(double totalSec) {
    final s = totalSec.floor().clamp(0, 8640000);
    final hours = s ~/ 3600;
    final minutes = (s % 3600) ~/ 60;
    final seconds = s % 60;
    final hh = hours < 10 ? '0$hours' : '$hours';
    final mm = minutes < 10 ? '0$minutes' : '$minutes';
    final ss = seconds < 10 ? '0$seconds' : '$seconds';
    return '$hh:$mm:$ss';
  }

  void _handleSsdpText(String text, int token, void Function(List<DlnaDevice>)? onUpdate) {
    final location = _headerValue(text, 'LOCATION');
    if (location.isEmpty) return;
    final rawUsn = _headerValue(text, 'USN').isNotEmpty ? _headerValue(text, 'USN') : location;
    final st = _headerValue(text, 'ST');
    final nt = _headerValue(text, 'NT');
    if (!'$st $nt $rawUsn'.contains('MediaRenderer')) return;
    final usn = _deviceId(rawUsn, location);
    if (_devices.containsKey(usn) || _hasLocation(location)) return;

    _devices[usn] = DlnaDevice(
      usn: usn,
      friendlyName: _guessName(usn, location),
      location: location,
      controlURL: '',
      host: _hostOf(location),
    );
    _fetchDescription(usn, location, token, onUpdate);
  }

  Future<void> _fetchDescription(
      String usn, String location, int token, void Function(List<DlnaDevice>)? onUpdate) async {
    try {
      final res = await _httpClient.get(Uri.parse(location)).timeout(const Duration(seconds: 5));
      if (token != _scanToken || res.statusCode != 200) return;
      final xml = res.body;
      final controlURL = _findServiceControlUrl(xml, location, 'AVTransport');
      if (controlURL.isEmpty) {
        _devices.remove(usn);
        onUpdate?.call(_listDevices().where((d) => d.controlURL.isNotEmpty).toList());
        return;
      }
      final rcsURL = _findServiceControlUrl(xml, location, 'RenderingControl');
      final device = DlnaDevice(
        usn: usn,
        friendlyName: _extractTag(xml, 'friendlyName').isNotEmpty
            ? _extractTag(xml, 'friendlyName')
            : _guessName(usn, location),
        manufacturer: _extractTag(xml, 'manufacturer'),
        location: location,
        controlURL: controlURL,
        renderingControlURL: rcsURL,
        host: _hostOf(location),
      );
      _devices[usn] = device;
      onUpdate?.call(_listDevices().where((d) => d.controlURL.isNotEmpty).toList());
    } catch (_) {
      _devices.remove(usn);
    }
  }

  String _findServiceControlUrl(String xml, String baseLocation, String serviceName) {
    final serviceRegex = RegExp(r'<service\b[\s\S]*?</service>', caseSensitive: false);
    for (final match in serviceRegex.allMatches(xml)) {
      final block = match.group(0) ?? '';
      final serviceType = _extractTag(block, 'serviceType');
      if (serviceType.contains(serviceName)) {
        final control = _extractTag(block, 'controlURL');
        if (control.isNotEmpty) return _resolveUrl(baseLocation, control);
      }
    }
    return '';
  }

  Future<String> _soapAction(String controlURL, String serviceType, String action, String bodyInner) async {
    final envelope = '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>$bodyInner</s:Body></s:Envelope>';
    final res = await _httpClient.post(
      Uri.parse(controlURL),
      headers: {
        'Content-Type': 'text/xml; charset="utf-8"',
        'SOAPAction': '"$serviceType#$action"',
      },
      body: envelope,
    ).timeout(const Duration(seconds: 8));

    if (res.statusCode < 200 || res.statusCode >= 300 || res.body.contains(RegExp(r'<\w*:?Fault[\s>]', caseSensitive: false))) {
      final codeRaw = _extractTag(res.body, 'errorCode');
      final parsedCode = int.tryParse(codeRaw) ?? 0;
      final desc = _extractTag(res.body, 'errorDescription');
      throw DlnaSoapError(
        action: action,
        httpCode: res.statusCode,
        errorCode: parsedCode,
        errorDescription: desc,
        message: desc.isNotEmpty ? '$desc ($action)' : '投屏指令失败 ($action, HTTP ${res.statusCode})',
      );
    }
    return res.body;
  }

  String _buildSetUriBody(String mediaUrl, String title, double durationSec) {
    final safeUrl = _xmlEscape(mediaUrl);
    final meta = _xmlEscape(_buildDidl(mediaUrl, title, durationSec));
    return '<u:SetAVTransportURI xmlns:u="$avt">'
        '<InstanceID>0</InstanceID>'
        '<CurrentURI>$safeUrl</CurrentURI>'
        '<CurrentURIMetaData>$meta</CurrentURIMetaData>'
        '</u:SetAVTransportURI>';
  }

  String _buildPlayBody() =>
      '<u:Play xmlns:u="$avt"><InstanceID>0</InstanceID><Speed>1</Speed></u:Play>';
  String _buildPauseBody() =>
      '<u:Pause xmlns:u="$avt"><InstanceID>0</InstanceID></u:Pause>';
  String _buildStopBody() =>
      '<u:Stop xmlns:u="$avt"><InstanceID>0</InstanceID></u:Stop>';
  String _buildSeekBody(String target, String unit) =>
      '<u:Seek xmlns:u="$avt"><InstanceID>0</InstanceID><Unit>$unit</Unit>'
      '<Target>${_xmlEscape(target)}</Target></u:Seek>';
  String _buildGetPositionInfoBody() =>
      '<u:GetPositionInfo xmlns:u="$avt"><InstanceID>0</InstanceID></u:GetPositionInfo>';
  String _buildGetTransportInfoBody() =>
      '<u:GetTransportInfo xmlns:u="$avt"><InstanceID>0</InstanceID></u:GetTransportInfo>';
  String _buildGetVolumeBody() =>
      '<u:GetVolume xmlns:u="$rcs"><InstanceID>0</InstanceID><Channel>Master</Channel></u:GetVolume>';
  String _buildSetVolumeBody(int volume) =>
      '<u:SetVolume xmlns:u="$rcs"><InstanceID>0</InstanceID><Channel>Master</Channel>'
      '<DesiredVolume>$volume</DesiredVolume></u:SetVolume>';

  String _buildDidl(String mediaUrl, String title, double durationSec) {
    final safeTitle =
        _xmlEscape(title.isNotEmpty ? title : AppBranding.defaultCastTitle);
    final safeUrl = _xmlEscape(mediaUrl);
    final durAttr = durationSec > 1 ? ' duration="${formatRelTime(durationSec)}"' : '';
    return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1">'
        '<dc:title>$safeTitle</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '<res protocolInfo="http-get:*:*:*"$durAttr>$safeUrl</res>'
        '</item></DIDL-Lite>';
  }

  String _headerValue(String text, String name) {
    final prefix = '${name.toUpperCase()}:';
    for (final line in text.split(RegExp(r'\r?\n'))) {
      if (line.toUpperCase().startsWith(prefix)) {
        return line.substring(line.indexOf(':') + 1).trim();
      }
    }
    return '';
  }

  String _extractTag(String xml, String tag) {
    final plain = RegExp('<$tag(?:\\s[^>]*)?>([\\s\\S]*?)</$tag>', caseSensitive: false);
    final m = plain.firstMatch(xml);
    if (m != null && m.group(1) != null) return _stripCdata(m.group(1)!);
    final ns = RegExp('<([A-Za-z_][\\w.-]*):$tag(?:\\s[^>]*)?>([\\s\\S]*?)</\\1:$tag>', caseSensitive: false);
    final nm = ns.firstMatch(xml);
    if (nm != null && nm.group(2) != null) return _stripCdata(nm.group(2)!);
    return '';
  }

  String _stripCdata(String raw) =>
      raw.replaceAll(RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'), r'$1').trim();

  String _extractAttr(String xml, String name) {
    final q = RegExp('$name="([^"]+)"', caseSensitive: false);
    final m1 = q.firstMatch(xml);
    if (m1 != null && m1.group(1) != null) return m1.group(1)!.trim();
    final e = RegExp('$name=&quot;([^&]+)&quot;', caseSensitive: false);
    final m2 = e.firstMatch(xml);
    if (m2 != null && m2.group(1) != null) return m2.group(1)!.trim();
    return '';
  }

  String _resolveUrl(String location, String path) {
    final trimmed = path.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
    final uri = Uri.parse(location);
    return uri.resolve(trimmed).toString();
  }

  String _hostOf(String location) {
    final uri = Uri.tryParse(location);
    return uri != null ? '${uri.host}:${uri.port}' : location;
  }

  String _guessName(String usn, String location) {
    if (usn.isNotEmpty) {
      final parts = usn.split(':');
      if (parts.length > 1) {
        final last = parts.last;
        return last.length > 24 ? last.substring(0, 24) : last;
      }
    }
    return _hostOf(location).isNotEmpty ? _hostOf(location) : 'DLNA 设备';
  }

  String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  List<DlnaDevice> _listDevices() => _devices.values.toList();

  String _deviceId(String usn, String location) {
    if (usn.startsWith('uuid:')) {
      final cut = usn.indexOf('::');
      return cut >= 0 ? usn.substring(0, cut) : usn;
    }
    return location;
  }

  bool _hasLocation(String location) {
    final loc = location.trim();
    return _devices.values.any((d) => d.location == loc);
  }

  void _closeSocket() {
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    if (Platform.isAndroid) {
      try {
        _multicastChannel.invokeMethod('releaseMulticastLock');
      } catch (_) {}
    }
  }

  void dispose() {
    _closeSocket();
    _httpClient.close();
  }
}
