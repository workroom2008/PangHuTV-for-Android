import 'dart:ui';
import 'package:flutter/material.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../utils/breakpoint.dart';
import '../utils/source_guard.dart';
import '../api/film_api.dart';
import '../models/app_catalog.dart';
import '../services/app_catalog_service.dart';
import '../components/loading_view.dart';
import '../components/empty_state.dart';
import '../components/film_row.dart';
import '../components/home_banner.dart';
import '../utils/favorite_manager.dart';

/// 首页推荐 Tab，对齐 OHOS `RecommendTab.ets`
class RecommendTab extends StatefulWidget {
  final String siteName;
  final VoidCallback? onOpenSearch;

  const RecommendTab({
    super.key,
    required this.siteName,
    this.onOpenSearch,
  });

  @override
  State<RecommendTab> createState() => _RecommendTabState();
}

class _RecommendTabState extends State<RecommendTab> {
  static const _verticalPhysics = AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics());
  static const _iconSize = 17.0, _tagHeight = 32.0, _glyphSize = 10.0, _labelSize = 13.0;
  static const _iconBg = Color(0x1FFA8C16), _iconBorder = Color(0x47FA8C16);
  static const _chipBg = Color(0x0DFFFFFF), _chipBorder = Color(0x1AFFFFFF);

  List<BannerItem> _banners = [];
  List<HomeSection> _sections = [];
  bool _loading = true;
  bool _fetchLock = false;
  String _errorText = '';
  double _headerAlpha = 0;
  int _reloadToken = 0;
  String _collectSourceId = '';
  List<CollectSourceOption> _collectSources = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    FavoriteManager.preload();
    _scrollController.addListener(_onScroll);
    SourceGuard.onReconnect(_onReconnect);
    _reloadCatalog();
    _loadHome(fromPull: false);
  }

  void _reloadCatalog() {
    final list = AppCatalogService.instance.collectSources;
    setState(() {
      _collectSources = list;
      if (_collectSourceId.isNotEmpty &&
          !list.any((e) => e.id == _collectSourceId)) {
        _collectSourceId = '';
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    SourceGuard.offReconnect(_onReconnect);
    super.dispose();
  }

  void _onReconnect() {
    FavoriteManager.preload();
    _reloadCatalog();
    _loadHome(fromPull: false);
  }

  void _selectCollectSource(String id) {
    if (_collectSourceId == id) return;
    setState(() => _collectSourceId = id);
    _loadHome(fromPull: false);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final y = _scrollController.offset;
    final alpha = y <= 0 ? 0.0 : (y / 160.0).clamp(0.0, 1.0);
    // 金标：差值 > 0.01，或到顶/到底必须写入，否则 0.01 阈值会把毛玻璃卡死
    if ((alpha - _headerAlpha).abs() > 0.01 || alpha == 0.0 || alpha == 1.0) {
      if (alpha == _headerAlpha) return;
      setState(() {
        _headerAlpha = alpha;
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(milliseconds: 1400)),
    );
  }

  Future<void> _loadHome({required bool fromPull, bool showHint = false}) async {
    if (_fetchLock) return;
    _fetchLock = true;
    if (!fromPull) {
      setState(() {
        _banners = [];
        _sections = [];
        _loading = true;
        _errorText = '';
      });
    }
    var ok = false;
    try {
      final home = await FilmApi.getHome(sourceId: _collectSourceId);
      if (!mounted) return;
      setState(() {
        _banners = home.banners;
        _sections = home.content;
        _loading = false;
        _errorText = '';
        _reloadToken = DateTime.now().millisecondsSinceEpoch;
      });
      ok = true;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = '$e';
      });
    } finally {
      _fetchLock = false;
    }
    if (showHint && ok) {
      _toast('已更新');
    } else if (showHint && !ok && _errorText.isNotEmpty) {
      _toast(_errorText);
    }
  }

  List<HomeSection> _visibleSections() {
    return _sections.where((s) {
      if (!s.nav.show) return false;
      final films = s.movies.isNotEmpty ? s.movies : s.hot;
      return films.isNotEmpty;
    }).toList();
  }

  String _categoryGlyph(String name) {
    final text = name.trim();
    if (text.isEmpty) return '';
    return String.fromCharCodes(text.runes.take(1));
  }

  double _effectiveHeaderAlpha(bool wide) {
    if (_banners.isEmpty) return 1.0;
    if (wide) return (0.76 + 0.16 * _headerAlpha).clamp(0.0, 0.92);
    return _headerAlpha;
  }

  void _openSearch() {
    if (widget.onOpenSearch != null) {
      widget.onOpenSearch!();
    } else {
      Navigator.pushNamed(context, '/search');
    }
  }

  void _openFilter(int pid) {
    Navigator.pushNamed(context, '/filter', arguments: {'Pid': '$pid'});
  }

  Widget _collectSourceBar(bool wide, double leftInset, double rightInset) {
    if (_collectSources.length <= 1) return const SizedBox.shrink();
    final chips = <({String id, String name})>[
      (id: '', name: '综合'),
      ..._collectSources.map((s) => (id: s.id, name: s.name)),
    ];
    return Padding(
      padding: EdgeInsets.only(
        top: wide ? 10 : 8,
        bottom: wide ? 6 : 4,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(
          left: AppTheme.spaceLg + leftInset,
          right: AppTheme.spaceLg + rightInset,
        ),
        child: Row(
          children: chips.map((c) {
            final active = _collectSourceId == c.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c.name),
                selected: active,
                onSelected: (_) => _selectCollectSource(c.id),
                selectedColor: AppTheme.accent.withValues(alpha: 0.35),
                backgroundColor: AppTheme.bgCard,
                labelStyle: TextStyle(
                  color: active ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _categoryEntry(HomeSection section, bool wide) {
    final glyph = _categoryGlyph(section.nav.name);
    return Padding(
      padding: EdgeInsets.only(right: wide ? 8 : AppTheme.spaceSm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openFilter(section.nav.id),
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          child: Container(
            height: wide ? 35 : _tagHeight,
            padding: EdgeInsets.only(
              left: wide ? 8 : (AppTheme.spaceSm - 2),
              right: wide ? 13 : (AppTheme.spaceMd - 1),
            ),
            decoration: BoxDecoration(
              color: wide ? const Color(0x0FFFFFFF) : _chipBg,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              border: Border.all(
                width: wide ? 0.8 : 0.8,
                color: wide ? const Color(0x1FFFFFFF) : _chipBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (glyph.isNotEmpty) ...[
                  Container(
                    width: wide ? 19 : _iconSize,
                    height: wide ? 19 : _iconSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: wide ? const Color(0x24FA8C16) : _iconBg,
                      borderRadius: BorderRadius.circular(wide ? 9.5 : _iconSize / 2),
                      border: Border.all(
                        width: wide ? 0.7 : 0.6,
                        color: wide ? const Color(0x52FA8C16) : _iconBorder,
                      ),
                    ),
                    child: Text(
                      glyph,
                      style: TextStyle(
                        fontFamily: AppTheme.calligraphyFont,
                        fontSize: wide ? 11 : _glyphSize,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent,
                        height: 1,
                      ),
                    ),
                  ),
                  SizedBox(width: wide ? 6 : (AppTheme.spaceSm - 2)),
                ],
                Text(
                  section.nav.name,
                  style: TextStyle(
                    fontSize: wide ? 13.5 : _labelSize,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stateActions({required String label, required VoidCallback onTap}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pillButton(icon: Icons.link_rounded, label: '更换服务端', accent: true, onTap: () => Navigator.pushNamed(context, '/server_config')),
        const SizedBox(height: 12),
        _pillButton(icon: Icons.refresh_rounded, label: label, accent: false, onTap: onTap),
      ],
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required bool accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: accent ? AppTheme.accent : AppTheme.bgCard,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Container(
          width: 148,
          height: 38,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppTheme.textPrimary),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }

  /// 指示器从顶栏底边往下出现，对齐 OHOS `topInset + 48 + pullDistance - 38`。
  Widget _wrapRefresh({required double topInset, required Widget child}) {
    return RefreshIndicator(
      onRefresh: () => _loadHome(fromPull: true, showHint: true),
      color: AppTheme.accent,
      backgroundColor: AppTheme.bgCard,
      edgeOffset: topInset + 48,
      displacement: 16,
      child: child,
    );
  }

  Widget _scrollableState({
    required double topInset,
    required double leftInset,
    required double rightInset,
    required Widget child,
  }) {
    return _wrapRefresh(
      topInset: topInset,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            physics: _verticalPhysics,
            padding: EdgeInsets.only(left: leftInset, right: rightInset),
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.only(top: 48 + topInset),
                  child: Center(child: child),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(double topInset, double leftInset, double rightInset, bool wide) {
    final alpha = _effectiveHeaderAlpha(wide);
    final searchBg = Color.fromRGBO(
      (22 * alpha).round(),
      (23 * alpha).round(),
      (31 * alpha).round(),
      0.36 + 0.64 * alpha,
    );
    final searchBorder = Color.fromRGBO(255, 255, 255, 0.16 * (1 - alpha) + 0.08 * alpha);
    final bar = Container(
      height: 48 + topInset,
      padding: EdgeInsets.only(
        top: topInset,
        left: AppTheme.spaceLg + leftInset,
        right: AppTheme.spaceLg + rightInset,
      ),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: alpha),
        border: Border(
          bottom: BorderSide(
            width: (wide || _headerAlpha > 0.5) ? 0.5 : 0,
            color: Color.fromRGBO(255, 255, 255, wide ? 0.08 : ((_headerAlpha - 0.5) * 0.16).clamp(0.0, 1.0)),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.subscriptions_rounded, size: 20, color: AppTheme.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.siteName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                shadows: [Shadow(blurRadius: 8, color: Color(0xD9000000), offset: Offset(0, 1))],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: _openSearch,
            child: Container(
              height: 34,
              padding: const EdgeInsets.only(left: 12, right: 14),
              decoration: BoxDecoration(
                color: searchBg,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                border: Border.all(color: searchBorder),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_rounded, size: 14, color: Color(0xBFFFFFFF)),
                  SizedBox(width: 6),
                  Text('搜索', style: TextStyle(fontSize: 12, color: Color(0x8CFFFFFF))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (!wide && _headerAlpha <= 0) return bar;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: bar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topInset = media.padding.top;
    final leftInset = media.padding.left;
    final rightInset = media.padding.right;
    final wide = Breakpoint.isWideWidth(media.size.width);
    final sections = _visibleSections();

    Widget body;
    if (_loading) {
      body = Padding(
        padding: EdgeInsets.only(top: 48 + topInset, left: leftInset, right: rightInset),
        child: const LoadingView(label: '正在加载推荐'),
      );
    } else if (_errorText.isNotEmpty) {
      body = Padding(
        padding: EdgeInsets.only(top: 48 + topInset, left: leftInset, right: rightInset),
        child: Center(
          child: SingleChildScrollView(
            child: EmptyState(
              title: '加载失败',
              subtitle: _errorText,
              icon: Icons.error_outline_rounded,
              action: _stateActions(label: '刷新', onTap: () => _loadHome(fromPull: false, showHint: true)),
            ),
          ),
        ),
      );
    } else if (_banners.isEmpty && sections.isEmpty) {
      body = _scrollableState(
        topInset: topInset,
        leftInset: leftInset,
        rightInset: rightInset,
        child: EmptyState(
          title: '暂无影片数据',
          subtitle: '当前源暂无影片或尚未采集，可下拉刷新或切换上方采集源',
          icon: Icons.movie_outlined,
          action: _stateActions(label: '刷新', onTap: () => _loadHome(fromPull: true, showHint: true)),
        ),
      );
    } else {
      final topSpace = wide
          ? (48 + topInset + 8)
          : (_banners.isEmpty ? (48 + topInset + 12) : 0.0);
      body = _wrapRefresh(
        topInset: topInset,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: _verticalPhysics,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (topSpace > 0) SizedBox(height: topSpace),
              HomeBanner(key: ValueKey(_reloadToken), banners: _banners),
              _collectSourceBar(wide, leftInset, rightInset),
              if (sections.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: wide ? 14 : AppTheme.spaceLg),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.only(
                      left: AppTheme.spaceLg + leftInset,
                      right: AppTheme.spaceLg + rightInset,
                    ),
                    child: Row(
                      children: sections.map((s) => _categoryEntry(s, wide)).toList(),
                    ),
                  ),
                ),
              ...sections.map((section) {
                final movies = section.movies.isNotEmpty ? section.movies : section.hot;
                return FilmRow(
                  title: section.nav.name,
                  films: movies,
                  pid: section.nav.id,
                  leftInset: leftInset,
                  rightInset: rightInset,
                  onMore: () => _openFilter(section.nav.id),
                );
              }),
              const SizedBox(height: AppTheme.spaceSm),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        body,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _header(topInset, leftInset, rightInset, wide),
        ),
      ],
    );
  }
}
