import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../common/app_branding.dart';
import '../common/app_theme.dart';
import '../services/auth_session.dart';
import '../services/app_catalog_service.dart';
import '../utils/server_config_manager.dart';
import '../utils/source_guard.dart';
import '../utils/site_heartbeat.dart';
import '../api/http_client.dart';
import '../api/film_api.dart';
import '../components/app_icon.dart';
import '../components/server_history_dialog.dart';
import 'main_scaffold_page.dart';

/// 软件源配置页，对齐 OHOS `ServerConfigPage`
class ServerConfigPage extends StatefulWidget {
  final String mode;

  const ServerConfigPage({super.key, this.mode = ''});

  @override
  State<ServerConfigPage> createState() => _ServerConfigPageState();
}

class _ServerConfigPageState extends State<ServerConfigPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  List<String> _serverHistory = [];
  bool _reconnect = false;
  int _lastBackPressMs = 0;

  @override
  void initState() {
    super.initState();
    _reconnect = widget.mode == 'reconnect';
    _loadInitial();
  }

  @override
  void dispose() {
    _controller.dispose();
    SourceGuard.markClosed();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    _controller.text = await ServerConfigManager.instance.getServerUrl();
    _serverHistory = await ServerConfigManager.instance.getServerHistory();
    if (mounted) setState(() {});
  }

  Future<void> _loadHistory() async {
    final list = await ServerConfigManager.instance.getServerHistory();
    if (mounted) {
      setState(() {
        _serverHistory = list;
      });
    }
  }

  Future<void> _saveAndConnect() async {
    FocusScope.of(context).unfocus();
    final url = _controller.text.trim();
    if (url.isEmpty) {
      _toast('请输入服务端地址');
      return;
    }

    setState(() => _isLoading = true);
    final res = await HttpClient.instance.testConnection(url);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!res.ok) {
      _toast(res.message ?? '无法连接该源，请检查地址');
      return;
    }

    final newOrigin = ServerConfigManager.stripApiSuffix(
      ServerConfigManager.instance.normalizeRaw(url),
    );
    final sameServer = newOrigin == ServerConfigManager.instance.getOrigin();
    if (!sameServer) {
      // 切到不同服务端才清空登录态；同源重连保留会话，避免无谓地弹登录
      await AuthSession.instance.clear();
      AppCatalogService.instance.clear();
    }
    await ServerConfigManager.instance.setServerUrl(url);
    await _loadHistory();
    FilmApi.clearSiteConfig();
    SiteHeartbeat.instance.resetFailures();
    MainScaffoldPage.resetNoticeSession();
    SourceGuard.markReconnectedCooldown();

    if (!mounted) return;
    _toast(_reconnect ? '已重新接入' : '源已接入');
    Navigator.of(context).pushNamedAndRemoveUntil(
      AuthSession.instance.isLoggedIn ? '/main' : '/login',
      (route) => false,
    );
    SourceGuard.notifyReconnected();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onReconnectBack() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBackPressMs < 2000) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPressMs = now;
    _toast('再按一次退出应用');
  }

  void _showHistoryDialog() {
    FocusScope.of(context).unfocus();
    final currentFull = _controller.text.trim();
    showServerHistoryDialog(
      context: context,
      historyOf: () => _serverHistory,
      currentUrl: currentFull,
      onSelect: (item) {
        setState(() {
          _controller.text = item;
        });
      },
      onReload: _loadHistory,
      onToastCleared: () => _toast('已清空历史服务端地址'),
    );
  }

  Widget _brand({required bool landscape}) {
    final subtitle = _reconnect
        ? (landscape ? '服务端连接失败\n请重新配置' : '服务端连接失败，请检查后重试')
        : (landscape ? '配置服务端后登录' : '填写服务端地址，使用网站账号登录');
    final iconSize = landscape ? 72.0 : 88.0;
    final iconRadius = landscape ? 16.0 : 20.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StartIconImage(size: iconSize, radius: iconRadius),
        SizedBox(height: landscape ? 8 : 14),
        Text(
          AppBranding.displayName,
          style: TextStyle(
            fontSize: landscape ? 22 : 26,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        SizedBox(height: landscape ? 4 : 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: landscape ? 11 : 13,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _form({required bool landscape}) {
    final inputH = landscape ? 42.0 : 48.0;
    final inputFont = landscape ? 13.0 : 14.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '服务端地址',
              style: TextStyle(fontSize: landscape ? 12 : 13, color: AppTheme.textSecondary),
            ),
            if (_serverHistory.isNotEmpty)
              GestureDetector(
                onTap: _showHistoryDialog,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: landscape ? 6 : 8, vertical: landscape ? 3 : 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, size: landscape ? 11 : 12, color: AppTheme.accent),
                      const SizedBox(width: 4),
                      Text(
                        '历史记录 (${_serverHistory.length})',
                        style: TextStyle(fontSize: landscape ? 11 : 12, color: AppTheme.accent),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: landscape ? 6 : 8),
        Container(
          height: inputH,
          padding: EdgeInsets.only(left: landscape ? 12 : 14, right: 4),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: TextStyle(fontSize: inputFont, color: AppTheme.textPrimary),
                  cursorColor: AppTheme.accent,
                  decoration: InputDecoration(
                    hintText: 'http://192.168.x.x:3008 或 https://域名',
                    hintStyle: TextStyle(fontSize: inputFont, color: AppTheme.textMuted),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _saveAndConnect(),
                ),
              ),
              if (_controller.text.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _controller.clear()),
                  child: SizedBox(
                    width: landscape ? 32 : 36,
                    height: inputH,
                    child: Icon(Icons.cancel_rounded, size: landscape ? 15 : 16, color: AppTheme.textMuted),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: landscape ? 12 : 24),
        SizedBox(
          width: double.infinity,
          height: inputH,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.textPrimary,
              disabledBackgroundColor: AppTheme.accent.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
              elevation: 0,
            ),
            onPressed: _isLoading ? null : _saveAndConnect,
            child: Text(
              _isLoading ? '正在连接...' : (_reconnect ? '重新接入' : '开始观影'),
              style: TextStyle(fontSize: landscape ? 15 : 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final canBack = !_reconnect && Navigator.canPop(context);

    return PopScope(
      canPop: !_reconnect,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onReconnectBack();
      },
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              if (canBack)
                SizedBox(
                  height: landscape ? 36 : 48,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppTheme.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              landscape ? 16 : 24,
                              landscape ? 4 : 20,
                              landscape ? 16 : 24,
                              24,
                            ),
                            child: landscape
                                ? Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(width: 160, child: _brand(landscape: true)),
                                      const SizedBox(width: 28),
                                      Expanded(
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 440),
                                          child: _form(landscape: true),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _brand(landscape: false),
                                      const SizedBox(height: 28),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 480),
                                        child: _form(landscape: false),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
