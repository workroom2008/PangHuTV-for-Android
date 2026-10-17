import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../api/http_client.dart';
import '../services/route_observer.dart';
import '../utils/site_heartbeat.dart';

/// Token 失效时统一跳转登录。
class AuthGate {
  static GlobalKey<NavigatorState>? navigatorKey;
  static bool _handling = false;

  static void markLoggedIn() {
    _handling = false;
  }

  static Future<void> handleUnauthorized() async {
    if (_handling) return;
    final route = EcoHubRouteObserver.currentName;
    if (route == '/login' || route == '/') return;

    _handling = true;
    SiteHeartbeat.instance.stop();
    try {
      await HttpClient.instance.post('/logout', skipUnauthorizedRedirect: true);
    } catch (_) {}
    try {
      await AuthApi.logoutLocal();
    } catch (_) {}

    final nav = navigatorKey?.currentState;
    if (nav != null && EcoHubRouteObserver.currentName != '/login') {
      nav.pushNamedAndRemoveUntil('/login', (route) => false);
    }

    Future.delayed(const Duration(seconds: 2), () {
      _handling = false;
    });
  }
}
