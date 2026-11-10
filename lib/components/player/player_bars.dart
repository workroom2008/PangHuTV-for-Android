import 'package:flutter/material.dart';
import '../../common/app_theme.dart';
import '../../utils/format_util.dart';

/// 播放器顶部控制栏（全屏模式），对齐 OHOS `PlayerSkin.topBar`
class PlayerTopBar extends StatelessWidget {
  final bool isFull;
  final bool showHud;
  final String errorText;
  final String title;
  final double topInset;
  final double leftInset;
  final double rightInset;
  final bool hasPrev;
  final bool hasNext;
  final String castDeviceName;
  final bool canCast;
  final VoidCallback onBack;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onCast;
  final VoidCallback? onStopCast;
  final VoidCallback? onPip;

  const PlayerTopBar({
    super.key,
    required this.isFull,
    required this.showHud,
    required this.errorText,
    required this.title,
    this.topInset = 0,
    this.leftInset = 0,
    this.rightInset = 0,
    this.hasPrev = false,
    this.hasNext = false,
    this.castDeviceName = '',
    this.canCast = false,
    required this.onBack,
    this.onPrev,
    this.onNext,
    this.onCast,
    this.onStopCast,
    this.onPip,
  });

  double _edge(double base, double inset) => base > inset ? base : inset;

  @override
  Widget build(BuildContext context) {
    if (!isFull || (!showHud && errorText.isEmpty)) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: _edge(8, topInset),
        left: _edge(8, leftInset),
        right: _edge(8, rightInset),
        bottom: 8,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xAA000000), Color(0x55000000), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasPrev)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.skip_previous_rounded, size: 16),
              label: const Text('上集', style: TextStyle(fontSize: 13)),
              onPressed: onPrev,
            ),
          if (hasNext)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.skip_next_rounded, size: 16),
              label: const Text('下集', style: TextStyle(fontSize: 13)),
              onPressed: onNext,
            ),
          if (onPip != null && castDeviceName.isEmpty && errorText.isEmpty)
            IconButton(
              icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 20),
              tooltip: '画中画',
              onPressed: onPip,
            ),
        ],
      ),
    );
  }
}

/// 播放器底部控制栏，对齐 OHOS `PlayerSkin.bottomBar`
class PlayerBottomBar extends StatefulWidget {
  final bool isReady;
  final bool isOpening;
  final bool showHud;
  final String errorText;
  final bool cinemaHud;
  final bool isFull;
  final bool isPlaying;
  final bool muted;
  final Duration currentPosition;
  final Duration totalDuration;
  final double currentSpeed;
  final String scaleLabel;
  final double leftInset;
  final double rightInset;
  final double bottomInset;
  final String castDeviceName;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleFull;
  final VoidCallback onToggleMute;
  final VoidCallback onSpeed;
  final VoidCallback? onScale;
  final ValueChanged<Duration>? onSeekStart;
  final ValueChanged<Duration>? onSeekProgress;
  final ValueChanged<Duration>? onSeekEnd;
  final ValueChanged<Duration> onSeekTo;

  const PlayerBottomBar({
    super.key,
    required this.isReady,
    required this.isOpening,
    required this.showHud,
    required this.errorText,
    required this.cinemaHud,
    required this.isFull,
    required this.isPlaying,
    required this.muted,
    required this.currentPosition,
    required this.totalDuration,
    required this.currentSpeed,
    required this.scaleLabel,
    this.leftInset = 0,
    this.rightInset = 0,
    this.bottomInset = 0,
    this.castDeviceName = '',
    required this.onTogglePlay,
    required this.onToggleFull,
    required this.onToggleMute,
    required this.onSpeed,
    this.onScale,
    this.onSeekStart,
    this.onSeekProgress,
    this.onSeekEnd,
    required this.onSeekTo,
  });

  @override
  State<PlayerBottomBar> createState() => _PlayerBottomBarState();
}

class _PlayerBottomBarState extends State<PlayerBottomBar> {
  bool _isDragging = false;
  double _dragMs = 0;

  double _edge(double base, double inset) => base > inset ? base : inset;

  Widget _buildSlider(BuildContext context) {
    final maxMs = widget.totalDuration.inMilliseconds > 0 ? widget.totalDuration.inMilliseconds.toDouble() : 1.0;
    final curMs = _isDragging
        ? _dragMs.clamp(0.0, maxMs)
        : widget.currentPosition.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2.5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: AppTheme.accent,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
      ),
      child: Slider(
        value: curMs,
        min: 0.0,
        max: maxMs,
        onChangeStart: (val) {
          setState(() {
            _isDragging = true;
            _dragMs = val;
          });
          widget.onSeekStart?.call(Duration(milliseconds: val.toInt()));
        },
        onChanged: (val) {
          setState(() {
            _dragMs = val;
          });
          widget.onSeekProgress?.call(Duration(milliseconds: val.toInt()));
        },
        onChangeEnd: (val) {
          setState(() {
            _isDragging = false;
          });
          final target = Duration(milliseconds: val.toInt());
          widget.onSeekEnd?.call(target);
          widget.onSeekTo(target);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isReady || widget.isOpening || !widget.showHud || widget.errorText.isNotEmpty || widget.castDeviceName.isNotEmpty) {
      return const SizedBox.shrink();
    }

    final displaySec = _isDragging ? (_dragMs / 1000.0) : widget.currentPosition.inSeconds.toDouble();
    final timeStr =
        '${FormatUtil.duration(displaySec)} / ${FormatUtil.duration(widget.totalDuration.inSeconds.toDouble())}';

    if (widget.cinemaHud) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          left: _edge(12, widget.leftInset),
          right: _edge(12, widget.rightInset),
          bottom: _edge(4, widget.bottomInset),
          top: 4,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xCC000000), Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSlider(context),
            Row(
              children: [
                IconButton(
                  icon: Icon(widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 24),
                  onPressed: widget.onTogglePlay,
                ),
                Text(timeStr, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                const Spacer(),
                InkWell(
                  onTap: widget.onSpeed,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    ),
                    child: Text('${widget.currentSpeed}x', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (widget.onScale != null)
                  InkWell(
                    onTap: widget.onScale,
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    child: Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      ),
                      child: Text(widget.scaleLabel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                IconButton(
                  icon: Icon(widget.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white, size: 20),
                  onPressed: widget.onToggleMute,
                ),
                IconButton(
                  icon: Icon(
                    widget.isFull ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: widget.onToggleFull,
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 竖屏底栏（精简对齐 OHOS：隐藏比例与静音，保留充足进度条宽度）
    return Container(
      width: double.infinity,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xB8000000), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 22,
            ),
            onPressed: widget.onTogglePlay,
          ),
          Expanded(child: _buildSlider(context)),
          Text(
            timeStr,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: widget.onSpeed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Text(
                '${widget.currentSpeed}x',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 20),
            onPressed: widget.onToggleFull,
          ),
        ],
      ),
    );
  }
}
