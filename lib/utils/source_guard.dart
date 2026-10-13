import 'dart:async';
import 'package:flutter/material.dart';
import '../common/app_theme.dart';
import '../services/route_observer.dart';
import 'server_config_manager.dart';

/// 软件源断连拦截与重连广播，对齐 OHOS `SourceGuard`
class SourceGuard {
  static bool _intercepting = false;
  static int _skipCount = 0;
  static Timer? _reconnectSkipTimer;
  static final List<VoidCallback> _listeners = [];
  static GlobalKey<NavigatorState>? navigatorKey;

  static void markReconnectedCooldown([Duration duration = const Duration(seconds: 4)]) {
    _intercepting = false;
    if (_reconnectSkipTimer != null) {
      _reconnectSkipTimer!.cancel();
      _reconnectSkipTimer = null;
      endSkip();
    }
    beginSkip();
    _reconnectSkipTimer = Timer(duration, () {
      endSkip();
      _reconnectSkipTimer = null;
    });
  }

  @visibleForTesting
  static int get skipCount => _skipCount;

  static void beginSkip() {
    _skipCount++;
  }

  static void endSkip() {
    if (_skipCount > 0) {
      _skipCount--;
    }
  }

  static void onReconnect(VoidCallback listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  static void offReconnect(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void intercept({VoidCallback? onContinue}) {
    if (_skipCount > 0 || _intercepting) {
      return;
    }
    if (ServerConfigManager.instance.getCachedServerUrl().isEmpty) {
      return;
    }
    final name = EcoHubRouteObserver.currentName;
    if (name == EcoHubRouteObserver.serverConfig) {
      return;
    }
    if (name == EcoHubRouteObserver.play) {
      _showPlayConfirm(onContinue);
      return;
    }
    _doNavigate();
  }

  static void _showPlayConfirm(VoidCallback? onContinue) {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) {
      _doNavigate();
      return;
    }
    _intercepting = true;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppTheme.bgElevated,
            title: const Text('服务端失联', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
            content: const Text(
              '检测到当前服务端连接异常，是否前往重新配置？',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _intercepting = false;
                  onContinue?.call();
                },
                child: const Text('继续观看', style: TextStyle(color: AppTheme.textMuted)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _doNavigate();
                },
                child: const Text('更换服务端', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  static void _doNavigate() {
    final nav = navigatorKey?.currentState;
    if (nav == null) {
      _intercepting = false;
      return;
    }
    _intercepting = true;
    nav.pushNamed('/server_config', arguments: {'mode': 'reconnect'}).then((_) {
      // 配源页 dispose 会 markClosed；若被意外 pop 也要放开锁
    }).catchError((_) {
      _intercepting = false;
    });
  }

  static void markClosed() {
    _intercepting = false;
  }

  static void notifyReconnected() {
    _intercepting = false;
    final copy = List<VoidCallback>.from(_listeners);
    for (final l in copy) {
      l();
    }
  }
}
