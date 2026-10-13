import 'film_models.dart';

class CollectSourceOption {
  final String id;
  final String name;
  final int grade;
  final String posterAspect;
  final String posterAspectResolved;

  CollectSourceOption({
    required this.id,
    required this.name,
    this.grade = 0,
    this.posterAspect = 'auto',
    this.posterAspectResolved = '16:10',
  });

  factory CollectSourceOption.fromJson(Map<String, dynamic> json) {
    return CollectSourceOption(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? json['id'] ?? ''}',
      grade: json['grade'] is int
          ? json['grade'] as int
          : int.tryParse('${json['grade']}') ?? 0,
      posterAspect: '${json['posterAspect'] ?? 'auto'}',
      posterAspectResolved: '${json['posterAspectResolved'] ?? '16:10'}',
    );
  }
}

class AppAuthInfo {
  final String mode;
  final String loginPath;
  final String logoutPath;

  const AppAuthInfo({
    this.mode = 'token',
    this.loginPath = '/login',
    this.logoutPath = '/logout',
  });

  factory AppAuthInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AppAuthInfo();
    return AppAuthInfo(
      mode: '${json['mode'] ?? 'token'}',
      loginPath: '${json['login_path'] ?? json['loginPath'] ?? '/login'}',
      logoutPath: '${json['logout_path'] ?? json['logoutPath'] ?? '/logout'}',
    );
  }
}

/// 服务端 /api/app/bootstrap 快照（采集源列表随后台配置更新）。
class AppCatalog {
  final String siteName;
  final String apiBase;
  final String serverVersion;
  final bool requireWebLogin;
  final AppAuthInfo auth;
  final String masterSourceId;
  final List<SearchSourceTab> searchSources;
  final List<CollectSourceOption> collectSources;

  AppCatalog({
    this.siteName = '',
    this.apiBase = '',
    this.serverVersion = '',
    this.requireWebLogin = true,
    this.auth = const AppAuthInfo(),
    this.masterSourceId = '',
    this.searchSources = const [],
    this.collectSources = const [],
  });

  factory AppCatalog.fromJson(Map<String, dynamic> json) {
    final searchRaw = json['search_sources'] ?? json['searchSources'];
    final collectRaw = json['collect_sources'] ?? json['collectSources'];
    final tabs = <SearchSourceTab>[];
    if (searchRaw is List) {
      for (final item in searchRaw) {
        if (item is Map) {
          tabs.add(SearchSourceTab(
            id: '${item['id'] ?? ''}',
            name: '${item['name'] ?? ''}',
            count: item['count'] is int
                ? item['count'] as int
                : int.tryParse('${item['count']}') ?? 0,
          ));
        }
      }
    }
    final sources = <CollectSourceOption>[];
    if (collectRaw is List) {
      for (final item in collectRaw) {
        if (item is Map<String, dynamic>) {
          sources.add(CollectSourceOption.fromJson(item));
        } else if (item is Map) {
          sources.add(CollectSourceOption.fromJson(item.cast<String, dynamic>()));
        }
      }
    }
    return AppCatalog(
      siteName: '${json['site_name'] ?? json['siteName'] ?? ''}',
      apiBase: '${json['api_base'] ?? json['apiBase'] ?? ''}',
      serverVersion: '${json['server_version'] ?? json['serverVersion'] ?? ''}',
      requireWebLogin: json['require_web_login'] == true ||
          json['requireWebLogin'] == true,
      auth: AppAuthInfo.fromJson(
        json['auth'] is Map ? (json['auth'] as Map).cast<String, dynamic>() : null,
      ),
      masterSourceId:
          '${json['master_source_id'] ?? json['masterSourceId'] ?? ''}',
      searchSources: tabs,
      collectSources: sources,
    );
  }
}
