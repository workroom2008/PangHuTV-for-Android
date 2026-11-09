import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'player_scale.dart';
import '../../utils/format_util.dart';

/// 播放器视频渲染画面与海报层，对齐 OHOS `PlayerVideoLayer.ets`
///
/// 渲染内核为 media_kit_video（libmpv 纹理），替代原先的 video_player。
class PlayerVideoSurface extends StatelessWidget {
  final VideoController? controller;
  final PlayerScaleMode scaleMode;
  final String poster;
  final bool isOpening;
  final bool isReady;

  /// libmpv 渲染出的视频宽高（由播放器状态层提供，0 表示尚未就绪）。
  final double videoWidth;
  final double videoHeight;

  const PlayerVideoSurface({
    super.key,
    required this.controller,
    required this.scaleMode,
    required this.poster,
    this.isOpening = false,
    this.isReady = false,
    this.videoWidth = 0,
    this.videoHeight = 0,
  });

  Widget _buildVideo(VideoController c) {
    final w = videoWidth > 0 ? videoWidth : 16.0;
    final h = videoHeight > 0 ? videoHeight : 9.0;
    final aspect = (videoWidth > 0 && videoHeight > 0) ? (videoWidth / videoHeight) : (16 / 9);
    final video = Video(
      controller: c,
      key: ValueKey(c),
      // 画面比例交给外层容器控制，避免 libmpv 自带 letterbox 与 FittedBox 冲突。
      controls: NoVideoControls,
      fit: BoxFit.fill,
    );
    if (scaleMode == PlayerScaleMode.fit) {
      return Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: video,
        ),
      );
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: PlayerScale.boxFit(scaleMode),
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: w,
          height: h,
          child: video,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final hasInitializedVideo = c != null && isReady;
    // 对齐 OHOS `if (this.poster && (!this.ready || this.opening))`：未就绪或打开中展示完整封面
    final showPoster = poster.isNotEmpty && (!isReady || isOpening);

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasInitializedVideo)
            _buildVideo(c),
          if (showPoster)
            Positioned.fill(
              child: Container(
                color: Colors.black, // 对齐 OHOS PlayerVideoLayer.BG_COLOR：纯黑底色阻断底层画面漏光
                alignment: Alignment.center,
                child: Image.network(
                  poster,
                  headers: FormatUtil.imageHeaders(poster),
                  fit: BoxFit.contain, // 对齐 OHOS ImageFit.Contain：完整展示不裁切
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
