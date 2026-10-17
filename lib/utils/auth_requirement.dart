import '../models/film_models.dart';
import '../services/app_catalog_service.dart';

/// 是否必须登录后才能使用前台 API（对齐 Web SiteGuard）。
class AuthRequirement {
  AuthRequirement._();

  static bool mustLogin({BasicConfig? siteConfig}) {
    if (siteConfig?.loginRequired == true) return true;
    final catalog = AppCatalogService.instance.catalog;
    if (catalog != null && catalog.requireWebLogin) return true;
    return false;
  }
}
