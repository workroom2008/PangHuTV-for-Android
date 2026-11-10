import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'player_scale.dart';
import '../../utils/format_util.dart';

/// 播放器视频渲染画面与海报层，对齐 OHOS `PlayerVideoLayer.ets`
class PlayerVideoSurface extends StatelessWidget {
  final VideoPlayerController? controller;
  final PlayerScaleMode scaleMode;
  final String poster;
  final bool isOpening;
  final bool isReady;

  const PlayerVideoSurface({
    super.key,
    required this.controller,
    required this.scaleMode,
    required this.poster,
    this.isOpening = false,
    this.isReady = false,
  });

  Widget _buildVideo(VideoPlayerController c) {
    final size = c.value.size;
    final rot = c.value.rotationCorrection;
    final isRotated = rot == 90 || rot == 270;
    final w = isRotated ? size.height : size.width;
    final h = isRotated ? size.width : size.height;
    final effectiveW = w > 0 ? w : 16.0;
    final effectiveH = h > 0 ? h : 9.0;
    final aspect = (w > 0 && h > 0) ? (w / h) : (c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9);
    if (scaleMode == PlayerScaleMode.fit) {
      return Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: VideoPlayer(c, key: ValueKey(c)),
        ),
      );
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: PlayerScale.boxFit(scaleMode),
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: effectiveW,
          height: effectiveH,
          child: VideoPlayer(c, key: ValueKey(c)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final hasInitializedVideo = c != null && c.value.isInitialized;
    // 画面活跃中（已在播放或已有有效帧进度）时强制隐藏海报，避免视频画面透出与海报并存
    final isVideoActive = hasInitializedVideo && (c.value.isPlaying || c.value.position > Duration.zero);
    // 对齐 OHOS `if (this.poster && (!this.ready || this.opening))`：未就绪或打开中展示完整封面
    final showPoster = poster.isNotEmpty &&
        !isVideoActive &&
        (!isReady || isOpening || !hasInitializedVideo);

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
