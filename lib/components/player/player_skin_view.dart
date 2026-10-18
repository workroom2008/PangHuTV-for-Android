import 'package:flutter/material.dart';
import '../../common/app_theme.dart';
import 'player_gesture_handler.dart';
import 'player_error_pad.dart';
import 'player_bars.dart';
import 'player_loading_card.dart';

/// 播放器覆盖层控制栏组件（全量对齐鸿蒙端 PlayerSkin）
class PlayerSkinView extends StatelessWidget {
  final bool isFull;
  final bool edgeHud;
  final bool showHud;
  final bool showBack;
  final String title;
  final bool isPlaying;
  final bool isBuffering;
  final bool isOpening;
  final bool pickerOpen;
  final int loadSessionId;
  final bool isReady;
  final bool isCompleted;
  final bool muted;
  final String errorText;
  final Duration currentPosition;
  final Duration totalDuration;
  final double currentSpeed;
  final String scaleLabel;
  final bool hasPrev;
  final bool hasNext;
  final PlayerPanState panState;
  final double topInset;
  final double leftInset;
  final double rightInset;
  final double bottomInset;
  final String castDeviceName;
  final bool canCast;
  final VoidCallback onBack;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleFull;
  final VoidCallback onToggleMute;
  final VoidCallback onSpeed;
  final VoidCallback? onScale;
  final VoidCallback onRetry;
  final VoidCallback? onErrorDetail;
  final VoidCallback? onExternalPlay;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onSeekBack10;
  final VoidCallback onSeekFwd10;
  final ValueChanged<Duration>? onSeekStart;
  final ValueChanged<Duration>? onSeekProgress;
  final ValueChanged<Duration>? onSeekEnd;
  final ValueChanged<Duration> onSeekTo;
  final VoidCallback? onCast;
  final VoidCallback? onStopCast;
  final VoidCallback? onPip;

  const PlayerSkinView({
    super.key,
    required this.isFull,
    this.edgeHud = false,
    required this.showHud,
    this.showBack = true,
    required this.title,
    required this.isPlaying,
    required this.isBuffering,
    this.isOpening = false,
    this.pickerOpen = false,
    this.loadSessionId = 0,
    this.isReady = false,
    this.isCompleted = false,
    this.muted = false,
    this.errorText = '',
    required this.currentPosition,
    required this.totalDuration,
    this.currentSpeed = 1.0,
    this.scaleLabel = '适应',
    this.hasPrev = false,
    this.hasNext = false,
    this.panState = const PlayerPanState(),
    this.topInset = 0,
    this.leftInset = 0,
    this.rightInset = 0,
    this.bottomInset = 0,
    this.castDeviceName = '',
    this.canCast = false,
    required this.onBack,
    required this.onTogglePlay,
    required this.onToggleFull,
    required this.onToggleMute,
    required this.onSpeed,
    this.onScale,
    required this.onRetry,
    this.onErrorDetail,
    this.onExternalPlay,
    this.onPrev,
    this.onNext,
    required this.onSeekBack10,
    required this.onSeekFwd10,
    this.onSeekStart,
    this.onSeekProgress,
    this.onSeekEnd,
    required this.onSeekTo,
    this.onCast,
    this.onStopCast,
    this.onPip,
  });

  bool get _isLoading {
    if (castDeviceName.isNotEmpty || errorText.isNotEmpty) return false;
    if (pickerOpen) return false;
    if (isOpening) return true;
    if (!isPlaying || isCompleted) return false;
    return isBuffering;
  }

  double _edge(double base, double inset) => base > inset ? base : inset;

  bool get _cinemaHud => isFull || edgeHud;

  bool get _showCenterPlay =>
      showHud &&
      !_isLoading &&
      errorText.isEmpty &&
      castDeviceName.isEmpty &&
      (!isPlaying || isCompleted);

  double get _progressPercent {
    if (totalDuration.inMilliseconds <= 0) return 0.0;
    return (currentPosition.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0);
  }

  Widget _buildCenterGroup(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (panState.kind != PlayerTipKind.none && castDeviceName.isEmpty)
            IgnorePointer(
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xBD000000),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [BoxShadow(color: Color(0x38000000), blurRadius: 14, offset: Offset(0, 8))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (panState.kind == PlayerTipKind.seekFwd)
                      const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 18)
                    else if (panState.kind == PlayerTipKind.seekBack)
                      const Icon(Icons.fast_rewind_rounded, color: Colors.white, size: 18)
                    else if (panState.kind == PlayerTipKind.brightness)
                      const Icon(Icons.wb_sunny_rounded, color: Colors.white, size: 18)
                    else if (panState.kind == PlayerTipKind.volume)
                      Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white, size: 18)
                    else if (panState.kind == PlayerTipKind.scale)
                      const Icon(Icons.aspect_ratio_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      panState.text,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          PlayerLoadingCard(
            visible: _isLoading,
            isOpening: isOpening,
            resetToken: loadSessionId,
            onRetry: onRetry,
          ),
          if (_showCenterPlay)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isFull) ...[
                  _buildCircleBtn(label: '-10', onTap: onSeekBack10),
                  const SizedBox(width: 28),
                ],
                GestureDetector(
                  onTap: onTogglePlay,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0x66000000),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: Icon(
                      isCompleted ? Icons.replay_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
                if (isFull) ...[
                  const SizedBox(width: 28),
                  _buildCircleBtn(label: '+10', onTap: onSeekFwd10),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCircleBtn({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildRoundBtn({required IconData icon, Color color = Colors.white, VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Color(0x33000000),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
        Positioned(
          top: _edge(0, topInset),
          bottom: _edge(0, bottomInset),
          left: _edge(0, leftInset),
          right: _edge(0, rightInset),
          child: IgnorePointer(
            ignoring: !_isLoading && !_showCenterPlay,
            child: _buildCenterGroup(context),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: PlayerBottomBar(
            isReady: isReady,
            isOpening: isOpening && !pickerOpen,
            showHud: showHud,
            errorText: errorText,
            cinemaHud: _cinemaHud,
            isFull: isFull,
            isPlaying: isPlaying,
            muted: muted,
            currentPosition: currentPosition,
            totalDuration: totalDuration,
            currentSpeed: currentSpeed,
            scaleLabel: scaleLabel,
            leftInset: leftInset,
            rightInset: rightInset,
            bottomInset: bottomInset,
            castDeviceName: castDeviceName,
            onTogglePlay: onTogglePlay,
            onToggleFull: onToggleFull,
            onToggleMute: onToggleMute,
            onSpeed: onSpeed,
            onScale: onScale,
            onSeekStart: onSeekStart,
            onSeekProgress: onSeekProgress,
            onSeekEnd: onSeekEnd,
            onSeekTo: onSeekTo,
          ),
        ),
        if (isReady && !isOpening && !showHud && errorText.isEmpty && castDeviceName.isEmpty && totalDuration.inMilliseconds > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(height: 2, color: Colors.white12),
                    Container(
                      height: 2,
                      width: constraints.maxWidth * _progressPercent,
                      color: AppTheme.accent,
                    ),
                  ],
                );
              },
            ),
          ),
        if (errorText.isNotEmpty && castDeviceName.isEmpty)
          PlayerErrorPad(
            errorText: errorText,
            topInset: topInset,
            leftInset: leftInset,
            rightInset: rightInset,
            bottomInset: bottomInset,
            onRetry: onRetry,
            onErrorDetail: onErrorDetail,
            onExternalPlay: onExternalPlay,
          ),
        if (isFull)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: PlayerTopBar(
              isFull: isFull,
              showHud: showHud,
              errorText: errorText,
              title: title,
              topInset: topInset,
              leftInset: leftInset,
              rightInset: rightInset,
              hasPrev: hasPrev,
              hasNext: hasNext,
              castDeviceName: castDeviceName,
              canCast: canCast,
              onBack: onBack,
              onPrev: onPrev,
              onNext: onNext,
              onCast: onCast,
              onStopCast: onStopCast,
              onPip: onPip,
            ),
          ),
        if (!isFull && (showBack || canCast || onPip != null))
          Positioned(
            left: _edge(6, leftInset),
            right: _edge(6, rightInset),
            top: _edge(6, topInset),
            child: Row(
              children: [
                if (showBack)
                  _buildRoundBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack)
                else
                  const SizedBox.shrink(),
                const Spacer(),
                if (canCast && onCast != null) ...[
                  _buildRoundBtn(
                    icon: castDeviceName.isNotEmpty ? Icons.power_settings_new_rounded : Icons.cast_rounded,
                    color: castDeviceName.isNotEmpty ? AppTheme.danger : Colors.white,
                    onTap: castDeviceName.isNotEmpty ? onStopCast : onCast,
                  ),
                  const SizedBox(width: 8),
                ],
                if (onPip != null && castDeviceName.isEmpty)
                  _buildRoundBtn(
                    icon: Icons.picture_in_picture_alt_rounded,
                    onTap: onPip,
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
}
