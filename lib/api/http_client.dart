import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../common/app_branding.dart';
import '../services/auth_gate.dart';
import '../services/auth_session.dart';
import '../utils/server_config_manager.dart';
import '../utils/source_guard.dart';
import '../utils/site_heartbeat.dart';
import '../utils/app_version_util.dart';

class ApiResponse {
  final int code;
  final String msg;
  final dynamic data;

  ApiResponse({
    required this.code,
    required this.msg,
    this.data,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    return ApiResponse(
      code: json['code'] is int ? json['code'] : (int.tryParse('${json['code']}') ?? -1),
      msg: '${json['msg'] ?? ''}',
      data: json['data'],
    );
  }
}

class ConnectionResult {
  final bool ok;
  final String? message;
  final bool isPrivate;

  const ConnectionResult({
    required this.ok,
    this.message,
    this.isPrivate = false,
  });
}

/// HTTP 客户端单例
class HttpClient {
  static final HttpClient _instance = HttpClient._internal();
  String _userAgent = '';

  factory HttpClient() => _instance;
  static HttpClient get instance => _instance;

  HttpClient._internal();

  Future<String> _resolveUserAgent() async {
    if (_userAgent.isNotEmpty) return _userAgent;
    try {
      final version = await AppVersionUtil.getVersionName();
      _userAgent = version.isNotEmpty
          ? '${AppBranding.userAgentProduct}/$version'
          : AppBranding.userAgentProduct;
    } catch (_) {
      _userAgent = AppBranding.userAgentProduct;
    }
    return _userAgent;
  }

  Future<ApiResponse> get(
    String path, {
    Map<String, dynamic>? params,
    int timeoutMs = 15000,
  }) async {
    final manager = ServerConfigManager.instance;
    String url;
    try {
      url = manager.buildApiUrl(path);
    } catch (e) {
      SourceGuard.intercept();
      rethrow;
    }

    if (params != null && params.isNotEmpty) {
      final queryPairs = <String>[];
      params.forEach((k, v) {
        if (v != null && '$v'.trim().isNotEmpty) {
          queryPairs.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent('$v')}');
        }
      });
      if (queryPairs.isNotEmpty) {
        url += (url.contains('?') ? '&' : '?') + queryPairs.join('&');
      }
    }

    return _send(url, timeoutMs);
  }

  Future<ApiResponse> post(
    String path, {
    Map<String, dynamic>? body,
    int timeoutMs = 15000,
  }) async {
    final manager = ServerConfigManager.instance;
    final url = manager.buildApiUrl(path);
    final userAgent = await _resolveUserAgent();
    final headers = await _authHeaders(userAgent);
    headers['Content-Type'] = 'application/json';
    final res = await http
        .post(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode(body ?? {}),
        )
        .timeout(Duration(milliseconds: timeoutMs));
    return _parseHttpResponse(res);
  }

  void trackView(
    String action, [
    String resource = '',
    String page = '',
    String deviceModel = '',
    String resourceCat = '',
    String resourceTitle = '',
    String collectSource = '',
  ]) {
    _sendTrack(action, resource, page, deviceModel, resourceCat, resourceTitle, collectSource)
        .catchError((_) {});
  }

  Future<void> _sendTrack(
    String action,
    String resource,
    String page,
    String deviceModel,
    String resourceCat,
    String resourceTitle,
    String collectSource,
  ) async {
    final manager = ServerConfigManager.instance;
    String url;
    try {
      url = manager.buildApiUrl('/stat/view');
    } catch (_) {
      return;
    }
    final userAgent = await _resolveUserAgent();
    String version = '';
    try {
      version = await AppVersionUtil.getVersionName();
    } catch (_) {}

    final source = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'app');
    String deviceId = '';
    try {
      deviceId = await manager.getDeviceId();
    } catch (_) {}
    final resolvedModel = deviceModel.trim().isNotEmpty
        ? deviceModel.trim()
        : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.trim();
    final provideKey = manager.provideKey;

    try {
      await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
          if (deviceId.isNotEmpty) 'X-Device-Id': deviceId,
          if (deviceId.isNotEmpty) 'Device-Id': deviceId,
          if (provideKey.isNotEmpty) 'X-Provide-Key': provideKey,
        },
        body: jsonEncode({
          'source': source,
          if (collectSource.trim().isNotEmpty) 'collect_source': collectSource.trim(),
          'action': action,
          'resource': resource,
          'page': page.isNotEmpty ? page : action,
          if (resourceCat.isNotEmpty) 'resource_cat': resourceCat,
          if (resourceTitle.isNotEmpty) 'resource_title': resourceTitle,
          'app_version': version,
          'device_model': resolvedModel,
          'device_id': deviceId,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  @visibleForTesting
  String formatConnectionError(dynamic error) => _formatConnectionError(error);

  String _formatConnectionError(dynamic error) {
    final msg = error.toString().replaceFirst('Exception: ', '').trim();
    final lower = msg.toLowerCase();

    // 1. 服务未启动、网关异常或拒绝连接，统一归为服务错误
    if (lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('504') ||
        lower.contains('bad gateway') ||
        lower.contains('gateway timeout') ||
        lower.contains('service unavailable') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('failed to connect') ||
        lower.contains('connection failed') ||
        lower.contains('socketexception') ||
        lower.contains('errno = 111') ||
        lower.contains('errno = 61')) {
      return '服务未启动或网关异常 (服务错误)';
    }

    // 2. 超时
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return '连接超时，服务可能未启动或网络不可达';
    }

    // 3. 域名/地址解析失败
    if (lower.contains('nodename nor servname') ||
        lower.contains('host lookup') ||
        lower.contains('failed host lookup')) {
      return '无法解析服务端地址，请检查域名或网络';
    }

    return msg.isNotEmpty ? msg : '服务未启动或网关异常 (服务错误)';
  }

  /// 媒体流（HLS/封面代理）请求头，不含 JSON Content-Type。
  Future<Map<String, String>> mediaRequestHeaders() async {
    final userAgent = await _resolveUserAgent();
    final manager = ServerConfigManager.instance;
    String deviceId = '';
    try {
      deviceId = await manager.getDeviceId();
    } catch (_) {}
    final token = AuthSession.instance.token.trim();
    final provideKey = manager.provideKey;
    return {
      'Accept': '*/*',
      'User-Agent': userAgent,
      if (deviceId.isNotEmpty) 'X-Device-Id': deviceId,
      if (deviceId.isNotEmpty) 'Device-Id': deviceId,
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (token.isNotEmpty) 'Token': token,
      if (token.isEmpty && provideKey.isNotEmpty) 'X-Provide-Key': provideKey,
    };
  }

  Future<Map<String, String>> _authHeaders(String userAgent) async {
    final manager = ServerConfigManager.instance;
    String deviceId = '';
    try {
      deviceId = await manager.getDeviceId();
    } catch (_) {}
    final token = AuthSession.instance.token.trim();
    final provideKey = manager.provideKey;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': userAgent,
      if (deviceId.isNotEmpty) 'X-Device-Id': deviceId,
      if (deviceId.isNotEmpty) 'Device-Id': deviceId,
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (token.isNotEmpty) 'Token': token,
      if (token.isEmpty && provideKey.isNotEmpty) 'X-Provide-Key': provideKey,
    };
  }

  ApiResponse _parseHttpResponse(http.Response res) {
    if (res.statusCode == 401) {
      AuthGate.handleUnauthorized();
      throw Exception('请先登录');
    }
    if (res.statusCode != 200) {
      String errMsg = 'HTTP ${res.statusCode}';
      try {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['msg'] != null && body['msg'].toString().isNotEmpty) {
          errMsg = body['msg'].toString();
        }
      } catch (_) {}
      throw Exception(errMsg);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is Map<String, dynamic>) {
      return ApiResponse.fromJson(body);
    }
    if (body is Map) {
      return ApiResponse.fromJson(body.map((k, v) => MapEntry('$k', v)));
    }
    throw Exception('响应格式错误');
  }

  Future<ConnectionResult> testConnection(String baseUrl) async {
    final raw = baseUrl.trim();
    if (raw.isEmpty) {
      return const ConnectionResult(ok: false, message: '请输入有效的服务端地址');
    }
    final manager = ServerConfigManager.instance;
    final origin = ServerConfigManager.stripApiSuffix(manager.normalizeRaw(baseUrl));
    if (origin.isEmpty || origin == 'https://' || origin == 'http://') {
      return const ConnectionResult(ok: false, message: '请输入有效的服务端地址');
    }

    final key = ServerConfigManager.extractProvideKey(baseUrl);
    SourceGuard.beginSkip();
    try {
      // 公开探活：与 Web 一致，仅验证服务端根地址可达
      try {
        final response = await _send('$origin/api/config/basic', 5000, customKey: key);
        if (response.code == 0) {
          return const ConnectionResult(ok: true);
        }
      } catch (basicErr) {
        final msg = basicErr.toString().replaceFirst('Exception: ', '');
        if (msg.contains('401') || msg.contains('登录')) {
          return const ConnectionResult(ok: true);
        }
      }
      final query = key.isNotEmpty ? '?key=${Uri.encodeComponent(key)}' : '';
      try {
        final response = await _send('$origin/api/provide/app$query', 5000, customKey: key);
        if (response.code == 1 || response.code == 0) {
          return const ConnectionResult(ok: true);
        }
      } catch (appErr) {
        final msg = appErr.toString().replaceFirst('Exception: ', '');
        final lower = msg.toLowerCase();

        // 优先拦截 502/503/504 与拒绝连接等服务错误，防止误判为私有化
        if (lower.contains('502') ||
            lower.contains('503') ||
            lower.contains('504') ||
            lower.contains('bad gateway') ||
            lower.contains('gateway timeout') ||
            lower.contains('service unavailable') ||
            lower.contains('connection refused') ||
            lower.contains('connection reset') ||
            lower.contains('socketexception')) {
          return ConnectionResult(ok: false, message: _formatConnectionError(appErr));
        }

        // 明确包含私有化或订阅密钥提示
        if (msg.contains('私有化') || msg.contains('订阅密钥')) {
          return ConnectionResult(ok: false, isPrivate: true, message: msg);
        }

        // 过渡兼容逻辑：若 404 说明为早期未支持 /api/provide/app 的旧版服务端，尝试兜底探测 /api/health。
        // 注意：服务端 /api/health 未来大版本将废弃移除，届时将仅支持 /api/provide/app 探测。
        if (msg.contains('404')) {
          final healthRes = await _send('$origin/api/health$query', 5000, customKey: key);
          if (healthRes.code == 0) {
            return const ConnectionResult(ok: true);
          }
        }
        rethrow;
      }
      return const ConnectionResult(ok: true);
    } catch (e) {
      return ConnectionResult(ok: false, message: _formatConnectionError(e));
    } finally {
      SourceGuard.endSkip();
    }
  }

  Future<ApiResponse> _send(String url, int timeoutMs, {String? customKey}) async {
    final userAgent = await _resolveUserAgent();
    final manager = ServerConfigManager.instance;
    try {
      var headers = await _authHeaders(userAgent);
      if (customKey != null && customKey.isNotEmpty &&
          !headers.containsKey('Authorization')) {
        headers = Map<String, String>.from(headers)
          ..['X-Provide-Key'] = customKey;
      }
      final res = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(Duration(milliseconds: timeoutMs));
      return _parseHttpResponse(res);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('网络请求失败');
    }
  }
}
