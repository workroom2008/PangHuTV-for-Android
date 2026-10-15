import 'package:flutter/material.dart';
import '../../common/app_theme.dart';
import '../../components/player/play_side_tabs.dart';
import '../../models/film_models.dart';
import '../../utils/breakpoint.dart';
import '../../utils/split_cutout_insets.dart';

/// 现场播放页的主体布局（分屏与非分屏），对齐 PlayPage
class LivePlayBody extends StatelessWidget {
  final bool isSplit;
  final Widget playerWidget;
  final int activeTab;
  final ValueChanged<int> onTabChange;
  final String filmId;
  final String picture;
  final String name;
  final String subTitle;
  final String actor;
  final String plot;
  final MovieDescriptor? descriptor;
  final List<PlaySource> sources;
  final String playingSourceId;
  final String viewingSourceId;
  final int episodeIndex;
  final ValueChanged<String> onViewSource;
  final void Function(String sourceId, int index) onSelectEpisode;
  final bool relateLoading;
  final List<MovieBasicInfo> related;
  final void Function(MovieBasicInfo film) onOpenRelated;
  final String sourceName;
  final Widget? downloadRow;

  const LivePlayBody({
    super.key,
    required this.isSplit,
    required this.playerWidget,
    required this.activeTab,
    required this.onTabChange,
    required this.filmId,
    required this.picture,
    required this.name,
    required this.subTitle,
    required this.actor,
    required this.plot,
    this.descriptor,
    required this.sources,
    required this.playingSourceId,
    required this.viewingSourceId,
    required this.episodeIndex,
    required this.onViewSource,
    required this.onSelectEpisode,
    required this.relateLoading,
    required this.related,
    required this.onOpenRelated,
    required this.sourceName,
    this.downloadRow,
  });

  Widget _buildSideTabs(BuildContext context, {required int columns, bool split = false, double rightInset = 0}) {
    return PlaySideTabs(
      activeTab: activeTab,
      onTabChange: onTabChange,
      filmId: filmId,
      picture: picture,
      name: name,
      subTitle: subTitle,
      actor: actor,
      plot: plot,
      descriptor: descriptor,
      sources: sources,
      playingSourceId: playingSourceId,
      viewingSourceId: viewingSourceId,
      episodeIndex: episodeIndex,
      isSplit: split,
      rightInset: rightInset,
      onViewSource: onViewSource,
      onSelectEpisode: onSelectEpisode,
      relateLoading: relateLoading,
      related: related,
      columns: columns,
      onOpenRelated: onOpenRelated,
      sourceName: sourceName,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isSplit) {
      final media = MediaQuery.of(context);
      final cutout = SplitCutoutInsets.resolve(
        media.viewPadding,
        padding: media.padding,
        displayFeatures: media.displayFeatures,
        size: media.size,
      );

      return Row(
        children: [
          Expanded(
            flex: 7,
            child: Column(
              children: [
                Expanded(child: playerWidget),
                if (downloadRow != null) downloadRow!,
              ],
            ),
          ),
          Container(width: 1, color: const Color(0x24FFFFFF)),
          Expanded(
            flex: 5,
            child: Container(
              color: AppTheme.bgElevated,
              child: SafeArea(
                top: true,
                bottom: true,
                left: false,
                right: false,
                child: _buildSideTabs(
                  context,
                  columns: 3,
                  split: true,
                  rightInset: cutout.right,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: playerWidget,
        ),
        if (downloadRow != null) downloadRow!,
        Container(height: 8, color: AppTheme.bgElevated),
        Expanded(
          child: _buildSideTabs(
            context,
            columns: Breakpoint.gridColsOf(MediaQuery.sizeOf(context).width),
            split: false,
          ),
        ),
      ],
    );
  }
}
