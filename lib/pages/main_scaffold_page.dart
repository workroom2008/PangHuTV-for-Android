import 'dart:async';

import 'package:flutter/material.dart';
import '../common/app_branding.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../api/film_api.dart';
import '../services/app_catalog_service.dart';
import '../services/auth_session.dart';
import '../services/front_download_service.dart';
import '../utils/server_config_manager.dart';
import '../utils/site_heartbeat.dart';
import '../utils/collect_source_scope.dart';
import '../utils/source_guard.dart';
import '../utils/app_version_util.dart';
import '../api/http_client.dart';
import '../components/notice_dialog.dart';
import '../components/version_update_dialog.dart';
import '../components/loading_view.dart';
import 'recommend_tab.dart';
import 'daily_updates_tab.dart';
import 'profile_tab.dart';

/// 主框架脚手架页面
class MainScaffoldPage extends StatefulWidget {
  const MainScaffoldPage({super.key});

  static void resetNoticeSession() {
    _MainScaffoldPageState.resetNoticeSession();
  }

  @override
  State<MainScaffoldPage> createState() => _MainScaffoldPageState();
}

class _MainScaffoldPageState extends State<MainScaffoldPage> with WidgetsBindingObserver {
  /// 会话内最近一次关闭的公告指纹（换源清空；公告变动后再弹）
  static String _dismissedNoticeKey = '';

  static void resetNoticeSession() {
    _dismissedNoticeKey = '';
  }

  int _currentTabIndex = 0;
  String _siteName = AppBranding.displayName;
  bool _siteOpen = true;
  String _siteHint = '';
  bool _ready = false;
  bool _showNotice = false;
  String _noticeTitle = '站点公告';
  String _noticeContent = '';
  String _currentNoticeKey = '';
  bool _hasAppUpdate = false;
  bool _showUpdateDialog = false;
  final List<bool> _tabReady = [true, false, false];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FilmApi.onConfigChange(_onConfigChange);
    SourceGuard.onReconnect(_onReconnect);
    AppVersionUtil.hasUpdate.addListener(_onHasUpdate);
    AppVersionUtil.showUpdateDialog.addListener(_onShowUpdateDialog);
    _hasAppUpdate = AppVersionUtil.hasUpdate.value;
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SiteHeartbeat.instance.stop();
    FilmApi.offConfigChange(_onConfigChange);
    SourceGuard.offReconnect(_onReconnect);
    AppVersionUtil.hasUpdate.removeListener(_onHasUpdate);
    AppVersionUtil.showUpdateDialog.removeListener(_onShowUpdateDialog);
    super.dispose();
  }

  void _onHasUpdate() {
    if (!mounted) return;
    setState(() {
      _hasAppUpdate = AppVersionUtil.hasUpdate.value;
    });
  }

  void _onShowUpdateDialog() {
    if (!mounted) return;
    setState(() {
      _showUpdateDialog = AppVersionUtil.showUpdateDialog.value;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (ServerConfigManager.instance.getCachedServerUrl().isNotEmpty) {
        SiteHeartbeat.instance.start();
      }
      if (_ready) {
        _loadSite(false);
      }
    } else if (state == AppLifecycleState.paused) {
      SiteHeartbeat.instance.stop();
    }
  }

  void _onReconnect() {
    FrontDownloadService.instance.reset();
    unawaited(FrontDownloadService.instance.refresh());
    _loadSite(false);
  }

  void _onConfigChange(BasicConfig config) {
    if (!mounted) return;
    setState(() {
      _siteName = config.siteName.isNotEmpty ? config.siteName : AppBranding.displayName;
      _siteOpen = config.state;
      _siteHint = config.hint;
    });
    _checkNotice(config);
  }

  Future<void> _checkNotice(BasicConfig config) async {
    if (!config.state || !config.noticeEnabled || !config.noticeShowInApp || config.noticeContent.trim().isEmpty) {
      if (mounted) setState(() => _showNotice = false);
      return;
    }
    final targetVersion = config.noticeAppVersion.isNotEmpty ? config.noticeAppVersion : config.noticeVersion;
    final appVersion = await AppVersionUtil.getVersionName();
    final isMatched = AppVersionUtil.isVersionMatched(appVersion, targetVersion);

    final serverUrl = ServerConfigManager.instance.getCachedServerUrl();
    final content = config.noticeContent.trim();
    final summary = content.length > 32 ? content.substring(0, 32) : content;
    final noticeKey = '$serverUrl::${config.noticeTitle.trim()}::${content.length}_$summary';

    if (isMatched && _dismissedNoticeKey != noticeKey) {
      if (!mounted) return;
      setState(() {
        _noticeTitle = config.noticeTitle.isNotEmpty ? config.noticeTitle : '站点公告';
        _noticeContent = config.noticeContent;
        _currentNoticeKey = noticeKey;
        _showNotice = true;
      });
    } else if (!isMatched || _dismissedNoticeKey == noticeKey) {
      if (!mounted) return;
      setState(() {
        _showNotice = false;
      });
    }
  }

  Future<void> _bootstrap() async {
    AppVersionUtil.checkUpdate(force: false).then((info) {
      if (mounted) {
        setState(() {
          _hasAppUpdate = info.hasUpdate;
        });
      }
    }).catchError((_) {});

    final url = await ServerConfigManager.instance.getServerUrl();
    if (url.isEmpty) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/server_config');
      }
      return;
    }
    if (!AuthSession.instance.isLoggedIn) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }
    try {
      await AppCatalogService.instance.refresh();
      await CollectSourceScope.instance.ensureLoaded();
      CollectSourceScope.instance.syncFromCatalog(
        AppCatalogService.instance.collectSources.map((e) => e.id).toList(),
      );
    } catch (_) {}

    unawaited(FrontDownloadService.instance.refresh());
    await _loadSite(false);
    HttpClient.instance.trackView('browse', '', 'IndexPage');
    SiteHeartbeat.instance.start();
  }

  Future<void> _loadSite(bool first) async {
    if (first) {
      setState(() {
        _ready = false;
      });
    }
    try {
      final config = await FilmApi.getSiteConfig(force: first);
      if (!mounted) return;
      setState(() {
        _siteName = config.siteName.isNotEmpty ? config.siteName : AppBranding.displayName;
        _siteOpen = config.state;
        _siteHint = config.hint;
        _ready = true;
      });
      _checkNotice(config);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _siteOpen = true;
        _ready = true;
      });
    }
  }

  void _selectTab(int index) {
    setState(() {
      _currentTabIndex = index;
      _tabReady[index] = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showNoticeOverlay = _showNotice && _ready && _siteOpen;
    final showUpdateOverlay = _showUpdateDialog && AppVersionUtil.getCachedUpdateInfo() != null;
    final hasModalOverlay = showNoticeOverlay || showUpdateOverlay;

    final scaffold = Scaffold(
      backgroundColor: AppTheme.bg,
      body: !_ready
          ? const LoadingView(label: '正在接入服务')
          : !_siteOpen
              ? _buildMaintenanceView()
              : IndexedStack(
                  index: _currentTabIndex,
                  children: [
                    if (_tabReady[0])
                      RecommendTab(
                        siteName: _siteName,
                        onOpenSearch: () => Navigator.pushNamed(context, '/search'),
                      )
                    else
                      const SizedBox.shrink(),
                    if (_tabReady[1])
                      const DailyUpdatesTab()
                    else
                      const SizedBox.shrink(),
                    if (_tabReady[2])
                      const ProfileTab()
                    else
                      const SizedBox.shrink(),
                  ],
                ),
      bottomNavigationBar: _ready && _siteOpen
          ? Container(
              decoration: const BoxDecoration(
                color: AppTheme.bgElevated,
                border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
              ),
              child: BottomNavigationBar(
                currentIndex: _currentTabIndex,
                onTap: _selectTab,
                items: [
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_rounded),
                    label: '推荐',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.local_fire_department_outlined),
                    activeIcon: Icon(Icons.local_fire_department_rounded),
                    label: '更新',
                  ),
                  BottomNavigationBarItem(
                    icon: Stack(
                      children: [
                        const Icon(Icons.person_outline_rounded),
                        if (_hasAppUpdate)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppTheme.danger,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    activeIcon: const Icon(Icons.person_rounded),
                    label: '我的',
                  ),
                ],
              ),
            )
          : null,
    );

    return PopScope(
      canPop: !hasModalOverlay,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (showNoticeOverlay) {
          if (_currentNoticeKey.isNotEmpty) {
            _dismissedNoticeKey = _currentNoticeKey;
          }
          setState(() {
            _showNotice = false;
          });
        } else if (showUpdateOverlay) {
          AppVersionUtil.showUpdateDialog.value = false;
          setState(() {
            _showUpdateDialog = false;
          });
        }
      },
      child: Stack(
        children: [
          scaffold,

          // Notice modal (全屏遮罩，完整覆盖包括 TabBar 在内的整个视口)
          if (showNoticeOverlay)
            NoticeDialog(
              title: _noticeTitle,
              content: _noticeContent,
              onClose: () {
                if (_currentNoticeKey.isNotEmpty) {
                  _dismissedNoticeKey = _currentNoticeKey;
                }
                setState(() {
                  _showNotice = false;
                });
              },
            ),

          // Version update modal
          if (showUpdateOverlay)
            VersionUpdateDialog(
              updateInfo: AppVersionUtil.getCachedUpdateInfo()!,
              onClose: () {
                AppVersionUtil.showUpdateDialog.value = false;
                setState(() {
                  _showUpdateDialog = false;
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(38),
              ),
              child: const Icon(Icons.info_outline_rounded, color: AppTheme.accent, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              _siteName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              ),
              child: const Text(
                '站点维护中',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accent),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              child: Text(
                _siteHint.isNotEmpty
                    ? _siteHint
                    : '当前站点正在进行系统维护，暂无法提供观影服务，请稍后刷新重试或更换服务端。',
                style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.bgCard,
                        foregroundColor: AppTheme.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                        ),
                      ),
                      onPressed: () => _loadSite(true),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('刷新重试'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                        ),
                      ),
                      onPressed: () => Navigator.pushNamed(context, '/server_config'),
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: const Text('更换服务端'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
