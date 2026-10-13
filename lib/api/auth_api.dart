import '../services/auth_session.dart';
import '../services/app_catalog_service.dart';
import 'http_client.dart';

class AuthApi {
  static Future<void> login(String userName, String password) async {
    final res = await HttpClient.instance.post(
      '/login',
      body: {'userName': userName, 'password': password},
    );
    if (res.code != 0) {
      throw Exception(res.msg.isNotEmpty ? res.msg : '登录失败');
    }
    String token = '';
    if (res.data is Map) {
      final map = (res.data as Map).cast<String, dynamic>();
      token = '${map['token'] ?? ''}'.trim();
    }
    if (token.isEmpty) {
      throw Exception('服务端未返回 token');
    }
    await AuthSession.instance.saveToken(token);
    AppCatalogService.instance.clear();
    await AppCatalogService.instance.refresh(force: true);
  }

  static Future<void> logout() async {
    try {
      await HttpClient.instance.post('/logout');
    } catch (_) {}
    await AuthSession.instance.clear();
    AppCatalogService.instance.clear();
  }
}
