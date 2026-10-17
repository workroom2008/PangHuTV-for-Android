import 'package:flutter/material.dart';

import '../common/app_theme.dart';
import '../components/loading_view.dart';
import '../components/page_header.dart';
import '../models/external_player_app.dart';
import '../utils/app_settings_manager.dart';
import '../utils/external_player.dart';

/// 选择默认调起的第三方播放器（Android）
class ExternalPlayerPickerPage extends StatefulWidget {
  const ExternalPlayerPickerPage({super.key});

  @override
  State<ExternalPlayerPickerPage> createState() => _ExternalPlayerPickerPageState();
}

class _ExternalPlayerPickerPageState extends State<ExternalPlayerPickerPage> {
  bool _loading = true;
  String _error = '';
  List<ExternalPlayerApp> _apps = [];
  String _selected = '';

  @override
  void initState() {
    super.initState();
    _selected = AppSettingsManager.instance.externalPlayerPackage;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final list = await ExternalPlayer.listInstalled();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _apps = list;
      if (_apps.isEmpty) {
        _error = '未检测到可用的第三方播放器，请先安装 MX Player、VLC 等应用';
      }
    });
  }

  Future<void> _pick(ExternalPlayerApp app) async {
    await AppSettingsManager.instance.setExternalPlayer(
      packageName: app.packageName,
      label: app.isSystemDefault ? '' : app.label,
    );
    if (!mounted) return;
    setState(() => _selected = app.packageName);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            const PageHeader(title: '选择播放器'),
            Expanded(
              child: _loading
                  ? const LoadingView(label: '正在扫描本机播放器')
                  : _error.isNotEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _error,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            _tile(
                              const ExternalPlayerApp(packageName: '', label: '系统选择器（每次手动选）'),
                              subtitle: '调起 Android 应用选择器，不固定某一播放器',
                            ),
                            const SizedBox(height: 8),
                            ..._apps.map(
                              (app) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _tile(app, subtitle: app.packageName),
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(ExternalPlayerApp app, {required String subtitle}) {
    final selected = _selected == app.packageName;
    return Material(
      color: AppTheme.bgElevated,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        onTap: () => _pick(app),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? AppTheme.accent : AppTheme.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
