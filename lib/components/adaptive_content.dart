import 'package:flutter/material.dart';
import '../common/app_theme.dart';
import '../utils/breakpoint.dart';

/// 大屏居中限宽，并向子树注入 [Breakpoint.layoutWidth] 供栅格/卡片计算。
class AdaptiveContent extends StatelessWidget {
  final Widget child;
  final bool alignTop;

  const AdaptiveContent({
    super.key,
    required this.child,
    this.alignTop = true,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    if (!Breakpoint.needsContentConstraint(screenW)) {
      return child;
    }
    final layoutW = Breakpoint.layoutWidth(screenW);
    final layoutMedia = media.copyWith(size: Size(layoutW, media.size.height));
    final core = MediaQuery(
      data: layoutMedia,
      child: SizedBox(width: layoutW, child: child),
    );
    return ColoredBox(
      color: AppTheme.bg,
      child: alignTop
          ? Align(alignment: Alignment.topCenter, child: core)
          : Center(child: core),
    );
  }
}
