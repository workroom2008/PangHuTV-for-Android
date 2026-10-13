import '../api/http_client.dart';
import '../models/app_catalog.dart';
import '../models/film_models.dart';

/// 拉取并缓存服务端源目录；后台新增采集源后调用 refresh 即可同步。
class AppCatalogService {
  static final AppCatalogService instance = AppCatalogService._();
  AppCatalogService._();

  AppCatalog? _catalog;
  DateTime? _fetchedAt;

  AppCatalog? get catalog => _catalog;

  List<CollectSourceOption> get collectSources =>
      _catalog?.collectSources ?? const [];

  List<SearchSourceTab> get searchSources =>
      _catalog?.searchSources ?? const [];

  String get masterSourceId => _catalog?.masterSourceId ?? '';

  void clear() {
    _catalog = null;
    _fetchedAt = null;
  }

  Future<AppCatalog> refresh({bool force = false}) async {
    if (!force &&
        _catalog != null &&
        _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < const Duration(minutes: 5)) {
      return _catalog!;
    }
    final res = await HttpClient.instance.get('/app/bootstrap');
    if (res.code != 0 || res.data == null) {
      throw Exception(res.msg.isNotEmpty ? res.msg : '启动包获取失败');
    }
    if (res.data is! Map) {
      throw Exception('启动包格式错误');
    }
    final map = (res.data as Map).cast<String, dynamic>();
    _catalog = AppCatalog.fromJson(map);
    _fetchedAt = DateTime.now();
    return _catalog!;
  }
}
