import 'dart:math';
import 'package:flutter/material.dart';
import '../../common/app_theme.dart';
import '../../models/film_models.dart';
import '../../utils/breakpoint.dart';
import 'film_detail_header.dart';
import 'play_group_bar.dart';

const int _groupSize = 100;
const int _epNameWideLen = 6;
const double _epRowHeight = 54.0;
const double _epMinHeight = 44.0;

/// 播放页选集与详情面板，全量对齐鸿蒙端 `PlayDetailPanel.ets`
class PlayDetailPanel extends StatefulWidget {
  final String filmId;
  final String picture;
  final String name;
  final String subTitle;
  final String actor;
  final String plot;
  final String sourceName;
  final String sourceId;
  final MovieDescriptor? descriptor;
  final List<PlaySource> sources;
  final String playingSourceId;
  final String viewingSourceId;
  final int episodeIndex;
  final ValueChanged<String>? onViewSource;
  final void Function(String sourceId, int index)? onSelectEpisode;
  final bool isSplit;
  final int? episodeColumns;
  final double rightInset;

  const PlayDetailPanel({
    super.key,
    required this.filmId,
    this.picture = '',
    required this.name,
    this.subTitle = '',
    this.actor = '',
    this.plot = '',
    this.sourceName = '',
    this.sourceId = '',
    this.descriptor,
    required this.sources,
    required this.playingSourceId,
    required this.viewingSourceId,
    required this.episodeIndex,
    this.onViewSource,
    this.onSelectEpisode,
    this.isSplit = false,
    this.episodeColumns,
    this.rightInset = 0,
  });

  @override
  State<PlayDetailPanel> createState() => _PlayDetailPanelState();
}

class _PlayDetailPanelState extends State<PlayDetailPanel> {
  final Map<String, int> _groupIndexes = {};
  final ScrollController _listScroller = ScrollController();
  final ScrollController _groupScroller = ScrollController();
  final ScrollController _sourceScroller = ScrollController();
  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _sourceRowKey = GlobalKey();
  final GlobalKey _groupRowKey = GlobalKey();
  final Map<String, GlobalKey> _sourceKeys = {};
  final Map<int, GlobalKey> _groupKeys = {};
  double _headerHeight = 64.0;

  @override
  void initState() {
    super.initState();
    _syncGroupFromPlayingEpisode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureHeader();
      _syncSourceBar(false);
      _syncGroupBar(false);
      _checkReadyAndScroll(false);
    });
  }

  @override
  void didUpdateWidget(covariant PlayDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sources != widget.sources) {
      _syncGroupFromPlayingEpisode();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measureHeader();
        _checkReadyAndScroll(false);
        _syncSourceBar(false);
        _syncGroupBar(false);
      });
    } else if (oldWidget.viewingSourceId != widget.viewingSourceId) {
      _clampGroup(widget.viewingSourceId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncSourceBar(true);
        _syncGroupBar(true);
      });
    } else if (oldWidget.episodeIndex != widget.episodeIndex ||
        oldWidget.playingSourceId != widget.playingSourceId) {
      if (widget.viewingSourceId == widget.playingSourceId) {
        _setGroup(widget.viewingSourceId, widget.episodeIndex ~/ _groupSize, false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _measureHeader();
          _scrollToFocusedEpisode(true);
        });
      }
    }
  }

  @override
  void dispose() {
    _listScroller.dispose();
    _groupScroller.dispose();
    _sourceScroller.dispose();
    super.dispose();
  }

  void _measureHeader() {
    final ctx = _headerKey.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final h = box.size.height;
        if (h > 0 && (_headerHeight - h).abs() > 0.5) {
          _headerHeight = h;
        }
      }
    }
  }

  Map<String, GlobalKey> get _currentSourceKeys {
    for (final s in widget.sources) {
      _sourceKeys.putIfAbsent(s.id, () => GlobalKey());
    }
    return _sourceKeys;
  }

  Map<int, GlobalKey> get _currentGroupKeys {
    final count = _groupCount();
    for (int i = 0; i < count; i++) {
      _groupKeys.putIfAbsent(i, () => GlobalKey());
    }
    return _groupKeys;
  }

  PlaySource? _findSource(String id) {
    for (final s in widget.sources) {
      if (s.id == id) return s;
    }
    return widget.sources.isNotEmpty ? widget.sources.first : null;
  }

  List<MovieUrlInfo> _episodeList() {
    final source = _findSource(widget.viewingSourceId);
    return source?.linkList ?? [];
  }

  int _groupOf(String sourceId) {
    return _groupIndexes[sourceId] ?? 0;
  }

  void _setGroup(String sourceId, int groupIndex, [bool scrollReset = true]) {
    if (sourceId.isEmpty) return;
    final count = _groupCount();
    final safe = count <= 0 ? 0 : groupIndex.clamp(0, count - 1);
    final oldGroup = _groupOf(sourceId);
    if (oldGroup == safe && _groupIndexes.containsKey(sourceId)) {
      if (scrollReset) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocusedEpisode(true));
      }
      return;
    }
    setState(() {
      _groupIndexes[sourceId] = safe;
    });
    if (scrollReset) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocusedEpisode(true));
    }
  }

  void _clampGroup(String sourceId) {
    _setGroup(sourceId, _groupOf(sourceId), false);
  }

  void _syncGroupFromPlayingEpisode() {
    if (widget.viewingSourceId.isEmpty && widget.playingSourceId.isNotEmpty) {
      // Handled by parent view
    }
    if (widget.viewingSourceId == widget.playingSourceId) {
      final targetGroup = widget.episodeIndex ~/ _groupSize;
      _setGroup(widget.viewingSourceId, targetGroup, false);
    } else {
      _clampGroup(widget.viewingSourceId);
    }
  }

  int _groupCount() {
    final total = _episodeList().length;
    if (total <= 0) return 0;
    return (total / _groupSize).ceil();
  }

  bool _needsGrouping() {
    return _episodeList().length > _groupSize;
  }

  int _groupStart() {
    return _groupOf(widget.viewingSourceId) * _groupSize;
  }

  List<MovieUrlInfo> _visibleEpisodes() {
    final list = _episodeList();
    if (!_needsGrouping()) return list;
    final start = _groupStart();
    final end = (start + _groupSize).clamp(0, list.length);
    return list.sublist(start, end);
  }

  String _groupLabel(int index) {
    final total = _episodeList().length;
    final start = index * _groupSize + 1;
    final end = ((index + 1) * _groupSize).clamp(0, total);
    return '$start-$end';
  }

  bool _usesWideTiles() {
    final list = _visibleEpisodes();
    for (final e in list) {
      if (e.episode.length > _epNameWideLen) return true;
    }
    return false;
  }

  int _epCols(double screenWidth) {
    if (widget.episodeColumns != null) {
      return widget.episodeColumns!;
    }
    final effectiveWidth = widget.isSplit ? screenWidth * (5 / 12) : screenWidth;
    final bp = Breakpoint.ofWidth(effectiveWidth);
    final isWide = _usesWideTiles();
    if (bp == 'lg' || bp == 'xl') {
      return isWide ? 3 : 5;
    }
    if (bp == 'md') {
      return isWide ? 3 : 4;
    }
    return isWide ? 2 : 3;
  }

  double _calculateSourceTargetOffset(int targetIndex) {
    if (targetIndex <= 0) return 0.0;
    if (targetIndex < widget.sources.length) {
      final targetSource = widget.sources[targetIndex];
      final itemCtx = _sourceKeys[targetSource.id]?.currentContext;
      final rowCtx = _sourceRowKey.currentContext;
      if (itemCtx != null && rowCtx != null) {
        final itemBox = itemCtx.findRenderObject() as RenderBox?;
        final rowBox = rowCtx.findRenderObject() as RenderBox?;
        if (itemBox != null && itemBox.hasSize && rowBox != null && rowBox.hasSize) {
          return itemBox.localToGlobal(Offset.zero, ancestor: rowBox).dx;
        }
      }
    }

    // Fallback: 理论估算
    double offset = 0.0;
    final textScaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    for (int i = 0; i < targetIndex && i < widget.sources.length; i++) {
      final s = widget.sources[i];
      final isCurrentViewing = s.id == widget.viewingSourceId;
      final tp = TextPainter(
        text: TextSpan(
          text: s.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isCurrentViewing ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final extra = isCurrentViewing ? 40.0 : 24.0;
      offset += tp.width + extra + 8.0;
    }
    return offset;
  }

  double _calculateGroupTargetOffset(int targetGroup) {
    if (targetGroup <= 0) return 0.0;
    final count = _groupCount();
    if (targetGroup < count) {
      final itemCtx = _groupKeys[targetGroup]?.currentContext;
      final rowCtx = _groupRowKey.currentContext;
      if (itemCtx != null && rowCtx != null) {
        final itemBox = itemCtx.findRenderObject() as RenderBox?;
        final rowBox = rowCtx.findRenderObject() as RenderBox?;
        if (itemBox != null && itemBox.hasSize && rowBox != null && rowBox.hasSize) {
          return itemBox.localToGlobal(Offset.zero, ancestor: rowBox).dx;
        }
      }
    }

    // Fallback: 理论估算
    double offset = 0.0;
    final textScaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    for (int i = 0; i < targetGroup && i < count; i++) {
      final label = _groupLabel(i);
      final isCurrentGroup = _groupOf(widget.viewingSourceId) == i;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isCurrentGroup ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      offset += tp.width + 28.0 + 8.0;
    }
    return offset;
  }

  void _syncSourceBar(bool smooth) {
    if (widget.sources.isEmpty || !_sourceScroller.hasClients) return;
    final index = widget.sources.indexWhere((s) => s.id == widget.viewingSourceId);
    if (index < 0) return;

    final targetSource = widget.sources[index];
    final itemCtx = _sourceKeys[targetSource.id]?.currentContext;
    if (itemCtx != null) {
      final renderObject = itemCtx.findRenderObject();
      final scrollable = Scrollable.maybeOf(itemCtx);
      if (scrollable != null && renderObject != null) {
        scrollable.position.ensureVisible(
          renderObject,
          alignment: 0.5,
          duration: smooth ? const Duration(milliseconds: 250) : Duration.zero,
          curve: Curves.easeOutCubic,
        );
        return;
      }
    }

    final targetOffset = _calculateSourceTargetOffset(index);
    final maxExtent = _sourceScroller.position.maxScrollExtent;

    if (targetOffset > 0 && maxExtent <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncSourceBar(smooth);
      });
      return;
    }

    final clampedOffset = targetOffset.clamp(0.0, maxExtent);
    if ((_sourceScroller.offset - clampedOffset).abs() < 1.0) return;

    try {
      if (smooth) {
        _sourceScroller.animateTo(clampedOffset,
            duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
      } else {
        _sourceScroller.jumpTo(clampedOffset);
      }
    } catch (_) {}
  }

  void _syncGroupBar(bool smooth) {
    if (!_needsGrouping() || !_groupScroller.hasClients) return;
    final g = _groupOf(widget.viewingSourceId);

    final itemCtx = _groupKeys[g]?.currentContext;
    if (itemCtx != null) {
      final renderObject = itemCtx.findRenderObject();
      final scrollable = Scrollable.maybeOf(itemCtx);
      if (scrollable != null && renderObject != null) {
        scrollable.position.ensureVisible(
          renderObject,
          alignment: 0.5,
          duration: smooth ? const Duration(milliseconds: 250) : Duration.zero,
          curve: Curves.easeOutCubic,
        );
        return;
      }
    }

    final targetOffset = _calculateGroupTargetOffset(g);
    final maxExtent = _groupScroller.position.maxScrollExtent;

    if (targetOffset > 0 && maxExtent <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncGroupBar(smooth);
      });
      return;
    }

    final clampedOffset = targetOffset.clamp(0.0, maxExtent);
    if ((_groupScroller.offset - clampedOffset).abs() < 1.0) return;

    try {
      if (smooth) {
        _groupScroller.animateTo(clampedOffset,
            duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
      } else {
        _groupScroller.jumpTo(clampedOffset);
      }
    } catch (_) {}
  }

  void _checkReadyAndScroll(bool smooth) {
    _scrollToFocusedEpisode(smooth);
  }

  void _scrollToFocusedEpisode(bool smooth) {
    if (!_listScroller.hasClients) return;
    final list = _episodeList();
    if (list.isEmpty) return;

    final g = _groupOf(widget.viewingSourceId);
    final start = g * _groupSize;
    final end = start + _groupSize;
    final inGroup = widget.viewingSourceId == widget.playingSourceId &&
        widget.episodeIndex >= start &&
        widget.episodeIndex < end &&
        widget.episodeIndex < list.length;

    // 1. 同步横向滚动分组栏与播放源栏，使选中的胶囊进入视野首位
    _syncGroupBar(smooth);
    _syncSourceBar(smooth);

    final screenWidth = MediaQuery.sizeOf(context).width;
    final cols = _epCols(screenWidth);

    // 2. 纵向列表定位：基于 headerHeight 与行高精确推移，绝不被吸顶栏遮挡
    try {
      if (inGroup) {
        final localIndex = widget.episodeIndex - start;
        final targetRow = localIndex ~/ cols;
        final visibleCount = _visibleEpisodes().length;
        final maxRow = max(0, ((visibleCount / cols).ceil() - 1));
        final safeRow = min(targetRow, maxRow);

        // 竖屏且首行（或无分组前1-2行）：纵向空间充足，保持自然置顶（标题+吸顶栏+首行完整可见）
        // 横屏分栏（widget.isSplit）下纵向可视高度紧凑(~300dp)，如果滚到 0.0 会被未吸顶标题占据空间导致底部剧集被截断只露出一半，
        // 因此横屏分栏下吸顶对齐到 _headerHeight，保证吸顶栏吸顶且首行选集直接完整展示在下方！
        if (!widget.isSplit && ((g == 0 && safeRow == 0) || (safeRow <= 1 && !_needsGrouping()))) {
          if (smooth) {
            _listScroller.animateTo(0.0,
                duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
          } else {
            _listScroller.jumpTo(0.0);
          }
          return;
        }

        final targetOffset = (_headerHeight + safeRow * _epRowHeight)
            .clamp(0.0, _listScroller.position.maxScrollExtent);
        if (smooth) {
          _listScroller.animateTo(targetOffset,
              duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
        } else {
          _listScroller.jumpTo(targetOffset);
        }
      } else {
        // 目标分组不含当前剧集时，吸顶对齐到 ListItemGroup 顶部（header groupBar 吸顶，首行展示该组第1行）
        final targetOffset = _headerHeight.clamp(0.0, _listScroller.position.maxScrollExtent);
        if (smooth) {
          _listScroller.animateTo(targetOffset,
              duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
        } else {
          _listScroller.jumpTo(targetOffset);
        }
      }
    } catch (_) {}
  }

  void _showEpisodeTitle(String name) {
    final text = name.trim();
    if (text.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        title: const Text('剧集名称', style: TextStyle(fontSize: 16, color: AppTheme.textPrimary)),
        content: Text(text, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  bool _isEpisodeOn(int index) {
    return widget.viewingSourceId == widget.playingSourceId && widget.episodeIndex == index;
  }

  Widget _buildEpisodeTile(MovieUrlInfo ep, int index, bool isWide) {
    final active = _isEpisodeOn(index);
    return InkWell(
      onTap: () {
        if (active || widget.onSelectEpisode == null) {
          _showEpisodeTitle(ep.episode);
          return;
        }
        widget.onSelectEpisode!(widget.viewingSourceId, index);
      },
      onLongPress: () => _showEpisodeTitle(ep.episode),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        constraints: const BoxConstraints(minHeight: _epMinHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceSm, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppTheme.accentSoft : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: active ? Border.all(color: AppTheme.accent, width: 2) : null,
        ),
        child: Text(
          ep.episode,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            color: active ? AppTheme.textPrimary : AppTheme.textSecondary,
          ),
          maxLines: isWide ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final visibleEps = _visibleEpisodes();
    final isWide = _usesWideTiles();
    final cols = _epCols(screenWidth);
    final groupStart = _groupStart();
    final rowCount = (visibleEps.length / cols).ceil();

    final groupBarHeight = PlayGroupBar.calculateHeight(
      hasSources: widget.sources.length > 1,
      needsGrouping: _needsGrouping(),
    );

    return CustomScrollView(
      controller: _listScroller,
      slivers: [
        // Film Detail Header
        SliverToBoxAdapter(
          child: Container(
            key: _headerKey,
            child: FilmDetailHeader(
              filmId: widget.filmId,
              picture: widget.picture,
              name: widget.name,
              subTitle: widget.subTitle,
              actor: widget.actor,
              sourceName: widget.sourceName,
              sourceId: widget.sourceId,
              plot: widget.plot,
              descriptor: widget.descriptor,
              rightInset: widget.rightInset,
            ),
          ),
        ),

        // 吸顶播放源与分组控制栏
        if (groupBarHeight > 0)
          SliverPersistentHeader(
            pinned: true,
            delegate: StickyGroupBarDelegate(
              height: groupBarHeight,
              child: PlayGroupBar(
              sources: widget.sources,
              viewingSourceId: widget.viewingSourceId,
              onViewSource: widget.onViewSource,
              needsGrouping: _needsGrouping(),
              groupCount: _groupCount(),
              currentGroup: _groupOf(widget.viewingSourceId),
              onSelectGroup: (index) {
                _setGroup(widget.viewingSourceId, index, true);
                _syncGroupBar(true);
              },
              groupLabel: _groupLabel,
              sourceScroller: _sourceScroller,
              groupScroller: _groupScroller,
              rightInset: widget.rightInset,
              sourceKeys: _currentSourceKeys,
              groupKeys: _currentGroupKeys,
              sourceRowKey: _sourceRowKey,
              groupRowKey: _groupRowKey,
            ),
          ),
        ),

        // 选集列表（对齐 OHOS epRow: 固定 54dp 行高，44dp 净高）
        if (visibleEps.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 32, 12 + widget.rightInset, 32),
              child: const Center(
                child: Text('暂无数据', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, row) {
                return Container(
                  height: _epRowHeight,
                  padding: EdgeInsets.fromLTRB(12, 4, 12 + widget.rightInset, 6),
                  child: Row(
                    children: [
                      for (int col = 0; col < cols; col++) ...[
                        if (col > 0) const SizedBox(width: AppTheme.spaceSm),
                        Expanded(
                          child: (row * cols + col < visibleEps.length)
                              ? _buildEpisodeTile(
                                  visibleEps[row * cols + col],
                                  groupStart + (row * cols + col),
                                  isWide,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                );
              },
              childCount: rowCount,
            ),
          ),

        // 底部留白，保证滑到底部时最后一排剧集不贴边
        SliverToBoxAdapter(
          child: SizedBox(
            height: max(24.0, MediaQuery.paddingOf(context).bottom + 16.0),
          ),
        ),
      ],
    );
  }
}
