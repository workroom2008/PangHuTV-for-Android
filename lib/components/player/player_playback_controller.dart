import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../api/http_client.dart';
import '../../utils/playback_url.dart';
import 'player_gesture_handler.dart';
import 'player_speed.dart';
import 'player_scale.dart';
import 'player_stall_watcher.dart';
import 'player_device_control_mixin.dart';

/// 播放器会话与播放状态控制器，管理生命周期、缓冲检测与控制指令
class PlayerPlaybackController extends ChangeNotifier with PlayerDeviceControlMixin {
  VideoPlayerController? _controller;
  VideoPlayerController? get controller => _controller;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;
  bool _isBuffering = false;
  bool get isBuffering => _isBuffering;
  bool _isOpening = true;
  bool get isOpening => _isOpening;
  bool _isCompleted = false;
  bool get isCompleted => _isCompleted;
  bool _isDragging = false;
  bool get isDragging => _isDragging;
  bool _isSeeking = false;
  bool get isSeeking => _isSeeking;
  bool _playRequested = false;
  bool get playRequested => _playRequested;
  String _errorText = '';
  String get errorText => _errorText;

  Duration _currentPosition = Duration.zero;
  Duration get currentPosition => _currentPosition;
  double get currentPositionSec => _currentPosition.inMilliseconds / 1000.0;

  Duration _totalDuration = Duration.zero;
  Duration get totalDuration => _totalDuration;
  double get totalDurationSec => _totalDuration.inMilliseconds / 1000.0;

  Duration? _dragPreviewPosition;
  Duration? get dragPreviewPosition => _dragPreviewPosition;
  Duration get displayPosition => _dragPreviewPosition ?? _currentPosition;

  double _currentSpeed = PlayerSpeed.defaultRate;
  double get currentSpeed => _currentSpeed;
  bool _showHud = true;
  bool get showHud => _showHud;
  PlayerPanState _panState = const PlayerPanState();
  PlayerPanState get panState => _panState;
  PlayerScaleMode _scaleMode = PlayerScale.defaultMode;
  PlayerScaleMode get scaleMode => _scaleMode;

  final PlayerStallWatcher watcher = PlayerStallWatcher();
  int _initSessionId = 0;
  int get initSessionId => _initSessionId;
  bool _hasSeekedInitial = false;
  int _lastPersistMs = 0;

  VoidCallback? onEnded;
  void Function(double current, double duration)? onProgress;
  VoidCallback? onStateChanged;

  bool get isReady => _controller != null && _controller!.value.isInitialized && !_isOpening;

  void _safeSetWakelock(bool enable) => safeSetWakelock(enable);

  void _handleOpenTimeout(int sessionId) {
    if (sessionId != _initSessionId || !_isOpening) return;
    watcher.clearOpenWatch();
    _initSessionId++;
    _isOpening = false;
    _isBuffering = false;
    _playRequested = false;
    _errorText = '视频打开超时(${PlayerStallWatcher.openTimeoutMs ~/ 1000}s)';
    final stale = _controller;
    _controller = null;
    stale?.removeListener(_onControllerUpdate);
    stale?.dispose().catchError((_) {});
    notifyListeners();
    onStateChanged?.call();
  }

  void _handleInitFailure(int sessionId, Object e) {
    if (sessionId != _initSessionId) return;
    _isOpening = false;
    _isBuffering = false;
    _isPlaying = false;
    _playRequested = false;
    final detail = '$e';
    if (_isDecoderInitError(e)) {
      _errorText = '当前设备解码失败，请切换线路或换源后重试';
    } else {
      _errorText = '视频加载失败: $detail';
    }
    notifyListeners();
    onStateChanged?.call();
  }

  @visibleForTesting
  void debugArmOpeningSession() {
    _initSessionId++;
    _isOpening = true;
    _isBuffering = true;
    _isPlaying = false;
    _playRequested = true;
    _isCompleted = false;
    _errorText = '';
    notifyListeners();
  }

  @visibleForTesting
  void debugExpireOpenWatch() {
    _handleOpenTimeout(_initSessionId);
  }

  @visibleForTesting
  void debugLateInitFailure(int sessionId, Object error) {
    _handleInitFailure(sessionId, error);
  }

  static bool _isDecoderInitError(Object e) {
    final s = e.toString();
    return s.contains('MediaCodec') ||
        s.contains('VideoError') ||
        s.contains('MediaCodecVideoRenderer');
  }

  Future<void> initPlayer(
    String videoUrl, {
    double initialTime = 0,
    bool autoPlay = true,
    bool allowDecoderRetry = true,
  }) async {
    final sessionId = ++_initSessionId;
    watcher.dispose();

    final oldController = _controller;
    _controller = null;
    oldController?.removeListener(_onControllerUpdate);
    try { await oldController?.pause(); } catch (_) {}
    try { await oldController?.dispose(); } catch (_) {}

    if (sessionId != _initSessionId) return;
    _hasSeekedInitial = false;

    final url = PlaybackUrl.prepareForPlayer(videoUrl);
    if (url.isEmpty) {
      watcher.clearOpenWatch();
      _isOpening = false;
      _isBuffering = false;
      _isPlaying = false;
      _playRequested = false;
      _errorText = videoUrl.trim().isNotEmpty ? '暂无可用播放地址' : '';
      notifyListeners();
      onStateChanged?.call();
      return;
    }

    _isOpening = true;
    _isBuffering = true;
    _isPlaying = false;
    _playRequested = autoPlay;
    _isCompleted = false;
    _errorText = '';
    _showHud = true;
    notifyListeners();
    onStateChanged?.call();

    watcher.armOpenWatch(() {
      _handleOpenTimeout(sessionId);
    }, isOpening: true);

    VideoPlayerController? newController;
    try {
      final uri = Uri.parse(url);
      if (PlaybackUrl.needsServerApiAuth(url)) {
        final httpHeaders = await HttpClient.instance.mediaRequestHeaders();
        newController = VideoPlayerController.networkUrl(uri, httpHeaders: httpHeaders);
      } else {
        newController = VideoPlayerController.networkUrl(uri);
      }
      await newController.initialize();
      if (sessionId != _initSessionId) {
        newController.dispose().catchError((_) {});
        return;
      }

      watcher.clearOpenWatch();
      newController.addListener(_onControllerUpdate);
      _controller = newController;

      if (initialTime > 0 && !_hasSeekedInitial) {
        _hasSeekedInitial = true;
        await newController.seekTo(Duration(seconds: initialTime.toInt()));
      }

      await newController.setPlaybackSpeed(_currentSpeed);
      await newController.setVolume(muted ? 0.0 : 1.0);
      if (autoPlay) {
        await newController.play();
        safeSetWakelock(true);
      } else {
        await newController.pause();
        safeSetWakelock(false);
      }

      if (sessionId == _initSessionId) {
        _isOpening = false;
        _isBuffering = false;
        _errorText = '';
        _totalDuration = newController.value.duration;
        _isPlaying = autoPlay;
        _playRequested = autoPlay;
        armHideHud();
        notifyListeners();
        onStateChanged?.call();
      }
    } catch (e) {
      watcher.clearOpenWatch();
      newController?.dispose().catchError((_) {});
      if (_controller == newController) _controller = null;
      if (allowDecoderRetry && sessionId == _initSessionId && _isDecoderInitError(e)) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (sessionId != _initSessionId) return;
        await initPlayer(
          videoUrl,
          initialTime: initialTime,
          autoPlay: autoPlay,
          allowDecoderRetry: false,
        );
        return;
      }
      _handleInitFailure(sessionId, e);
    }
  }

  void _onControllerUpdate() {
    final c = _controller;
    if (c == null) return;
    final value = c.value;
    final playing = value.isPlaying;
    final buffering = value.isBuffering;
    final pos = value.position;
    final dur = value.duration;
    final completed = dur.inSeconds > 0 && pos >= dur && !buffering;

    if ((playing || pos > Duration.zero) && _isOpening) _isOpening = false;
    if (_isDragging || _isSeeking) {
      if (dur != _totalDuration || buffering != _isBuffering) {
        _totalDuration = dur;
        _isBuffering = buffering;
        notifyListeners();
      }
      return;
    }

    if (playing != _isPlaying || buffering != _isBuffering || pos != _currentPosition || dur != _totalDuration || completed != _isCompleted) {
      final justCompleted = completed && !_isCompleted;
      if (!playing && !buffering && !_isOpening) {
        _isPlaying = false;
        _playRequested = false;
      } else if (playing) {
        _isPlaying = true;
        _playRequested = true;
      }
      _isBuffering = buffering;
      _currentPosition = pos;
      _totalDuration = dur;
      _isCompleted = completed;
      if (completed) {
        _playRequested = false;
        _isPlaying = false;
      }
      watcher.clearSeekWatch();

      final now = DateTime.now().millisecondsSinceEpoch;
      if (onProgress != null && dur.inSeconds > 0 && _dragPreviewPosition == null) {
        if (completed || now - _lastPersistMs >= PlayerStallWatcher.progressPersistMs) {
          _lastPersistMs = now;
          onProgress!(pos.inSeconds.toDouble(), dur.inSeconds.toDouble());
        }
      }
      notifyListeners();
      onStateChanged?.call();
      if (justCompleted) onEnded?.call();
    }
  }

  void armHideHud() {
    watcher.armHide(() {
      if (_isPlaying && !_isCompleted && _panState.kind == PlayerTipKind.none && !_isDragging) {
        _showHud = false;
        notifyListeners();
      }
    }, canHide: _isPlaying && !_isCompleted && _errorText.isEmpty && !_isDragging);
  }

  void toggleHud() {
    if (_panState.kind != PlayerTipKind.none) return;
    _showHud = !_showHud;
    _showHud ? armHideHud() : watcher.clearHide();
    notifyListeners();
  }

  void togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_isCompleted) {
      seekTo(Duration.zero);
      c.play();
      _safeSetWakelock(true);
      _isCompleted = false;
      _playRequested = true;
      _isPlaying = true;
      _showHud = true;
      armHideHud();
      notifyListeners();
      return;
    }
    if (_isPlaying || c.value.isPlaying) {
      _playRequested = false;
      c.pause();
      _safeSetWakelock(false);
      _isPlaying = false;
      _isBuffering = false;
      _showHud = true;
      watcher.clearHide();
    } else {
      _playRequested = true;
      c.play();
      _safeSetWakelock(true);
      _isPlaying = true;
      armHideHud();
    }
    notifyListeners();
  }

  void play() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_isCompleted) {
      seekTo(Duration.zero);
      _isCompleted = false;
    }
    _playRequested = true;
    c.play();
    _safeSetWakelock(true);
    _isPlaying = true;
    notifyListeners();
  }

  void pause() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _playRequested = false;
    c.pause();
    _safeSetWakelock(false);
    _isPlaying = false;
    _isBuffering = false;
    watcher.clearHide();
    notifyListeners();
  }

  void parkForCast() {
    _initSessionId++;
    watcher.clearOpenWatch();
    watcher.clearSeekWatch();
    watcher.clearHide();
    _safeSetWakelock(false);
    _isPlaying = false;
    _playRequested = false;
    _isBuffering = false;
    _isOpening = false;
    _isCompleted = false;
    _errorText = '';
    final old = _controller;
    _controller = null;
    old?.removeListener(_onControllerUpdate);
    old?.pause().catchError((_) {});
    old?.dispose().catchError((_) {});
    notifyListeners();
  }

  void pauseLocal() {
    _controller?.pause().catchError((_) {});
    _safeSetWakelock(false);
    _isPlaying = false;
    _playRequested = false;
    _isBuffering = false;
    _showHud = true;
    watcher.clearHide();
    notifyListeners();
  }

  void resumeLocal(double targetSec, bool wasPlaying) {
    _isOpening = false;
    _playRequested = wasPlaying;
    seekTo(Duration(seconds: targetSec.toInt()));
    if (wasPlaying) {
      _controller?.play().catchError((_) {});
      _safeSetWakelock(true);
      _isPlaying = true;
    } else {
      _controller?.pause().catchError((_) {});
      _safeSetWakelock(false);
      _isPlaying = false;
    }
    notifyListeners();
  }

  void remountCompleted(double positionSec, double durationSec) {
    _initSessionId++;
    watcher.clearOpenWatch();
    watcher.clearSeekWatch();
    watcher.clearHide();
    _safeSetWakelock(false);
    final old = _controller;
    _controller = null;
    old?.removeListener(_onControllerUpdate);
    old?.pause().catchError((_) {});
    old?.dispose().catchError((_) {});
    _isPlaying = false;
    _playRequested = false;
    _isBuffering = false;
    _isOpening = false;
    _isCompleted = true;
    _errorText = '';
    _currentPosition = Duration(seconds: positionSec.toInt());
    if (durationSec > 0) _totalDuration = Duration(seconds: durationSec.toInt());
    notifyListeners();
  }

  Future<void> seekTo(Duration target) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final wasPlaying = _isPlaying || _playRequested;
    _dragPreviewPosition = null;
    _isDragging = false;
    _currentPosition = target;
    _isSeeking = true;

    if (_isCompleted && target < _totalDuration) {
      _isCompleted = false;
    }

    if (wasPlaying) {
      _isPlaying = true;
      _playRequested = true;
    }

    watcher.armSeekWatch(() {
      _isSeeking = false;
      showTransient(const PlayerPanState(kind: PlayerTipKind.seekFwd, text: 'Seek超时'));
    }, isSeeking: true);

    armHideHud();
    notifyListeners();

    try {
      await c.seekTo(target);
      if (wasPlaying && _playRequested) {
        await c.play();
        _safeSetWakelock(true);
        _isPlaying = true;
      }
    } catch (_) {
    } finally {
      _isSeeking = false;
      watcher.clearSeekWatch();
      notifyListeners();
    }
  }

  void setSpeed(double speed) {
    _currentSpeed = speed;
    _controller?.setPlaybackSpeed(speed);
    armHideHud();
    notifyListeners();
  }

  void cycleScale() {
    _scaleMode = PlayerScale.next(_scaleMode);
    showTransient(PlayerPanState(kind: PlayerTipKind.scale, text: '画面：${PlayerScale.label(_scaleMode)}'));
    notifyListeners();
  }

  void toggleMute() {
    final next = !muted;
    setMutedInternal(next);
    _controller?.setVolume(next ? 0.0 : 1.0);
    showTransient(PlayerPanState(kind: PlayerTipKind.volume, text: next ? '静音' : '音量 100%'));
  }

  void setDragPreview(Duration? preview) {
    _dragPreviewPosition = preview;
    _isDragging = preview != null;
    _showHud = true;
    watcher.clearHide();
    notifyListeners();
  }

  void setPanState(PlayerPanState state) {
    _panState = state;
    state.kind != PlayerTipKind.none ? watcher.clearHide() : armHideHud();
    notifyListeners();
  }

  void showTransient(PlayerPanState state) {
    _panState = state;
    watcher.clearHide();
    watcher.showTip(() {
      if (_panState.kind == state.kind) {
        _panState = const PlayerPanState(kind: PlayerTipKind.none);
        armHideHud();
        notifyListeners();
      }
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _initSessionId++;
    watcher.dispose();
    resetDeviceControl();
    final c = _controller;
    _controller = null;
    c?.removeListener(_onControllerUpdate);
    c?.dispose();
    super.dispose();
  }
}
