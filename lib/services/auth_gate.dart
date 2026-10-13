import 'package:flutter/material.dart';
import '../api/auth_api.dart';

/// Token 失效时统一跳转登录。
class AuthGate {
  static GlobalKey<NavigatorState>? navigatorKey;
  static bool _handling = false;

  static Future<void> handleUnauthorized() async {
    if (_handling) return;
    _handling = true;
    try {
      await AuthApi.logout();
    } catch (_) {}
    final nav = navigatorKey?.currentState;
    if (nav != null) {
      nav.pushNamedAndRemoveUntil('/login', (route) => false);
    }
    _handling = false;
  }
}
