import 'dart:ui';
import 'package:flutter/material.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../api/film_api.dart';
import '../utils/collect_source_scope.dart';
import '../utils/source_guard.dart';
import '../models/app_catalog.dart';
import '../services/app_catalog_service.dart';
import '../utils/breakpoint.dart';
import '../components/loading_view.dart';
import '../components/empty_state.dart';
import '../api/http_client.dart';
import '../utils/favorite_manager.dart';
import 'daily_update_pane.dart';

const int _pageSize = 21;

/// 每日更新 Tab 页面，对齐 OHOS `DailyUpdatesTab.ets`
class DailyUpdatesTab extends StatefulWidget {
  const DailyUpdatesTab({super.key});

  @override
  State<DailyUpdatesTab> createState() => _DailyUpdatesTabState();
}

class _DailyUpdatesTabState extends State<DailyUpdatesTab> with TickerProviderStateMixin {
  List<DailyUpdateCategory> _categories = [];
  int _currentIndex = 0;
  bool _loading = true;
  String _errorText = '';
  bool _ready = false;
  int _seedPid = 0;
  List<MovieBasicInfo> _seedList = [];
  PageInfo _seedPage = PageInfo(pageSize: _pageSize, current: 1, pageCount: 1, total: 0);
  int _reloadToken = 0;
  int _siblingResetToken = 0;
  bool _hasLoaded = false;
  bool _fetchLock = false;

  late final PageController _pageController;
  final ScrollController _chipsScroller = ScrollController();
  List<GlobalKey> _chipKeys = [];
  VoidCallback? _reconnectCb;
  final _sourceScope = CollectSourceScope.instance;
  List<CollectSourceOption> _collectSources = [];

  @override
  void initState() {
    super.initState();
    FavoriteManager.preload();
    _pageController = PageController(initialPage: _currentIndex);
    _reconnectCb = () {
      FavoriteManager.preload();
      _reloadCatalog();
      _loadMeta(fromPull: false);
    };
    SourceGuard.onReconnect(_reconnectCb!);
    _sourceScope.addListener(_onSourceScopeChanged);
    _boot();
  }

  Future<void> _boot() async {
    await _sourceScope.ensureLoaded();
    _reloadCatalog();
    if (!_hasLoaded) {
      _loadMeta(fromPull: false);
    }
  }

  void _reloadCatalog() {
    final list = AppCatalogService.instance.collectSources;
    CollectSourceScope.instance.syncFromCatalog(list.map((e) => e.id).toList());
    if (mounted) {
      setState(() => _collectSources = list);
    }
  }

  void _onSourceScopeChanged() {
    if (!mounted) return;
    setState(() {
      _currentIndex = 0;
      _siblingResetToken++;
    });
    _loadMeta(fromPull: false);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _sourceScope.removeListener(_onSourceScopeChanged);
    if (_reconnectCb != null) {
      SourceGuard.offReconnect(_reconnectCb!);
    }
    _pageController.dispose();
    _chipsScroller.dispose();
    super.dispose();
  }

  void _syncChipKeys() {
    _chipKeys = List.generate(_categories.length, (_) => GlobalKey());
  }

  DailyUpdateCategory _currentCategory() {
    if (_currentIndex >= 0 && _currentIndex < _categories.length) {
      return _categories[_currentIndex];
    }
    return DailyUpdateCategory(pid: 0, name: '全部', count: 0);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  Future<void> _loadMeta({bool fromPull = false}) async {
    if (_fetchLock) return;
    _fetchLock = true;
    setState(() {
      _loading = true;
      _errorText = '';
      _ready = false;
      _categories = [];
      _seedList = [];
      _seedPid = 0;
      _currentIndex = 0;
    });

    try {
      final result = await FilmApi.getDailyUpdates(
        0,
        1,
        pageSize: _pageSize,
        sourceId: _sourceScope.activeId,
      );
      var cats = result.categories;
      if (cats.isEmpty) {
        cats = [DailyUpdateCategory(pid: 0, name: '全部', count: result.page.total)];
      }

      if (!mounted) return;

      setState(() {
        _categories = cats;
        _seedPid = 0;
        _seedList = result.list;
        _seedPage = result.page;
        _reloadToken++;
        _ready = true;
        _hasLoaded = true;
        _loading = false;
        _errorText = '';
      });
      _syncChipKeys();
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      if (fromPull && _ready) {
        _toast('已更新');
      }
    } catch (err) {
      if (!mounted) return;
      final msg = err.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() {
        _errorText = msg.isNotEmpty ? msg : '每日更新加载失败';
        _ready = false;
        _hasLoaded = false;
        _reloadToken++;
        _loading = false;
      });
      if (fromPull) {
        _toast(_errorText.isNotEmpty ? _errorText : '刷新失败');
      }
    } finally {
      _fetchLock = false;
    }
  }

  void _invalidateOtherPanes() {
    setState(() {
      _siblingResetToken++;
    });
  }

  void _trackCategory(int index) {
    if (index < 0 || index >= _categories.length) return;
    final cat = _categories[index];
    if (cat.pid > 0 || (cat.name.isNotEmpty && cat.name != '全部')) {
      HttpClient.instance.trackView(
        'classify',
        '${cat.pid}',
        'DailyUpdatesTab',
        '',
        cat.name,
      );
    }
  }

  void _selectIndex(int index) {
    if (index < 0 || index >= _categories.length || index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
    _focusChip(index);
    _trackCategory(index);
  }

  void _focusChip(int index) {
    if (index < 0 || index >= _chipKeys.length) return;
    final ctx = _chipKeys[index].currentContext;
    if (ctx == null) return;
    final renderObject = ctx.findRenderObject();
    final scrollable = Scrollable.maybeOf(ctx);
    if (scrollable == null || renderObject == null) return;
    scrollable.position.ensureVisible(
      renderObject,
      alignment: 0.5,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  double _headerHeight(double topInset, bool isWide, bool hasChips) {
    var h = topInset + 48.0;
    if (_collectSources.length > 1) {
      h += isWide ? 40 : 36;
    }
    if (hasChips) {
      h += isWide ? 46 : 42;
    }
    return h;
  }

  Widget _buildSourceChips(bool isWide, double leftInset, double rightInset) {
    final chips = <({String id, String name})>[
      (id: '', name: '综合'),
      ..._collectSources.map((s) => (id: s.id, name: s.name)),
    ];
    return Container(
      height: isWide ? 36 : 32,
      margin: const EdgeInsets.only(bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(
          left: AppTheme.spaceLg + leftInset,
          right: AppTheme.spaceLg + rightInset,
        ),
        child: Row(
          children: [
            for (final c in chips) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _sourceScope.pick(c.id),
                child: Container(
                  height: isWide ? 32 : 28,
                  padding: EdgeInsets.symmetric(horizontal: isWide ? 14 : 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _sourceScope.activeId == c.id
                        ? const Color(0x33FA8C16)
                        : const Color(0x0DFFFFFF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _sourceScope.activeId == c.id
                          ? AppTheme.accent
                          : const Color(0x1AFFFFFF),
                    ),
                  ),
                  child: Text(
                    c.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _sourceScope.activeId == c.id ? FontWeight.w600 : FontWeight.normal,
                      color: _sourceScope.activeId == c.id ? AppTheme.accent : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChip(int index, DailyUpdateCategory item, bool isWide) {
    final active = _currentIndex == index;
    return GestureDetector(
      key: _chipKeys.length > index ? _chipKeys[index] : null,
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectIndex(index),
      child: Container(
        height: isWide ? 35 : 32,
        padding: EdgeInsets.symmetric(horizontal: isWide ? 14 : 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppTheme.accent : const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(
            width: 0.5,
            color: active ? AppTheme.accent : const Color(0x14FFFFFF),
          ),
        ),
        child: Text(
          item.name,
          style: TextStyle(
            fontSize: isWide ? 13.5 : 13,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required double topInset,
    required double leftInset,
    required double rightInset,
    required bool isWide,
    required bool hasChips,
  }) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          padding: EdgeInsets.only(
            top: topInset,
            bottom: hasChips ? 8.0 : 4.0,
          ),
          decoration: const BoxDecoration(
            color: Color(0xB80A0B10), // rgba(10, 11, 16, 0.72)
            border: Border(
              bottom: BorderSide(
                width: 0.5,
                color: Color(0x14FFFFFF), // rgba(255, 255, 255, 0.08)
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row 1: Title Bar
              Container(
                height: 44,
                padding: EdgeInsets.only(
                  left: AppTheme.spaceLg + leftInset,
                  right: AppTheme.spaceLg + rightInset,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      size: 20,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '每日更新',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (_categories.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Text(
                        '·',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          children: [
                            const TextSpan(text: '近 24 小时 '),
                            TextSpan(
                              text: '${_currentCategory().count}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent,
                              ),
                            ),
                            const TextSpan(text: ' 部'),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _fetchLock ? null : () => _loadMeta(fromPull: false),
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0x0FFFFFFF), // rgba(255, 255, 255, 0.06)
                          shape: BoxShape.circle,
                          border: Border.all(
                            width: 0.5,
                            color: const Color(0x1AFFFFFF), // rgba(255, 255, 255, 0.10)
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
                                ),
                              )
                            : const Icon(
                                Icons.refresh_rounded,
                                size: 16,
                                color: AppTheme.textSecondary,
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_collectSources.length > 1) _buildSourceChips(isWide, leftInset, rightInset),

              // Row 2: Category Chips
              if (hasChips)
                Container(
                  height: isWide ? 40 : 36,
                  margin: EdgeInsets.only(
                    top: isWide ? 3 : 2,
                    bottom: isWide ? 3 : 4,
                  ),
                  child: SingleChildScrollView(
                    controller: _chipsScroller,
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.only(
                      left: AppTheme.spaceLg + leftInset,
                      right: AppTheme.spaceLg + rightInset,
                    ),
                    child: Row(
                      children: [
                        for (int i = 0; i < _categories.length; i++) ...[
                          if (i > 0) SizedBox(width: isWide ? 8 : AppTheme.spaceSm),
                          _buildChip(i, _categories[i], isWide),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topInset = media.padding.top;
    final leftInset = media.padding.left;
    final rightInset = media.padding.right;
    final isWide = Breakpoint.isWideWidth(media.size.width);
    final hasChips = _categories.length > 1;
    final headerHeight = _headerHeight(topInset, isWide, hasChips);

    Widget body;
    if (_loading && !_ready) {
      body = Padding(
        padding: EdgeInsets.only(
          top: headerHeight,
          left: leftInset,
          right: rightInset,
        ),
        child: const LoadingView(label: '正在加载今日更新'),
      );
    } else if (!_ready && _errorText.isNotEmpty) {
      body = Padding(
        padding: EdgeInsets.only(top: headerHeight, left: leftInset, right: rightInset),
        child: Center(
          child: SingleChildScrollView(
            child: EmptyState(
              title: '加载失败',
              subtitle: _errorText,
              icon: Icons.error_outline_rounded,
              action: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.bgCard,
                  foregroundColor: AppTheme.textPrimary,
                ),
                onPressed: () => _loadMeta(fromPull: false),
                child: const Text('重试'),
              ),
            ),
          ),
        ),
      );
    } else {
      body = PageView.builder(
        controller: _pageController,
        physics: _categories.length <= 1
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        itemCount: _categories.length,
        onPageChanged: (index) {
          if (_currentIndex != index) {
            setState(() {
              _currentIndex = index;
            });
            _focusChip(index);
            _trackCategory(index);
          }
        },
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final active = (index - _currentIndex).abs() <= 1;
          final isSeed = cat.pid == _seedPid;
          final paneKey =
              'daily_pane_${cat.pid}_${_sourceScope.activeId}_${_reloadToken}_${isSeed ? 0 : _siblingResetToken}';
          return DailyUpdatePane(
            key: ValueKey(paneKey),
            pid: cat.pid,
            active: active,
            seedPid: _seedPid,
            seedList: isSeed ? _seedList : null,
            seedPage: isSeed ? _seedPage : null,
            reloadToken: _reloadToken,
            headerHeight: headerHeight,
            collectSourceId: _sourceScope.activeId,
            onAllRefreshed: _invalidateOtherPanes,
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: body,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeader(
              context,
              topInset: topInset,
              leftInset: leftInset,
              rightInset: rightInset,
              isWide: isWide,
              hasChips: hasChips,
            ),
          ),
        ],
      ),
    );
  }
}

