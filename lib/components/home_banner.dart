import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../utils/breakpoint.dart';
import '../utils/collect_source_scope.dart';
import '../utils/format_util.dart';
import '../utils/nav_util.dart';
import '../utils/server_config_manager.dart';

/// 首页 Banner，对齐 OHOS `HomeBanner.ets`
class HomeBanner extends StatefulWidget {
  final List<BannerItem> banners;

  const HomeBanner({super.key, required this.banners});

  @override
  State<HomeBanner> createState() => _HomeBannerState();
}

class _HomeBannerState extends State<HomeBanner> {
  static const int _kInitialPageBase = 10000;

  PageController? _controller;
  int _index = 0;
  int _virtualPage = 0;
  Timer? _timer;
  double _viewportFraction = 1;
  bool _isUserScrolling = false;

  bool get _multi => widget.banners.length > 1;

  void _setupController({int? targetPage}) {
    final width = MediaQuery.sizeOf(context).width;
    final peek = _multi ? Breakpoint.bannerPeek(width) : 0.0;
    final fraction = _multi ? ((width - peek * 2) / width).clamp(0.72, 1.0) : 1.0;
    _viewportFraction = fraction;

    final initialPage = targetPage ??
        (_multi ? (_kInitialPageBase ~/ widget.banners.length) * widget.banners.length : 0);
    _virtualPage = initialPage;
    _index = widget.banners.isEmpty ? 0 : (initialPage % widget.banners.length);
    _controller?.dispose();
    _controller = PageController(viewportFraction: fraction, initialPage: initialPage);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      _setupController();
      _startTimer();
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    final peek = _multi ? Breakpoint.bannerPeek(width) : 0.0;
    final fraction = _multi ? ((width - peek * 2) / width).clamp(0.72, 1.0) : 1.0;
    if ((fraction - _viewportFraction).abs() < 0.02) return;
    final page = _controller!.hasClients ? (_controller!.page?.round() ?? _virtualPage) : _virtualPage;
    _setupController(targetPage: page);
  }

  @override
  void didUpdateWidget(HomeBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.banners != oldWidget.banners) {
      if (oldWidget.banners.length != widget.banners.length || widget.banners.length <= 1) {
        _timer?.cancel();
        _setupController();
        _startTimer();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_multi) return;
    _timer = Timer.periodic(const Duration(milliseconds: 4800), (_) {
      if (!mounted || _controller == null || !_controller!.hasClients) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      if (!TickerMode.valuesOf(context).enabled) return;
      final current = _controller!.page?.round() ?? _virtualPage;
      _controller!.animateToPage(
        current + 1,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  void _onPageChanged(int page) {
    _virtualPage = page;
    if (widget.banners.isEmpty) return;
    final realIndex = page % widget.banners.length;
    if (_index != realIndex) {
      setState(() => _index = realIndex);
    }
    if (_multi && page < widget.banners.length * 2) {
      final jumpPage = (_kInitialPageBase ~/ widget.banners.length) * widget.banners.length + realIndex;
      _virtualPage = jumpPage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller != null && _controller!.hasClients) {
          _controller!.jumpToPage(jumpPage);
        }
      });
    }
  }

  void _openPlay(BannerItem item) {
    final id = item.mid > 0 ? '${item.mid}' : item.id;
    if (id.isEmpty) return;
    var sourceId = item.sourceId.trim();
    if (sourceId.isEmpty) {
      sourceId = CollectSourceScope.instance.activeId;
    }
    NavUtil.openPlay(context, id, sourceId: sourceId);
  }

  Widget _backdrop(BannerItem item, {required bool round}) {
    final url = ServerConfigManager.instance.resolveMediaUrl(FormatUtil.bannerBackdrop(item));
    final radius = round ? AppTheme.radiusLg : 0.0;
    if (url.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: FormatUtil.imageHeaders(url),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorWidget: (context, url, error) => const ColoredBox(color: AppTheme.bgCard),
      ),
    );
  }

  Widget _mobileItem(BannerItem item) {
    return GestureDetector(
      onTap: () => _openPlay(item),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_multi ? AppTheme.radiusLg : 0),
          border: _multi ? Border.all(color: const Color(0x1FFFFFFF), width: 0.6) : null,
          boxShadow: _multi
              ? const [BoxShadow(blurRadius: 12, color: Color(0x80000000), offset: Offset(0, 3))]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_multi ? AppTheme.radiusLg : 0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _backdrop(item, round: _multi),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x000A0B10),
                      Color(0x000A0B10),
                      Color(0x660A0B10),
                      Color(0xB30A0B10),
                      Color(0xD90A0B10),
                    ],
                    stops: [0.0, 0.50, 0.72, 0.90, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppTheme.spaceMd, 0, AppTheme.spaceMd, AppTheme.spaceLg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      item.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        shadows: [Shadow(blurRadius: 10, color: Color(0xE6000000), offset: Offset(0, 2))],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (item.remark.isNotEmpty) ...[
                          Text(
                            item.remark,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            FormatUtil.joinMeta([item.year, item.cName, item.area]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Color(0xBFFFFFFF)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _playButton(compact: true, item: item),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wideItem(BannerItem item, double windowHeight) {
    final compact = windowHeight < 500;
    return GestureDetector(
      onTap: () => _openPlay(item),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_multi ? AppTheme.radiusLg : 0),
          border: Border.all(color: const Color(0x14FFFFFF)),
          boxShadow: _multi
              ? const [BoxShadow(blurRadius: 14, color: Color(0x80000000), offset: Offset(0, 4))]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_multi ? AppTheme.radiusLg : 0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _backdrop(item, round: _multi),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFF0A0B10),
                      Color(0xF00A0B10),
                      Color(0x990A0B10),
                      Color(0x260A0B10),
                    ],
                    stops: [0.0, 0.38, 0.68, 1.0],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x000A0B10), Color(0xBF0A0B10)],
                    stops: [0.65, 1.0],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.55,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(compact ? 28 : 36, compact ? 14 : 24, 16, compact ? 14 : 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 24,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _chip(
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.star_rounded, size: 11, color: AppTheme.accent),
                                        SizedBox(width: 4),
                                        Text('精选推荐', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.accent)),
                                      ],
                                    ),
                                    bg: const Color(0x1FFA8C16),
                                    border: const Color(0x59FA8C16),
                                  ),
                                  if (item.cName.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    _chip(
                                      child: Text(item.cName, style: const TextStyle(fontSize: 11, color: Color(0xD9FFFFFF))),
                                      bg: const Color(0x14FFFFFF),
                                    ),
                                  ],
                                  if (item.remark.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    _chip(
                                      child: Text(
                                        item.remark,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFFA940)),
                                      ),
                                      bg: const Color(0x1FFFA940),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 8 : 12),
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 20 : 28,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                              shadows: const [Shadow(blurRadius: 8, color: Color(0xD9000000), offset: Offset(0, 2))],
                            ),
                          ),
                          SizedBox(height: compact ? 4 : 6),
                          Text(
                            FormatUtil.joinMeta([item.year, item.cName, item.area]),
                            style: TextStyle(fontSize: compact ? 11 : 12, color: AppTheme.textSecondary),
                          ),
                          if (item.blurb.trim().isNotEmpty) ...[
                            SizedBox(height: compact ? 6 : 10),
                            Text(
                              item.blurb.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: compact ? 11 : 12, height: 1.45, color: AppTheme.textMuted),
                            ),
                          ],
                          SizedBox(height: compact ? 12 : 18),
                          _playButton(compact: compact, item: item),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip({required Widget child, required Color bg, Color? border}) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: border == null ? null : Border.all(color: border, width: 0.5),
      ),
      child: child,
    );
  }

  Widget _playButton({required bool compact, required BannerItem item}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        gradient: const LinearGradient(colors: [Color(0xFFFA8C16), Color(0xFFFFA940)]),
        boxShadow: const [BoxShadow(blurRadius: 12, color: Color(0x61FA8C16), offset: Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openPlay(item),
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 22 : 24, vertical: compact ? 8 : 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, size: compact ? 13 : 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  '立即播放',
                  style: TextStyle(fontSize: compact ? 12 : 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) {
      return const SizedBox.shrink();
    }
    final size = MediaQuery.sizeOf(context);
    final wide = Breakpoint.isWideWidth(size.width);
    final height = Breakpoint.bannerHeight(width: size.width, height: size.height, multi: _multi);
    final space = _multi ? Breakpoint.bannerItemSpace(size.width) : 0.0;
    final controller = _controller;
    if (controller == null) {
      return SizedBox(height: height);
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: _multi
            ? (wide && size.height < 500 ? 14 : AppTheme.spaceXl)
            : AppTheme.spaceLg,
      ),
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: Listener(
              onPointerDown: (_) {
                _timer?.cancel();
              },
              onPointerUp: (_) {
                if (!_isUserScrolling) {
                  _startTimer();
                }
              },
              onPointerCancel: (_) {
                if (!_isUserScrolling) {
                  _startTimer();
                }
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.axis != Axis.horizontal || notification.depth != 0) {
                    return false;
                  }
                  if (notification is ScrollStartNotification) {
                    if (notification.dragDetails != null) {
                      _isUserScrolling = true;
                      _timer?.cancel();
                    }
                  } else if (notification is ScrollEndNotification) {
                    if (_isUserScrolling) {
                      _isUserScrolling = false;
                      _startTimer();
                    }
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: controller,
                  itemCount: _multi ? null : 1,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, i) {
                    final item = widget.banners[i % widget.banners.length];
                    final child = wide ? _wideItem(item, size.height) : _mobileItem(item);
                    if (space <= 0) return child;
                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: space / 2),
                      child: child,
                    );
                  },
                ),
              ),
            ),
          ),
          if (_multi) ...[
            SizedBox(height: size.height < 500 ? 8 : 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.banners.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: active ? 18 : 5,
                  height: 3.5,
                  decoration: BoxDecoration(
                    color: active ? AppTheme.accent : const Color(0x40FFFFFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}
