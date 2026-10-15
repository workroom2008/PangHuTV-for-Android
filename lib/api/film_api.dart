import 'dart:async';
import 'http_client.dart';
import '../models/film_models.dart';
import '../models/api_parser.dart';

typedef ConfigListener = void Function(BasicConfig config);

/// 影视业务 API
class FilmApi {
  static BasicConfig? _siteConfig;
  static Future<BasicConfig>? _configFuture;
  static final List<ConfigListener> _configListeners = [];

  static void onConfigChange(ConfigListener listener) {
    if (!_configListeners.contains(listener)) {
      _configListeners.add(listener);
    }
  }

  static void offConfigChange(ConfigListener listener) {
    _configListeners.remove(listener);
  }

  static Future<HomeData> getHome({String sourceId = ''}) async {
    final params = sourceId.trim().isNotEmpty ? {'source': sourceId.trim()} : null;
    final res = await HttpClient.instance.get('/index', params: params);
    if (res.code != 0 || res.data == null) {
      throw Exception(res.msg.isNotEmpty ? res.msg : '首页数据获取失败');
    }
    return ApiParser.parseHome(res.data);
  }

  static Future<DailyUpdateResult> getDailyUpdates(
    int pid,
    int current, {
    int pageSize = 21,
    String sourceId = '',
  }) async {
    final params = {
      'pid': pid,
      'current': current,
      'pageSize': pageSize,
      if (sourceId.trim().isNotEmpty) 'source': sourceId.trim(),
    };
    final res = await HttpClient.instance.get('/dailyUpdates', params: params);
    if (res.code != 0 || res.data == null) {
      throw Exception(res.msg.isNotEmpty ? res.msg : '每日更新获取失败');
    }
    return ApiParser.parseDailyUpdate(res.data);
  }

  static Future<BasicConfig> getSiteConfig({
    bool force = false,
    int timeoutMs = 15000,
  }) async {
    if (!force && _siteConfig != null) {
      return _siteConfig!;
    }
    if (_configFuture != null) {
      return _configFuture!;
    }
    _configFuture = () async {
      try {
        final res = await HttpClient.instance.get('/config/basic', timeoutMs: timeoutMs);
        if (res.code != 0 || res.data == null) {
          throw Exception(res.msg.isNotEmpty ? res.msg : '站点配置获取失败');
        }
        final config = ApiParser.parseBasicConfig(res.data);
        _siteConfig = config;
        for (final l in List<ConfigListener>.from(_configListeners)) {
          l(config);
        }
        return config;
      } finally {
        _configFuture = null;
      }
    }();
    return _configFuture!;
  }

  static void clearSiteConfig() {
    _siteConfig = null;
    _configFuture = null;
  }

  static Future<List<String>> getHotKeywords({int limit = 8}) async {
    final res = await HttpClient.instance.get('/hotKeywords', params: {'limit': limit});
    if (res.code != 0 || res.data == null) return [];
    return ApiParser.parseStringList(res.data);
  }

  static Future<SearchResult> searchFilm(String keyword, {int current = 1, String source = ''}) async {
    final params = {
      'keyword': keyword,
      'current': current,
      if (source.isNotEmpty) 'source': source,
    };
    final res = await HttpClient.instance.get('/searchFilm', params: params);
    if (res.code != 0 || res.data == null) {
      return SearchResult(
        list: [],
        page: PageInfo(pageSize: 10, current: current, pageCount: 0, total: 0),
        error: '搜索失败',
      );
    }
    return ApiParser.parseSearch(res.data);
  }

  static Future<FilterResult> getFilter(
    Map<String, dynamic> query, {
    String sourceId = '',
  }) async {
    final params = Map<String, dynamic>.from(query);
    final sid = sourceId.trim();
    if (sid.isNotEmpty) {
      params['source'] = sid;
    }
    final res = await HttpClient.instance.get('/filmClassifySearch', params: params);
    if (res.code != 0 || res.data == null) {
      throw Exception(res.msg.isNotEmpty ? res.msg : '筛选数据获取失败');
    }
    return ApiParser.parseFilter(res.data);
  }

  static Future<PlayInfo> getPlayInfo(
    String id, {
    String playFrom = '',
    int episode = 0,
    String sid = '',
  }) async {
    if ((id.isEmpty || id == '0') && sid.isNotEmpty) {
      return getLivePlayInfo(playFrom, sid, episode: episode);
    }
    final params = {
      'id': id,
      'playFrom': playFrom,
      'episode': episode,
      if (sid.isNotEmpty) 'sid': sid,
    };
    final res = await HttpClient.instance.get('/filmPlayInfo', params: params, timeoutMs: 20000);
    if (res.code != 0 || res.data == null) {
      throw Exception(res.msg.isNotEmpty ? res.msg : '播放数据获取失败');
    }
    return ApiParser.parsePlay(res.data);
  }

  static Future<PlayInfo> getLivePlayInfo(
    String source,
    String sid, {
    int episode = 0,
  }) async {
    final params = {
      'source': source,
      'sid': sid,
      'episode': episode,
    };
    final res = await HttpClient.instance.get('/liveFilmPlayInfo', params: params, timeoutMs: 20000);
    if (res.code != 0 || res.data == null) {
      throw Exception(res.msg.isNotEmpty ? res.msg : '现场播放数据获取失败');
    }
    return ApiParser.parsePlay(res.data);
  }

  static Future<List<MovieBasicInfo>> getRelate(String id) async {
    final res = await HttpClient.instance.get('/filmRelate', params: {'id': id});
    if (res.code != 0 || res.data == null) return [];
    if (res.data is List) {
      return ApiParser.parseMovies(res.data);
    }
    return [];
  }

  static Future<List<MovieBasicInfo>> getLiveRelate(
    String source, {
    dynamic cid = 0,
    dynamic sid = 0,
  }) async {
    final params = {
      'source': source,
      'cid': cid ?? 0,
      'sid': sid ?? 0,
    };
    final res = await HttpClient.instance.get('/liveFilmRelate', params: params);
    if (res.code != 0 || res.data == null) return [];
    if (res.data is List) {
      return ApiParser.parseMovies(res.data);
    }
    return [];
  }
}
