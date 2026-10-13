import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../common/app_theme.dart';
import '../components/page_header.dart';
import '../components/app_icon.dart';
import '../components/version_update_dialog.dart';
import '../utils/app_version_util.dart';
import '../utils/nav_util.dart';

class _ProjectLinkItem {
  final String title;
  final String desc;
  final String url;
  final IconData icon;

  const _ProjectLinkItem({
    required this.title,
    required this.desc,
    required this.url,
    required this.icon,
  });
}

/// 关于页面，对齐 OHOS `AboutPage.ets`
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _appVersion = '1.0.1';
  bool _isCheckingVersion = false;
  bool _showUpdateDialog = false;
  AppUpdateInfo _updateInfo = AppUpdateInfo(
    currentVersion: '',
    latestVersion: '',
    hasUpdate: false,
    releaseName: '',
    releaseNotes: '',
    releaseUrl: '',
    downloadUrl: '',
  );

  static const List<_ProjectLinkItem> _projectLinks = [
    _ProjectLinkItem(
      title: '胖虎影视（PangHuTV）',
      desc: '服务端、Web 管理后台与前台源码',
      url: 'https://github.com/workroom2008/PangHuTV',
      icon: Icons.language_rounded,
    ),
    _ProjectLinkItem(
      title: 'EcoHub for Android',
      desc: 'Android 客户端应用源码',
      url: 'https://github.com/workroom2008/EcoHub-for-Android',
      icon: Icons.phone_android_rounded,
    ),
    _ProjectLinkItem(
      title: 'Telegram 交流群组',
      desc: '社区交流、反馈与动态探讨',
      url: 'https://t.me/ecohub_club',
      icon: Icons.chat_bubble_outline_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadVersion();
    final cached = AppVersionUtil.getCachedUpdateInfo();
    if (cached != null) {
      _updateInfo = cached;
    }
    // 进入关于页面时静默检查更新
    AppVersionUtil.checkUpdate(force: false).then((info) {
      if (mounted) {
        setState(() {
          _updateInfo = info;
        });
      }
    }).catchError((_) {});
  }

  Future<void> _loadVersion() async {
    final v = await AppVersionUtil.getVersionName();
    if (mounted) {
      setState(() {
        _appVersion = v;
      });
    }
  }

  Future<void> _handleCheckVersion({bool force = false}) async {
    if (_isCheckingVersion) return;

    if (!force && _updateInfo.hasUpdate) {
      setState(() {
        _showUpdateDialog = true;
      });
      return;
    }

    setState(() {
      _isCheckingVersion = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在检查版本更新...')),
    );

    try {
      final info = await AppVersionUtil.checkUpdate(force: true);
      if (!mounted) return;
      setState(() {
        _updateInfo = info;
        _isCheckingVersion = false;
      });

      if (info.hasUpdate) {
        setState(() {
          _showUpdateDialog = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('当前已是最新版本 (v$_appVersion)')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCheckingVersion = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('检查版本失败，请稍后重试')),
      );
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('链接已复制到剪贴板'),
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }

  Widget _buildLinkItem(_ProjectLinkItem item, bool isFirst, bool isLast) {
    return Column(
      children: [
        if (!isFirst)
          const Padding(
            padding: EdgeInsets.only(left: 56),
            child: Divider(color: AppTheme.border, height: 0.5),
          ),
        InkWell(
          onTap: () => NavUtil.openBrowser(item.url),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(item.icon, size: 18, color: AppTheme.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.desc,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.url,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.accent,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16, color: AppTheme.textMuted),
                  tooltip: '复制链接',
                  onPressed: () => _copyToClipboard(item.url),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                ),
                const Icon(Icons.chevron_right_rounded, size: 14, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                const PageHeader(title: '关于'),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: AppTheme.contentMaxWidth),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceLg, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. App 头部基础信息
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Column(
                                  children: [
                                    const StartIconImage(size: 72, radius: 20),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'EcoHub',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '版本 v$_appVersion',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      '自托管高性能多源影视聚合系统',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textSecondary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // 2. 版本更新卡片
                            Container(
                              decoration: BoxDecoration(
                                color: AppTheme.bgElevated,
                                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                                border: Border.all(color: AppTheme.border, width: 0.5),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _handleCheckVersion(),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: AppTheme.accentSoft,
                                            borderRadius: BorderRadius.circular(18),
                                          ),
                                          child: const Icon(
                                            Icons.refresh_rounded,
                                            size: 18,
                                            color: AppTheme.accent,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              const Text(
                                                '版本更新',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                              if (_updateInfo.hasUpdate) ...[
                                                const SizedBox(width: AppTheme.spaceSm),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.danger,
                                                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                                                  ),
                                                  child: const Text(
                                                    'NEW',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppTheme.textPrimary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _isCheckingVersion
                                              ? '检查中...'
                                              : (_updateInfo.hasUpdate
                                                  ? '发现新版本 v${_updateInfo.latestVersion}'
                                                  : 'v$_appVersion'),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: _updateInfo.hasUpdate ? FontWeight.w500 : FontWeight.normal,
                                            color: _updateInfo.hasUpdate ? AppTheme.accent : AppTheme.textMuted,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.chevron_right_rounded, size: 14, color: AppTheme.textMuted),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // 3. 相关项目地址列表
                            _sectionTitle('相关项目地址'),
                            Container(
                              decoration: BoxDecoration(
                                color: AppTheme.bgElevated,
                                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                                border: Border.all(color: AppTheme.border, width: 0.5),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: List.generate(
                                  _projectLinks.length,
                                  (index) => _buildLinkItem(
                                    _projectLinks[index],
                                    index == 0,
                                    index == _projectLinks.length - 1,
                                  ),
                                ),
                              ),
                            ),

                            // 4. 使用须知卡片
                            _sectionTitle('使用须知'),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.bgElevated,
                                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                                border: Border.all(color: AppTheme.border, width: 0.5),
                              ),
                              child: const Text(
                                'EcoHub 为开源自托管影视聚合系统，不提供、不存储任何影视文件。片源来自使用者自行配置的采集接口。请遵守所在地区的法律法规及源站使用约定，仅供学习与技术交流。',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ),

                            // 5. 版权与开源协议声明
                            const SizedBox(height: 24),
                            const Center(
                              child: Column(
                                children: [
                                  Text(
                                    '开源协议：MIT License',
                                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Copyright © 2026 workroom2008. All Rights Reserved.',
                                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showUpdateDialog && (_updateInfo.hasUpdate || AppVersionUtil.getCachedUpdateInfo() != null))
            VersionUpdateDialog(
              updateInfo: _updateInfo.hasUpdate ? _updateInfo : AppVersionUtil.getCachedUpdateInfo()!,
              onClose: () {
                setState(() {
                  _showUpdateDialog = false;
                });
              },
            ),
        ],
      ),
    );
  }
}
