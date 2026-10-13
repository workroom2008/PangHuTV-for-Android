import 'package:flutter/material.dart';
import '../common/app_theme.dart';
import '../components/page_header.dart';
import '../api/auth_api.dart';
import '../utils/app_settings_manager.dart';

/// 设置页面，全量对齐 OHOS `SettingsPage.ets`
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _cacheSize = '0.0 MB';

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  Future<void> _refreshCacheSize() async {
    final size = await AppSettingsManager.instance.getCacheSize();
    if (mounted) {
      setState(() {
        _cacheSize = size;
      });
    }
  }

  void _handleClearCache() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
        title: const Text(
          '清理本地缓存',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        content: const Text(
          '确定清理本地缓存吗？',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await AppSettingsManager.instance.clearCache();
              await _refreshCacheSize();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('缓存已清理'),
                  duration: Duration(milliseconds: 1500),
                ),
              );
            },
            child: const Text(
              '清理',
              style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
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

  Widget _cardDivider() {
    return Divider(
      color: Colors.white.withValues(alpha: 0.06),
      height: 0.5,
      indent: 16,
      endIndent: 16,
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            activeThumbColor: AppTheme.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required String title,
    required String subtitle,
    required String extra,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              extra,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            const PageHeader(title: '设置'),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppTheme.contentMaxWidth),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. 播放设置分类
                        _sectionTitle('播放'),
                        ValueListenableBuilder<bool>(
                          valueListenable: AppSettingsManager.instance.pipAutoStartNotifier,
                          builder: (context, pipAutoStart, _) {
                            return ValueListenableBuilder<bool>(
                              valueListenable: AppSettingsManager.instance.autoPlayNextNotifier,
                              builder: (context, autoPlayNext, _) {
                                return Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.bgElevated,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.08),
                                      width: 0.5,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    children: [
                                      _buildSwitchRow(
                                        title: '回到桌面开启画中画',
                                        subtitle: '返回桌面时自动开启小窗悬浮',
                                        value: pipAutoStart,
                                        onChanged: (v) => AppSettingsManager.instance.setPipAutoStart(v),
                                      ),
                                      _cardDivider(),
                                      _buildSwitchRow(
                                        title: '自动连播下一集',
                                        subtitle: '当前视频播完后自动播放下一集',
                                        value: autoPlayNext,
                                        onChanged: (v) => AppSettingsManager.instance.setAutoPlayNext(v),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 14),

                        // 2. 通用设置分类
                        _sectionTitle('通用'),
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.bgElevated,
                            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 0.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              _buildActionRow(
                                title: '清理本地缓存',
                                subtitle: '清理图片与临时网络数据',
                                extra: _cacheSize,
                                onTap: _handleClearCache,
                              ),
                              _cardDivider(),
                              _buildActionRow(
                                title: '退出登录',
                                subtitle: '清除本机 Token，需重新登录',
                                extra: '',
                                onTap: () async {
                                  await AuthApi.logout();
                                  if (!context.mounted) return;
                                  Navigator.of(context).pushNamedAndRemoveUntil(
                                    '/login',
                                    (route) => false,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
