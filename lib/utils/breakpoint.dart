/// 窗口断点，对齐 OHOS `common/utils/Breakpoint.ets`
class Breakpoint {
  static const double md = 600;
  static const double lg = 840;
  static const double xl = 1440;

  static String ofWidth(double vp) {
    if (vp >= xl) return 'xl';
    if (vp >= lg) return 'lg';
    if (vp >= md) return 'md';
    return 'sm';
  }

  static bool isWide(String bp) => bp == 'md' || bp == 'lg' || bp == 'xl';

  static bool isWideWidth(double width) => isWide(ofWidth(width));

  /// 内容区最大宽度（TV/平板横屏居中，避免卡片与 Banner 过度拉伸）
  static double contentMaxWidth(double width) {
    if (width <= md) return width;
    if (width <= lg) return 920;
    if (width <= xl) return 1120;
    return 1280;
  }

  static double layoutWidth(double width) {
    final max = contentMaxWidth(width);
    return width < max ? width : max;
  }

  static bool needsContentConstraint(double width) => layoutWidth(width) < width - 1;

  /// 大屏主框架用侧栏导航（替代底部 Tab）
  static bool useNavigationRail(double width) => width >= lg;

  static const double maxCardWidth = 176;

  static int gridColsOf(double width) {
    final w = layoutWidth(width);
    final bp = ofWidth(w);
    if (w >= xl || bp == 'xl') return 8;
    if (w >= 1100) return 7;
    if (w >= lg || bp == 'lg') return 6;
    if (w >= md || bp == 'md') return 4;
    return 3;
  }

  static int listLanesOf(double width) {
    final bp = ofWidth(width);
    if (bp == 'xl') return 3;
    if (bp == 'lg' || bp == 'md') return 2;
    return 1;
  }

  /// 横向 FilmRow 卡片宽，对齐 OHOS `Breakpoint.cardWidth` 与 DailyUpdatePane 栅格卡片宽
  static double cardWidthOf(
    double width, {
    double? windowWidth,
    double horizontalPadding = 32.0,
    int? columns,
    double gap = 8.0,
  }) {
    final w = layoutWidth(windowWidth ?? width);
    final cols = columns ?? gridColsOf(w);
    final available = w - horizontalPadding;
    if (available <= 0 || cols <= 0) return 104.0;
    final cardW = (available - (cols - 1) * gap) / cols;
    if (cardW > maxCardWidth) return maxCardWidth;
    return cardW < 104 ? 104.0 : cardW;
  }

  /// FilmCard 宽高比：海报 2:3 (高=宽*1.5) + 标题/副标题高度与边距 41
  static double filmCardAspectRatio(double cardWidth) {
    if (cardWidth <= 0) return 0.52;
    return cardWidth / (cardWidth * 1.5 + 41.0);
  }

  /// 网格海报宽高比计算，避免在窄屏或分屏时因固定 0.54 导致文字下溢 (RenderFlex overflow)
  static double gridAspectRatio({
    required double width,
    required int columns,
    double horizontalPadding = 24.0,
    double crossAxisSpacing = 8.0,
  }) {
    final w = layoutWidth(width);
    final available = w - horizontalPadding;
    if (available <= 0 || columns <= 0) return 0.52;
    final cardW = (available - (columns - 1) * crossAxisSpacing) / columns;
    return filmCardAspectRatio(cardW.clamp(104.0, maxCardWidth));
  }

  static double bannerHeight({
    required double width,
    required double height,
    required bool multi,
  }) {
    if (isWideWidth(width)) {
      if (height > 0 && height < 500) {
        return multi ? 240 : 255;
      }
      return multi ? 340 : 360;
    }
    return multi ? 420 : 440;
  }

  static double bannerPeek(double width) {
    if (width >= xl) return 140;
    if (width >= 1100) return 104;
    if (width >= 780 || ofWidth(width) == 'lg' || ofWidth(width) == 'xl') {
      return 84;
    }
    if (isWideWidth(width) || width >= md) return 68;
    return 20;
  }

  static double bannerItemSpace(double width) => isWideWidth(width) ? 14 : 10;
}
