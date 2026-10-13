import 'package:flutter/material.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../api/film_api.dart';
import '../components/film_card.dart';
import '../components/loading_view.dart';
import '../components/empty_state.dart';
import '../components/scroll_fab.dart';
import '../utils/breakpoint.dart';

const int _pageSize = 21;

/// 每日更新单分类面板，对齐 OHOS `DailyUpdatePane.ets`
class DailyUpdatePane extends StatefulWidget {
  final int pid;
  final bool active;
  final int seedPid;
  final List<MovieBasicInfo>? seedList;
  final PageInfo? seedPage;
  final int reloadToken;
  final double headerHeight;
  final String collectSourceId;
  final VoidCallback? onAllRefreshed;

  const DailyUpdatePane({
    super.key,
    required this.pid,
    this.active = true,
    this.seedPid = 0,
    this.seedList,
    this.seedPage,
    this.reloadToken = 0,
    this.headerHeight = 0,
    this.collectSourceId = '',
    this.onAllRefreshed,
  });

  @override
  State<DailyUpdatePane> createState() => _DailyUpdatePaneState();
}

class _DailyUpdatePaneState extends State<DailyUpdatePane> with AutomaticKeepAliveClientMixin {
  List<MovieBasicInfo> _films = [];
  PageInfo _page = PageInfo(pageSize: _pageSize, current: 1, pageCount: 1, total: 0);
  bool _loading = true;
  bool _loadingMore = false;
  bool _fetchLock = false;
  String _errorText = '';
  bool _hasLoaded = false;
  bool _showTopFab = false;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _boot();
  }

  @override
  void didUpdateWidget(covariant DailyUpdatePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reloadToken != oldWidget.reloadToken ||
        widget.collectSourceId != oldWidget.collectSourceId) {
      _hasLoaded = false;
      _boot();
    } else if (widget.active && !_hasLoaded) {
      _loadData(true, fromPull: false);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _boot() {
    if (_consumeSeed()) {
      return;
    }
    _films = [];
    _page = PageInfo(pageSize: _pageSize, current: 1, pageCount: 1, total: 0);
    _errorText = '';
    if (widget.active) {
      _loadData(true, fromPull: false);
    } else {
      _loading = true;
    }
  }

  bool _consumeSeed() {
    if (widget.pid != widget.seedPid || widget.seedList == null) {
      return false;
    }
    _films = List<MovieBasicInfo>.from(widget.seedList!);
    _page = widget.seedPage ??
        PageInfo(
          pageSize: _pageSize,
          current: 1,
          pageCount: 1,
          total: widget.seedList!.length,
        );
    _hasLoaded = true;
    _loading = false;
    _errorText = '';
    return true;
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      if (!_loadingMore && _hasMore()) {
        _loadData(false, fromPull: false);
      }
    }
    final show = pos.viewportDimension > 0 && pos.pixels > pos.viewportDimension;
    if (show != _showTopFab) {
      setState(() {
        _showTopFab = show;
      });
    }
  }

  bool _hasMore() {
    return _page.current < _page.pageCount;
  }

  void _scrollToTop() {
    setState(() => _showTopFab = false);
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Future<void> _loadData(bool reset, {required bool fromPull}) async {
    if (_fetchLock) return;
    final nextPage = reset ? 1 : _page.current + 1;
    if (!reset && (_loadingMore || nextPage > _page.pageCount)) return;

    _fetchLock = true;
    if (reset) {
      if (!fromPull) {
        setState(() {
          _films = [];
          _loading = true;
          _errorText = '';
        });
      }
    } else {
      setState(() {
        _loadingMore = true;
      });
    }

    var ok = false;
    try {
      final res = await FilmApi.getDailyUpdates(
        widget.pid,
        nextPage,
        pageSize: _pageSize,
        sourceId: widget.collectSourceId,
      );
      if (!mounted) return;
      setState(() {
        _films = reset ? res.list : [..._films, ...res.list];
        _page = res.page;
        _loading = false;
        _loadingMore = false;
        _hasLoaded = true;
        _errorText = '';
      });
      ok = true;
      if (fromPull && widget.pid == widget.seedPid) {
        widget.onAllRefreshed?.call();
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) {
          _errorText = msg.isNotEmpty ? msg : '每日更新加载失败';
        } else {
          _toast(msg);
        }
      });
    } finally {
      _fetchLock = false;
    }

    if (fromPull) {
      if (ok) {
        _toast('已更新');
      } else {
        _toast(_errorText.isNotEmpty ? _errorText : '刷新失败');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final media = MediaQuery.of(context);
    final leftInset = media.padding.left;
    final rightInset = media.padding.right;
    final width = media.size.width;

    if (_loading && _films.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(
          top: widget.headerHeight,
          left: leftInset,
          right: rightInset,
        ),
        child: const LoadingView(label: '正在加载今日更新'),
      );
    }

    if (_films.isEmpty) {
      final emptyBody = ListView(
        physics: _errorText.isNotEmpty
            ? const ClampingScrollPhysics()
            : const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.only(left: leftInset, right: rightInset),
        children: [
          SizedBox(height: widget.headerHeight + 24),
          if (_errorText.isNotEmpty)
            EmptyState(
              title: '加载失败',
              subtitle: _errorText,
              icon: Icons.error_outline_rounded,
              action: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _paneActionPill(
                    icon: Icons.link_rounded,
                    label: '更换服务端',
                    accent: true,
                    onTap: () => Navigator.pushNamed(context, '/server_config'),
                  ),
                  const SizedBox(height: 12),
                  _paneActionPill(
                    icon: Icons.refresh_rounded,
                    label: '刷新',
                    accent: false,
                    onTap: () => _loadData(true, fromPull: false),
                  ),
                ],
              ),
            )
          else
            const EmptyState(
              title: '暂无更新',
              subtitle: '近 24 小时还没有新片入库',
              icon: Icons.local_fire_department_rounded,
            ),
        ],
      );
      if (_errorText.isNotEmpty) {
        return emptyBody;
      }
      return RefreshIndicator(
        onRefresh: () => _loadData(true, fromPull: true),
        color: AppTheme.accent,
        backgroundColor: AppTheme.bgCard,
        edgeOffset: widget.headerHeight,
        displacement: 16,
        child: emptyBody,
      );
    }

    final cols = Breakpoint.gridColsOf(width);
    final cardAspectRatio = Breakpoint.gridAspectRatio(
      width: width,
      columns: cols,
      horizontalPadding: (AppTheme.spaceLg * 2) + leftInset + rightInset,
    );

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        RefreshIndicator(
          onRefresh: () => _loadData(true, fromPull: true),
          color: AppTheme.accent,
          backgroundColor: AppTheme.bgCard,
          edgeOffset: widget.headerHeight,
          displacement: 16,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: widget.headerHeight + 8),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                  left: AppTheme.spaceLg + leftInset,
                  right: AppTheme.spaceLg + rightInset,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    childAspectRatio: cardAspectRatio,
                    crossAxisSpacing: AppTheme.spaceSm,
                    mainAxisSpacing: AppTheme.spaceMd,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => FilmCard(film: _films[index]),
                    childCount: _films.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 72,
                  child: Center(
                    child: Text(
                      _loadingMore
                          ? '加载中...'
                          : (_hasMore() ? '' : '没有更多了'),
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(right: rightInset),
          child: ScrollFab(
            visible: _showTopFab,
            onClickFab: _scrollToTop,
          ),
        ),
      ],
    );
  }

  Widget _paneActionPill({
    required IconData icon,
    required String label,
    required bool accent,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        width: 148,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent ? AppTheme.accent : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppTheme.textPrimary),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }
}

