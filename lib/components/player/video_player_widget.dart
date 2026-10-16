import 'package:flutter/material.dart';
import 'player_gesture_handler.dart';
import 'player_skin_view.dart';
import 'player_speed_sheet.dart';
import 'player_scale.dart';
import 'player_pip_coordinator.dart';
import 'player_video_surface.dart';
import 'player_playback_controller.dart';
import '../cast/player_cast_controller.dart';
import '../cast/player_cast_hud.dart';
import '../../types/dlna_types.dart';
import '../../utils/app_settings_manager.dart';
import '../../utils/external_player.dart';

/// 跨平台视频播放器，全量对齐 OHOS `VideoPlayer.ets`
class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String poster;
  final double initialTime;
  final bool showBack;
  final bool isFull;
  final bool hasPrev;
  final bool hasNext;
  final bool pageActive;
  final bool edgeHud;
  final int reloadToken;
  final double topInset;
  final double leftInset;
  final double rightInset;
  final double bottomInset;
  final VoidCallback? onBack;
  final VoidCallback? onEnded;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final void Function(bool full, {bool isPortrait})? onFullscreenChange;
  final void Function(double current, double duration)? onProgress;

  const VideoPlayerWidget({
    super.key,
    required this.videoUrl,
    this.title = '',
    this.poster = '',
    this.initialTime = 0,
    this.showBack = false,
    this.isFull = false,
    this.hasPrev = false,
    this.hasNext = false,
    this.pageActive = true,
    this.edgeHud = false,
    this.reloadToken = 0,
    this.topInset = 0,
    this.leftInset = 0,
    this.rightInset = 0,
    this.bottomInset = 0,
    this.onBack,
    this.onEnded,
    this.onPrev,
    this.onNext,
    this.onFullscreenChange,
    this.onProgress,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with WidgetsBindingObserver
    implements PlayerCastHost {
  final PlayerPlaybackController _playback = PlayerPlaybackController();
  final PlayerCastController _castCtrl = PlayerCastController();
  late final PlayerPipCoordinator _pipCoord;

  int _lastCastPersistMs = 0;

  @override
  double get currentPosition => _castCtrl.isCasting
      ? _castCtrl.session.positionSec
      : _playback.currentPositionSec;
  @override
  double get totalDuration => _castCtrl.isCasting
      ? (_castCtrl.session.durationSec > 0 ? _castCtrl.session.durationSec : _playback.totalDurationSec)
      : _playback.totalDurationSec;
  @override
  bool get isPlaying => _castCtrl.isCasting
      ? (_castCtrl.session.phase == CastPhase.playing)
      : _playback.isPlaying;
  @override
  bool get isOpening => _playback.isOpening;
  @override
  bool get isBuffering => _playback.isBuffering;
  @override
  String get videoUrl => widget.videoUrl;
  @override
  String get title => widget.title;
  @override
  bool get hasNext => widget.hasNext;
  @override
  double get volume => _playback.volume;
  @override
  bool get isFull => widget.isFull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _castCtrl.attachHost(this);
    _playback.onEnded = widget.onEnded;
    _playback.onProgress = (cur, dur) {
      if (!_castCtrl.isCasting) {
        widget.onProgress?.call(cur, dur);
      }
    };
    _playback.onStateChanged = () {
      _syncAutoPip();
      _pipCoord.updateAspectRatio(_playback.controller?.value.size);
    };
    _playback.onHardwareDecodeFailed = (url) => ExternalPlayer.open(url);

    _pipCoord = PlayerPipCoordinator(
      onStateChanged: () {
        if (mounted) setState(() {});
        if (!_pipCoord.isPipActive) _syncAutoPip();
      },
      onPlay: () {
        if (!_castCtrl.isCasting) {
          _playback.play();
        }
      },
      onPause: () {
        if (!_castCtrl.isCasting) {
          _playback.pause();
        }
      },
      onPrev: widget.onPrev,
      onNext: widget.onNext,
    )..init();

    _playback.loadWindowLevels();
    _beginPlayback();
  }

  Future<void> _beginPlayback({double? initialTime}) async {
    if (_castCtrl.isCasting) return;
    final t = initialTime ?? widget.initialTime;
    final raw = widget.videoUrl.trim();
    if (raw.isEmpty) {
      await _playback.initPlayer(raw, initialTime: t);
      return;
    }
    if (AppSettingsManager.instance.preferExternalPlayer) {
      final ok = await ExternalPlayer.open(raw);
      if (!mounted) return;
      if (ok) {
        _playback.handoffToExternalPlayer();
        return;
      }
      showToast('无法调起其它播放器，已改用内置播放');
    }
    await _playback.initPlayer(widget.videoUrl, initialTime: t);
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _playback.onEnded = widget.onEnded;
    if (oldWidget.videoUrl != widget.videoUrl || oldWidget.reloadToken != widget.reloadToken) {
      if (_castCtrl.isCasting) {
        final consumed = _castCtrl.handleSourceChange();
        if (!consumed) {
          _beginPlayback();
        }
      } else {
        _beginPlayback();
      }
    }
    if (oldWidget.hasPrev != widget.hasPrev || oldWidget.hasNext != widget.hasNext) {
      _syncAutoPip();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pipCoord.dispose();
    _castCtrl.dispose();
    _playback.dispose();
    super.dispose();
  }

  void _syncAutoPip() {
    _pipCoord.syncAutoPip(
      isCasting: _castCtrl.isCasting,
      videoUrl: widget.videoUrl,
      errorText: _playback.errorText,
      isPlaying: _playback.isPlaying,
      isCompleted: _playback.isCompleted,
      hasPrev: widget.hasPrev,
      hasNext: widget.hasNext,
      videoSize: _playback.controller?.value.size,
    );
  }

  bool _isPortraitVideo() {
    final c = _playback.controller;
    if (c == null || !c.value.isInitialized) return false;
    final size = c.value.size;
    final rot = c.value.rotationCorrection;
    final isRotated = rot == 90 || rot == 270;
    final w = isRotated ? size.height : size.width;
    final h = isRotated ? size.width : size.height;
    if (w > 0 && h > 0) {
      return h > w;
    }
    final aspect = c.value.aspectRatio;
    return aspect > 0 && aspect < 1.0;
  }

  void _toggleFullscreen() {
    if (_castCtrl.isCasting) {
      showToast('投屏中无法全屏，请先停止投屏');
      return;
    }
    widget.onFullscreenChange?.call(!widget.isFull, isPortrait: _isPortraitVideo());
  }

  void _handleManualStartPip() {
    _pipCoord.enterPip(
      videoSize: _playback.controller?.value.size,
      isCasting: _castCtrl.isCasting,
      isFull: widget.isFull,
      onExitFullscreen: () => widget.onFullscreenChange?.call(false, isPortrait: _isPortraitVideo()),
      showToast: showToast,
    );
  }

  @override
  void parkLocal() {
    _playback.parkForCast();
    _syncAutoPip();
  }

  @override
  void pauseLocal() {
    _playback.pauseLocal();
    _syncAutoPip();
  }

  @override
  void exitFullForCast() {
    if (widget.isFull) {
      widget.onFullscreenChange?.call(false, isPortrait: _isPortraitVideo());
    }
  }

  @override
  void resumeLocal(double targetSec, bool wasPlaying) {
    // 投屏选择器取消时本地播放器仍在：只 seek/play，避免 initPlayer 导致画面重载。
    // 仍在打开中也不要重挂，否则会打断进行中的 initialize。
    final c = _playback.controller;
    if ((c != null && c.value.isInitialized) || _playback.isOpening) {
      _playback.resumeLocal(targetSec, wasPlaying);
    } else {
      _playback.initPlayer(widget.videoUrl, initialTime: targetSec, autoPlay: wasPlaying);
    }
    _syncAutoPip();
  }

  @override
  void remountCompleted(double positionSec, double durationSec) {
    _playback.remountCompleted(positionSec, durationSec);
    _syncAutoPip();
  }

  @override
  void onCastEnded() => widget.onEnded?.call();

  @override
  void syncUi() {
    if (mounted) setState(() {});
  }

  @override
  void syncProgress(double currentSec, double durationSec) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (widget.onProgress != null && durationSec > 0) {
      if (now - _lastCastPersistMs >= 5000) {
        _lastCastPersistMs = now;
        widget.onProgress!(currentSec, durationSec);
      }
    }
  }

  @override
  void showToast(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void setPipAutoStart(bool enable) {
    _syncAutoPip();
  }

  @override
  void stopPip() {}

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _playback,
      builder: (context, _) {
        final pickerOpen = _castCtrl.pausedForPicker && !_castCtrl.isCasting;
        if (_pipCoord.isPipActive) {
          return Container(
            color: Colors.black,
            child: PlayerVideoSurface(
              controller: _playback.controller,
              scaleMode: _playback.scaleMode,
              poster: widget.poster,
              isOpening: _playback.isOpening,
              isReady: _playback.isReady,
            ),
          );
        }

        return Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PlayerGestureHandler(
                currentPosition: _playback.currentPosition,
                totalDuration: _playback.totalDuration,
                isPlaying: _playback.isPlaying,
                isFull: widget.isFull,
                currentSpeed: _playback.currentSpeed,
                currentBrightness: _playback.brightness,
                currentVolume: _playback.volume,
                onSingleTap: _playback.toggleHud,
                onDoubleTap: () {
                  if (!_castCtrl.isCasting) _playback.togglePlay();
                },
                onSeekProgress: _playback.setDragPreview,
                onSeekEnd: _playback.seekTo,
                onSpeedChange: _playback.setSpeed,
                onBrightnessChange: _playback.setBrightness,
                onVolumeChange: (v) {
                  _playback.setVolume(v);
                  if (_castCtrl.isCasting) {
                    _castCtrl.pushCastVolume(v);
                  }
                },
                onPanStateChange: _playback.setPanState,
                child: PlayerVideoSurface(
                  controller: _playback.controller,
                  scaleMode: _playback.scaleMode,
                  poster: widget.poster,
                  isOpening: _playback.isOpening,
                  isReady: _playback.isReady,
                ),
              ),
              if (_castCtrl.deviceName.isNotEmpty && !widget.isFull)
                Center(
                  child: PlayerCastHud(
                    deviceName: _castCtrl.deviceName,
                    positionSec: _castCtrl.session.positionSec,
                    durationSec: _castCtrl.session.durationSec > 0
                        ? _castCtrl.session.durationSec
                        : totalDuration,
                    phase: _castCtrl.session.phase,
                    transportState: _castCtrl.session.transportState,
                    castSession: _castCtrl.session,
                    onStopCast: () => _castCtrl.endCastByUser(),
                  ),
                ),
              PlayerSkinView(
                isFull: widget.isFull,
                edgeHud: widget.edgeHud,
                showHud: _playback.showHud || pickerOpen,
                showBack: widget.showBack,
                title: widget.title,
                isPlaying: _castCtrl.isCasting
                    ? (_castCtrl.session.phase == CastPhase.playing)
                    : _playback.isPlaying,
                isBuffering: _castCtrl.isCasting
                    ? (_castCtrl.session.phase == CastPhase.launching)
                    : _playback.isBuffering,
                isOpening: _castCtrl.isCasting ? false : _playback.isOpening,
                pickerOpen: pickerOpen,
                loadSessionId: _playback.initSessionId,
                isReady: _castCtrl.isCasting ? true : _playback.isReady,
                isCompleted: _castCtrl.isCasting ? false : _playback.isCompleted,
                muted: _playback.muted,
                errorText: _playback.errorText,
                currentPosition: _castCtrl.isCasting
                    ? Duration(seconds: _castCtrl.session.positionSec.toInt())
                    : _playback.displayPosition,
                totalDuration: _castCtrl.isCasting
                    ? (_castCtrl.session.durationSec > 0
                        ? Duration(seconds: _castCtrl.session.durationSec.toInt())
                        : _playback.totalDuration)
                    : _playback.totalDuration,
                currentSpeed: _playback.currentSpeed,
                scaleLabel: PlayerScale.label(_playback.scaleMode),
                hasPrev: widget.hasPrev,
                hasNext: widget.hasNext,
                panState: _playback.panState,
                topInset: widget.topInset,
                leftInset: widget.leftInset,
                rightInset: widget.rightInset,
                bottomInset: widget.bottomInset,
                castDeviceName: _castCtrl.deviceName,
                canCast: widget.videoUrl.trim().isNotEmpty,
                onBack: () {
                  if (widget.isFull) {
                    _toggleFullscreen();
                  } else {
                    widget.onBack?.call();
                  }
                },
                onTogglePlay: () {
                  if (!_castCtrl.isCasting) {
                    if (_playback.controller == null && _playback.isCompleted) {
                      _playback.initPlayer(widget.videoUrl, initialTime: 0, autoPlay: true);
                    } else {
                      _playback.togglePlay();
                    }
                  }
                },
                onToggleFull: _toggleFullscreen,
                onToggleMute: () {
                  _playback.toggleMute();
                  if (_castCtrl.isCasting) {
                    _castCtrl.pushCastVolume(_playback.muted ? 0.0 : _playback.volume);
                  }
                },
                onSpeed: () => PlayerSpeedSheet.show(context, _playback.currentSpeed, _playback.setSpeed),
                onScale: _playback.cycleScale,
                onRetry: () {
                  if (!_castCtrl.isCasting) {
                    _beginPlayback(initialTime: _playback.currentPositionSec);
                  }
                },
                onExternalPlay: widget.videoUrl.trim().isEmpty
                    ? null
                    : () async {
                        final ok = await ExternalPlayer.open(widget.videoUrl);
                        if (!mounted) return;
                        if (!ok) showToast('无法调起其它播放器，请安装 MX Player、VLC 等后重试');
                      },
                onPrev: widget.onPrev,
                onNext: widget.onNext,
                onSeekBack10: () {
                  final target = Duration(seconds: (currentPosition - 10).clamp(0, totalDuration).toInt());
                  _playback.seekTo(target);
                },
                onSeekFwd10: () {
                  final target = Duration(seconds: (currentPosition + 10).clamp(0, totalDuration).toInt());
                  _playback.seekTo(target);
                },
                onSeekStart: _playback.setDragPreview,
                onSeekProgress: _playback.setDragPreview,
                onSeekTo: _playback.seekTo,
                onCast: () => _castCtrl.openCastDialog(context),
                onStopCast: () => _castCtrl.endCastByUser(),
                onPip: _pipCoord.pipSupported ? _handleManualStartPip : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
