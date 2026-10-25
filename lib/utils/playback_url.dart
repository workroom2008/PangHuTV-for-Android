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
    url = appendPrivateAccessQuery(url);
    url = appendServerMediaProxy(url);
    return url;
  }

  /// 给本站 /api/hls 地址补 client=tv，让服务端把分片也代理下来。
  ///
  /// 参数名历史上叫 client=tv（最初为老 Android TV 根证书不全而加），
  /// 但现在真正的价值是「线路」：实测极品源分片直连 CDN 只有 38KB/s
  /// （2.3MB 分片 60 秒都下不完），经服务端代理是 1.9MB/s，差 50 倍。
  /// 手机端直连表现为「播 1-2 秒卡住、提示网络较慢」，与源无关而与线路有关，
  /// 所以手机端也必须走代理。
  static String appendServerMediaProxy(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;
    if (!needsServerApiAuth(url)) return url;
    // hlsExoAlias 已把 /api/hls 改成 /api/hls.m3u8，两种都要认
    final path = uri.path.toLowerCase();
    if (!path.startsWith('/api/hls')) return url;

    final q = Map<String, String>.from(uri.queryParameters);
    if (q['client'] == 'tv') return url;
    q['client'] = 'tv';
    return uri.replace(queryParameters: q).toString();
  }

  static String prepareMediaUrl(String link) {
    final url = resolve(link);
    if (url.isEmpty) return url;
    if (needsServerApiAuth(url)) {
      return appendPrivateAccessQuery(url);
    }
    return url;
  }

  /// 需服务端 /filmPlayInfo 二次解链的占位链。
  static bool isDeferredCollectLink(String link) {
    final lower = link.trim().toLowerCase();
    if (lower.isEmpty) return false;
    return lower.startsWith('91porna:') ||
        lower.startsWith('missav:') ||
        lower.startsWith('chigua51:') ||
        lower.startsWith('tianmei:') ||
        lower.startsWith('lissav:') ||
        lower.startsWith('sihu:') ||
        lower.startsWith('ck69:') ||
        lower.startsWith('av591:');
  }

  static bool isPlayableLink(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return false;
    final lower = raw.toLowerCase();
    if (lower.startsWith('91porna:') ||
        lower.startsWith('missav:') ||
        lower.startsWith('chigua51:') ||
        lower.startsWith('tianmei:') ||
        lower.startsWith('lissav:') ||
        lower.startsWith('sihu:') ||
        lower.startsWith('ck69:') ||
        lower.startsWith('av591:')) {
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
