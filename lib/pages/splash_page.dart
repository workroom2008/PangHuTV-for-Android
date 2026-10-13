import 'package:flutter/material.dart';
import '../common/app_branding.dart';
import '../common/app_theme.dart';
import '../services/auth_session.dart';
import '../services/app_catalog_service.dart';
import '../utils/server_config_manager.dart';
import '../utils/app_version_util.dart';
import '../api/film_api.dart';
import '../components/app_icon.dart';
import '../components/version_update_dialog.dart';

const int _minSplashTimeMs = 800;
const int _probeAttempts = 3;
const int _probeTimeoutMs = 5000;

/// 开屏自检页面，对齐 OHOS `SplashPage`
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String _statusText = '正在接入服务...';
  bool _showUpdateDialog = false;
  AppUpdateInfo? _updateInfo;

  @override
  void initState() {
    super.initState();
    _checkAndBootstrap();
  }

  Future<void> _checkAndBootstrap() async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    await ServerConfigManager.instance.init();
    await AuthSession.instance.init();

    final updateFuture = () async {
      try {
        return await AppVersionUtil.checkUpdate(force: false, timeoutMs: 2500);
      } catch (_) {
        return null;
      }
    }();

    final url = await ServerConfigManager.instance.getServerUrl();
    if (url.trim().isEmpty) {
      await _ensureMinTime(startTime, _minSplashTimeMs);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先配置服务端地址')),
        );
        Navigator.pushReplacementNamed(context, '/server_config');
      }
      return;
    }

    setState(() {
      _statusText = '正在检测服务端连通性...';
    });

    var ok = false;
    for (var i = 0; i < _probeAttempts; i++) {
      if (i > 0) {
        setState(() {
          _statusText = '正在重试服务端连通性 (${i + 1}/$_probeAttempts)...';
        });
      }
      try {
        await FilmApi.getSiteConfig(force: true, timeoutMs: _probeTimeoutMs);
        ok = true;
        break;
      } catch (_) {}
    }

    await _ensureMinTime(startTime, _minSplashTimeMs);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('服务端连接失败，请检查网络或重新配置')),
      );
      Navigator.pushReplacementNamed(
        context,
        '/server_config',
        arguments: {'mode': 'reconnect'},
      );
      return;
    }

    final fastUpdate = await Future.any<AppUpdateInfo?>([
      updateFuture,
      Future<AppUpdateInfo?>.delayed(const Duration(milliseconds: 50), () => null),
    ]);
    if (!mounted) return;
    if (fastUpdate != null && fastUpdate.hasUpdate) {
      setState(() {
        _updateInfo = fastUpdate;
        _showUpdateDialog = true;
      });
      return;
    }

    if (!AuthSession.instance.isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    setState(() => _statusText = '正在同步源目录...');
    try {
      await AppCatalogService.instance.refresh(force: true);
    } catch (_) {}
    _goMain();
  }

  void _goMain() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/main');
  }

  Future<void> _ensureMinTime(int startTime, int minTime) async {
    final elapsed = DateTime.now().millisecondsSinceEpoch - startTime;
    if (elapsed < minTime) {
      await Future.delayed(Duration(milliseconds: minTime - elapsed));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const StartIconImage(size: 84, radius: 20),
                  const SizedBox(height: 16),
                  const Text(
                    AppBranding.displayName,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _statusText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_showUpdateDialog && _updateInfo != null)
            VersionUpdateDialog(
              updateInfo: _updateInfo!,
              onClose: () {
                setState(() {
                  _showUpdateDialog = false;
                });
                _goMain();
              },
            ),
        ],
      ),
    );
  }
}
