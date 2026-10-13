import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyServerUrl = 'server_base_url';
const String _keyServerHistory = 'server_url_history';
const String _keyDeviceId = 'device_unique_id';
const int _maxServerHistory = 10;

/// 软件源配置管理器
class ServerConfigManager {
  static final ServerConfigManager _instance = ServerConfigManager._internal();
  SharedPreferences? _pref;
  String _cachedUrl = '';
  String _cachedDeviceId = '';

  factory ServerConfigManager() => _instance;
  static ServerConfigManager get instance => _instance;

  ServerConfigManager._internal();

  Future<void> init() async {
    try {
      _pref = await SharedPreferences.getInstance();
      _cachedUrl = _pref?.getString(_keyServerUrl) ?? '';
    } catch (_) {}
  }

  SharedPreferences? get preferences => _pref;

  Future<String> getDeviceId() async {
    if (_cachedDeviceId.isNotEmpty) return _cachedDeviceId;
    if (_pref == null) await init();
    var id = _pref?.getString(_keyDeviceId) ?? '';
    if (id.isEmpty) {
      final rand = Random().nextInt(1 << 32).toRadixString(36);
      id = 'and_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_$rand';
      await _pref?.setString(_keyDeviceId, id);
    }
    _cachedDeviceId = id;
    return id;
  }

  Future<String> getServerUrl() async {
    if (_cachedUrl.isNotEmpty) return _cachedUrl;
    if (_pref == null) await init();
    _cachedUrl = _pref?.getString(_keyServerUrl) ?? '';
    return _cachedUrl;
  }

  String getCachedServerUrl() => _cachedUrl;

  String getOrigin() {
    if (_cachedUrl.trim().isEmpty) return '';
    return stripApiSuffix(normalizeRaw(_cachedUrl));
  }

  String storageScope() {
    return hostScope(getOrigin());
  }

  String scopedKey(String name) {
    final scope = storageScope();
    if (scope.isEmpty) return '';
    return '$name@$scope';
  }

  static String hostScope(String origin) {
    var value = origin.trim().toLowerCase();
    if (value.isEmpty) return '';
    if (value.startsWith('https://')) {
      value = value.substring(8);
    } else if (value.startsWith('http://')) {
      value = value.substring(7);
    }
    final slash = value.indexOf('/');
    if (slash >= 0) {
      value = value.substring(0, slash);
    }
    return value;
  }

  String getApiBase() {
    final origin = getOrigin();
    return origin.isNotEmpty ? '$origin/api' : '';
  }

  String resolveMediaUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final origin = getOrigin();
    if (origin.isEmpty) return path;
    return path.startsWith('/') ? '$origin$path' : '$origin/$path';
  }

  Future<List<String>> getServerHistory() async {
    if (_pref == null) await init();
    try {
      final raw = _pref?.getString(_keyServerHistory) ?? '[]';
      final list = (jsonDecode(raw) as List).map((e) => '$e').toList();
      if (list.isNotEmpty) return list;
      if (_cachedUrl.isNotEmpty) return [_cachedUrl];
      return [];
    } catch (_) {
      return _cachedUrl.isNotEmpty ? [_cachedUrl] : [];
    }
  }

  Future<void> addServerHistory(String url) async {
    final cleanUrl = normalizeRaw(url);
    if (cleanUrl.isEmpty) return;
    if (_pref == null) await init();
    try {
      final current = await getServerHistory();
      final filtered = current.where((item) => item != cleanUrl).toList();
      filtered.insert(0, cleanUrl);
      if (filtered.length > _maxServerHistory) {
        filtered.removeRange(_maxServerHistory, filtered.length);
      }
      await _pref?.setString(_keyServerHistory, jsonEncode(filtered));
    } catch (_) {}
  }

  Future<void> removeServerHistory(String url) async {
    if (_pref == null) await init();
    try {
      final current = await getServerHistory();
      final filtered = current.where((item) => item != url).toList();
      await _pref?.setString(_keyServerHistory, jsonEncode(filtered));
    } catch (_) {}
  }

  Future<void> clearServerHistory() async {
    if (_pref == null) await init();
    try {
      await _pref?.setString(_keyServerHistory, '[]');
    } catch (_) {}
  }

  Future<void> setServerUrl(String url) async {
    final cleanUrl = normalizeRaw(url);
    _cachedUrl = cleanUrl;
    if (_pref == null) await init();
    await _pref?.setString(_keyServerUrl, cleanUrl);
    await addServerHistory(cleanUrl);
  }

  Future<void> clearServerUrl() async {
    _cachedUrl = '';
    if (_pref == null) await init();
    await _pref?.remove(_keyServerUrl);
  }

  String normalizeRaw(String url) {
    var cleanUrl = url.trim();
    while (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }
    return cleanUrl;
  }

  String get provideKey => extractProvideKey(_cachedUrl);

  static String extractProvideKey(String url) {
    if (url.isEmpty) return '';
    final queryIndex = url.indexOf('?');
    if (queryIndex < 0) return '';
    final queryStr = url.substring(queryIndex + 1);
    final pairs = queryStr.split('&');
    for (final part in pairs) {
      final eq = part.indexOf('=');
      if (eq > 0) {
        final k = part.substring(0, eq).trim();
        if (k == 'key') {
          return Uri.decodeComponent(part.substring(eq + 1).trim());
        }
      }
    }
    return '';
  }

  static String stripProvideKey(String url) {
    if (url.isEmpty) return '';
    final queryIndex = url.indexOf('?');
    if (queryIndex < 0) return url;
    final base = url.substring(0, queryIndex);
    final queryStr = url.substring(queryIndex + 1);
    final pairs = queryStr.split('&');
    final kept = <String>[];
    for (final part in pairs) {
      final eq = part.indexOf('=');
      final k = eq > 0 ? part.substring(0, eq).trim() : part.trim();
      if (k != 'key') {
        kept.add(part);
      }
    }
    return kept.isNotEmpty ? '$base?${kept.join('&')}' : base;
  }

  static String buildServerUrl(String baseUrl, [String? key]) {
    final cleanBase = stripProvideKey(baseUrl.trim());
    final cleanKey = key?.trim() ?? '';
    if (cleanKey.isEmpty) return cleanBase;
    final sep = cleanBase.contains('?') ? '&' : '?';
    return '$cleanBase${sep}key=${Uri.encodeComponent(cleanKey)}';
  }

  static String stripApiSuffix(String url) {
    var base = url.trim();
    final queryIndex = base.indexOf('?');
    if (queryIndex >= 0) {
      base = base.substring(0, queryIndex);
    }
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    // 兼容剥离 /api/provide/app 或 /provide/app
    if (base.toLowerCase().endsWith('/api/provide/app')) {
      base = base.substring(0, base.length - 16);
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
    } else if (base.toLowerCase().endsWith('/provide/app')) {
      base = base.substring(0, base.length - 12);
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
    }
    while (base.toLowerCase().endsWith('/api')) {
      base = base.substring(0, base.length - 4);
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
    }
    return base;
  }

  String buildApiUrl(String path) {
    final apiBase = getApiBase();
    if (apiBase.isEmpty) {
      throw Exception('未配置服务端地址');
    }
    final apiPath = path.startsWith('/') ? path : '/$path';
    return '$apiBase$apiPath';
  }
}
