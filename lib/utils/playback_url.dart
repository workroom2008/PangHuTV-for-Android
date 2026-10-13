import '../services/auth_session.dart';
import 'server_config_manager.dart';

/// 播放/封面代理 URL：拼 origin、ExoPlayer HLS 别名、私有化 ?key=。
class PlaybackUrl {
  static String resolve(String link) {
    final raw = link.trim();
    if (raw.isEmpty) return raw;
    return ServerConfigManager.instance.resolveMediaUrl(raw);
  }

  /// 交给 VideoPlayer 的最终地址；不可播时返回空串。
  static String prepareForPlayer(String link) {
    var url = resolve(link);
    if (!isPlayableLink(url)) return '';
    url = hlsExoAlias(url);
    return appendPrivateAccessQuery(url);
  }

  static String prepareMediaUrl(String link) {
    final url = resolve(link);
    if (url.isEmpty) return url;
    if (needsServerApiAuth(url)) {
      return appendPrivateAccessQuery(url);
    }
    return url;
  }

  static bool isPlayableLink(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return false;
    final lower = raw.toLowerCase();
    if (lower.startsWith('91porna:') ||
        lower.startsWith('missav:') ||
        lower.startsWith('chigua51:')) {
      return false;
    }
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return true;
    }
    if (lower.contains('/api/hls')) {
      return true;
    }
    return false;
  }

  static String hlsExoAlias(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;
    if (uri.path.toLowerCase() == '/api/hls') {
      return uri.replace(path: '/api/hls.m3u8').toString();
    }
    return url;
  }

  static bool needsServerApiAuth(String resolvedUrl) {
    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null || uri.host.isEmpty) return false;
    final server = _serverBaseUri();
    if (server == null) return false;
    if (!_sameHost(uri, server)) return false;
    final path = uri.path.toLowerCase();
    return path.startsWith('/api/hls') || path.startsWith('/api/cover');
  }

  static String appendPrivateAccessQuery(String url) {
    if (!needsServerApiAuth(url)) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final q = Map<String, String>.from(uri.queryParameters);
    // ExoPlayer 对 m3u8 内嵌 /api/hls 子请求不一定带 Header，登录态写入 ?token=。
    final token = AuthSession.instance.token.trim();
    if (token.isNotEmpty && !q.containsKey('token')) {
      q['token'] = token;
    }
    if (token.isEmpty) {
      final key = ServerConfigManager.instance.provideKey.trim();
      if (key.isNotEmpty && !q.containsKey('key')) {
        q['key'] = key;
      }
    }
    if (q.length == uri.queryParameters.length) return url;
    return uri.replace(queryParameters: q).toString();
  }

  static Uri? _serverBaseUri() {
    final origin = ServerConfigManager.instance.getOrigin().trim();
    if (origin.isEmpty) return null;
    return Uri.tryParse(origin);
  }

  static bool _sameHost(Uri a, Uri b) {
    if (a.scheme.toLowerCase() != b.scheme.toLowerCase()) return false;
    if (a.host.toLowerCase() != b.host.toLowerCase()) return false;
    final ap = a.hasPort ? a.port : _defaultPort(a.scheme);
    final bp = b.hasPort ? b.port : _defaultPort(b.scheme);
    return ap == bp;
  }

  static int _defaultPort(String scheme) {
    return scheme.toLowerCase() == 'https' ? 443 : 80;
  }
}
