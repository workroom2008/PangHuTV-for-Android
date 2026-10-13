import 'package:shared_preferences/shared_preferences.dart';
import '../utils/server_config_manager.dart';

const _keyTokenPrefix = 'auth_token@';

/// 与 Web 共用的登录 Token（按服务端 host 隔离）。
class AuthSession {
  static final AuthSession instance = AuthSession._();
  AuthSession._();

  String _cachedToken = '';

  String _storageKey() {
    final scope = ServerConfigManager.instance.storageScope();
    if (scope.isEmpty) return '';
    return '$_keyTokenPrefix$scope';
  }

  Future<void> init() async {
    await ServerConfigManager.instance.init();
    final key = _storageKey();
    if (key.isEmpty) {
      _cachedToken = '';
      return;
    }
    final pref = ServerConfigManager.instance.preferences ??
        await SharedPreferences.getInstance();
    _cachedToken = pref.getString(key) ?? '';
  }

  String get token => _cachedToken;

  bool get isLoggedIn => _cachedToken.trim().isNotEmpty;

  Future<void> saveToken(String token) async {
    _cachedToken = token.trim();
    final key = _storageKey();
    if (key.isEmpty) return;
    final pref = ServerConfigManager.instance.preferences ??
        await SharedPreferences.getInstance();
    await pref.setString(key, _cachedToken);
  }

  Future<void> clear() async {
    _cachedToken = '';
    final key = _storageKey();
    if (key.isEmpty) return;
    final pref = ServerConfigManager.instance.preferences ??
        await SharedPreferences.getInstance();
    await pref.remove(key);
  }
}
