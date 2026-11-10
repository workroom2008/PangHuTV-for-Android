import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../api/http_client.dart';
import '../../utils/playback_url.dart';
import 'player_gesture_handler.dart';
import 'player_speed.dart';
import 'player_scale.dart';
import 'player_stall_watcher.dart';
import 'player_device_control_mixin.dart';

/// 播放器会话与播放状态控制器，管理生命周期、缓冲检测与控制指令
///
/// 播放内核为 media_kit(libmpv)，不是 video_player/ExoPlayer：
/// 后者只走硬解，竖屏超高分辨率（XP 源 1280x2278）超出设备 MediaCodec 上限即
/// 初始化失败，且插件不暴露 RenderersFactory 无法开启软解回退。
/// libmpv 在硬解失败时自动回落软解，1280x2278 可正常播放。
class PlayerPlaybackController extends ChangeNotifier with PlayerDeviceControlMixin {
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<void>? _completedSub;
  StreamSubscription<Tracks>? _tracksSub;

  /// 供渲染层使用：media_kit 的 VideoController。
  Player? get player => _player;
  VideoController? get videoController => _videoController;

  /// 当前视频宽高（libmpv 解码后回填，未就绪时为 0）。
  double get videoWidth => _player?.state.width?.toDouble() ?? 0;
  double get videoHeight => _player?.state.height?.toDouble() ?? 0;

  /// 兼容旧调用点：原先读 VideoPlayerController.value.size。
  Size get videoSize => Size(videoWidth, videoHeight);

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

  /// 可用音轨（不含 mpv 的 auto/no 伪轨）。
  List<AudioTrack> _audioTracks = const <AudioTrack>[];
  List<AudioTrack> get audioTracks => _audioTracks;

  /// 当前选中的音轨 id；空串表示未选中/未知。
  String _currentAudioId = '';
  String get currentAudioId => _currentAudioId;

  /// 是否已经做过一次"无音轨自动纠正"，避免用户主动选"关闭声音"后被强行改回。
  bool _audioTrackAutoFixed = false;

  /// 音轨变化时是否要通知 UI（避免 position 每 100ms 刷新都触发界面重建）。
  bool _audioListDirty = false;

  VoidCallback? onEnded;
  void Function(double current, double duration)? onProgress;
  VoidCallback? onStateChanged;
  /// 内置 ExoPlayer 硬解失败且已重试后，由 UI 调起第三方播放器；返回 true 表示已成功调起。
  Future<bool> Function(String rawVideoUrl)? onHardwareDecodeFailed;

  bool get isReady => _videoController != null && !_isOpening;

  void _safeSetWakelock(bool enable) => safeSetWakelock(enable);

  void _handleOpenTimeout(int sessionId) {
    if (sessionId != _initSessionId || !_isOpening) return;
    watcher.clearOpenWatch();
    _initSessionId++;
    _isOpening = false;
    _isBuffering = false;
    _playRequested = false;
    _errorText = '视频打开超时(${PlayerStallWatcher.openTimeoutMs ~/ 1000}s)';
    _disposePlayer();
    notifyListeners();
    onStateChanged?.call();
  }

  /// 释放当前播放内核与所有订阅。
  void _disposePlayer() {
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();
    _tracksSub?.cancel();
    _playingSub = null;
    _bufferingSub = null;
    _positionSub = null;
    _durationSub = null;
    _errorSub = null;
    _completedSub = null;
    _tracksSub = null;
    _audioTracks = const <AudioTrack>[];
    _currentAudioId = '';
    _audioTrackAutoFixed = false;
    _audioListDirty = false;
    final p = _player;
    _player = null;
    _videoController = null;
    if (p != null) {
      p.dispose().catchError((_) {});
    }
  }

  void _handleInitFailure(int sessionId, Object e, {bool externalPlayerOpened = false}) {
    if (sessionId != _initSessionId) return;
    _isOpening = false;
    _isBuffering = false;
    _isPlaying = false;
    _playRequested = false;
    final detail = '$e';
    if (_isDecoderInitError(e)) {
      _errorText = externalPlayerOpened
          ? '本机硬解失败，已调起其它播放器'
          : '当前设备解码失败，请点「其它播放器」或切换线路';
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

  /// 是否为解码/渲染层错误（而非网络/地址错误）。
  ///
  /// libmpv 的报错文案与 ExoPlayer 不同，这里同时保留旧关键字与 mpv 常见关键字，
  /// 便于上层仍能区分"解码失败"与"加载失败"。
  static bool _isDecoderInitError(Object e) {
    final s = e.toString();
    return s.contains('MediaCodec') ||
        s.contains('VideoError') ||
        s.contains('MediaCodecVideoRenderer') ||
        s.contains('Failed to open') ||
        s.contains('could not open codec') ||
        s.contains('No video decoder') ||
        s.contains('hwdec') ||
        s.contains('vo/gpu') ||
        s.contains('Decoder');
  }

  /// 设置 libmpv 原生属性（仅 NativePlayer 支持，Web 端无此能力）。
  ///
  /// 用 dynamic 调用而非深度 import `media_kit/src/...`：
  /// 后者是包私有实现，升级时路径可能变动，且触发 implementation_imports 告警。
  /// 这里只做尽力而为，失败静默忽略（不影响播放主流程）。
  static Future<void> _setMpvProperty(Player p, String key, String value) async {
    try {
      final platform = p.platform;
      if (platform == null) return;
      final dyn = platform as dynamic;
      await dyn.setProperty(key, value);
    } catch (_) {}
  }

  /// 测试环境（flutter test）没有 libmpv 原生库，创建 Player 会挂起并遗留定时器。
  /// 这里在测试时短路，让 widget 测试只验证 UI 状态机，不触碰真实播放内核。
  static bool get _isTestEnv {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  Future<void> initPlayer(
    String videoUrl, {
    double initialTime = 0,
    bool autoPlay = true,
    bool allowDecoderRetry = true,
  }) async {
    final sessionId = ++_initSessionId;
    watcher.dispose();

    _disposePlayer();

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

    if (_isTestEnv) {
      // 单元测试：不建真实内核，只把状态置为"已打开"，供 UI 断言使用。
      _isOpening = false;
      _isBuffering = false;
      _isPlaying = autoPlay;
      _playRequested = autoPlay;
      _errorText = '';
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

    Player? newPlayer;
    try {
      Map<String, String>? httpHeaders;
      if (PlaybackUrl.needsServerApiAuth(url)) {
        httpHeaders = await HttpClient.instance.mediaRequestHeaders();
      }

      newPlayer = Player();
      // 硬解优先、失败自动回落软解：libmpv 的 hwdec=auto-safe 在设备不支持
      // 该分辨率/编码时会自己退回软解，无需应用层重试（ExoPlayer 做不到这点）。
      // 硬解优先、失败自动回落软解：libmpv 的 hwdec=auto-safe 在设备不支持
      // 该分辨率/编码时会自己退回软解，无需应用层重试（ExoPlayer 做不到这点）。
      await _setMpvProperty(newPlayer, 'hwdec', 'auto-safe');
      // 服务端 /api/hls 在 client=tv 下会把分片重写成**相对路径**的代理地址
      // （/api/hls?source=...&token=...）。mpv 见播放列表里是相对引用就按
      // "unsafe playlist" 拒绝加载，报：
      //   Use the --load-unsafe-playlists option to load it anyway.
      // 这些播放列表来自我们自己的服务端，条目也是自己生成的分片代理，
      // 因此放开该限制是安全且必要的。
      await _setMpvProperty(newPlayer, 'load-unsafe-playlists', 'yes');
      // 网络抖动时多等一会，避免大分片被误判为加载失败。
      await _setMpvProperty(newPlayer, 'network-timeout', '30');
      final videoController = VideoController(newPlayer);

      if (sessionId != _initSessionId) {
        newPlayer.dispose().catchError((_) {});
        return;
      }
      _player = newPlayer;
      _videoController = videoController;
      _bindPlayerStreams(newPlayer);

      await newPlayer.open(
        Media(url, httpHeaders: httpHeaders),
        play: false,
      ).timeout(
        // 内核缺失/异常时 open 会永久挂起；超时后走失败分支，避免打开态卡死。
        const Duration(seconds: 30),
        onTimeout: () => throw StateError('播放内核打开超时'),
      );
      if (sessionId != _initSessionId) return;

      watcher.clearOpenWatch();

      if (initialTime > 0 && !_hasSeekedInitial) {
        _hasSeekedInitial = true;
        await newPlayer.seek(Duration(seconds: initialTime.toInt()));
      }

      await newPlayer.setRate(_currentSpeed);
      await newPlayer.setVolume(muted ? 0.0 : 1.0);
      if (autoPlay) {
        await newPlayer.play();
        safeSetWakelock(true);
      } else {
        await newPlayer.pause();
        safeSetWakelock(false);
      }

      if (sessionId == _initSessionId) {
        _isOpening = false;
        _isBuffering = false;
        _errorText = '';
        _totalDuration = newPlayer.state.duration;
        _isPlaying = autoPlay;
        _playRequested = autoPlay;
        armHideHud();
        notifyListeners();
        onStateChanged?.call();
      }
    } catch (e) {
      watcher.clearOpenWatch();
      if (_player == newPlayer) _disposePlayer();
      else newPlayer?.dispose().catchError((_) {});
      // libmpv 已内置软解回退，同一地址无需为解码失败重试；
      // 仅对非解码类错误（网络/初始化抖动）重试一次。
      if (allowDecoderRetry && sessionId == _initSessionId && !_isDecoderInitError(e)) {
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
      var externalOpened = false;
      if (sessionId == _initSessionId &&
          _isDecoderInitError(e) &&
          onHardwareDecodeFailed != null) {
        try {
          externalOpened = await onHardwareDecodeFailed!(videoUrl);
        } catch (_) {}
      }
      _handleInitFailure(sessionId, e, externalPlayerOpened: externalOpened);
    }
  }

  /// 订阅 libmpv 的状态流，把分散的 playing/buffering/position/duration
  /// 聚合成与旧版 VideoPlayerController 等价的单点更新逻辑。
  void _bindPlayerStreams(Player p) {
    _playingSub = p.stream.playing.listen((_) => _onPlayerUpdate());
    _bufferingSub = p.stream.buffering.listen((_) => _onPlayerUpdate());
    _positionSub = p.stream.position.listen((_) => _onPlayerUpdate());
    _durationSub = p.stream.duration.listen((_) => _onPlayerUpdate());
    _completedSub = p.stream.completed.listen((done) {
      if (done) _onPlayerUpdate();
    });
    _tracksSub = p.stream.tracks.listen(_handleTracks);
    _errorSub = p.stream.error.listen((msg) {
      if (msg.trim().isEmpty) return;
      _handleInitFailure(_initSessionId, msg);
    });
  }

  void _onPlayerUpdate() {
    final p = _player;
    if (p == null) return;
    final buffering = p.state.buffering;
    final pos = p.state.position;
    final dur = p.state.duration;
    final completed = dur.inSeconds > 0 && pos >= dur && !buffering;

    // 音轨就绪比首帧早：libmpv 一打开 http 播放列表就会发 ffmpeg 日志更新 track-list，
    // 用这个时机把 _isOpening 放掉，否则会白等满 30s 的打开超时。
    if (_audioTracks.isNotEmpty && _isOpening) _isOpening = false;
    if (_audioListDirty) {
      _audioListDirty = false;
      notifyListeners();
      onStateChanged?.call();
    }

    final playing = p.state.playing;

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

  /// 播放中播完落点或正常播放时，自动隐藏 HUD。
  void armHideHud() {
    watcher.armHide(() {
      if (_isPlaying && !_isCompleted && _panState.kind == PlayerTipKind.none && !_isDragging) {
        _showHud = false;
        notifyListeners();
      }
    }, canHide: _isPlaying && !_isCompleted && _errorText.isEmpty && !_isDragging);
  }

  /// 音轨列表更新（含 mpv 的 auto/no 伪轨，需过滤）。
  void _handleTracks(Tracks tracks) {
    final real = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList(growable: false);
    final selected = _player?.state.track.audio.id ?? '';
    final currentId = (selected == 'auto' || selected == 'no') ? '' : selected;

    final changed = real.length != _audioTracks.length ||
        (real.isNotEmpty && _audioTracks.isNotEmpty && real.first.id != _audioTracks.first.id) ||
        currentId != _currentAudioId;
    _audioTracks = real;
    _currentAudioId = currentId;
    if (changed) _audioListDirty = true;

    // 兜底 C：mpv 落到 aid=no（无音轨选中）时自动纠正一次。
    // 只纠正一次：用户之后主动选"关闭"不再被强行改回。
    if (!_audioTrackAutoFixed && currentId.isEmpty && real.length == 1) {
      _audioTrackAutoFixed = true;
      selectAudioTrack(real.first.id);
    }
  }

  /// 手动切换音轨（弹层选择）。id 为空表示不动作。
  Future<void> selectAudioTrack(String id) async {
    final p = _player;
    if (p == null || id.trim().isEmpty) return;
    AudioTrack? target;
    for (final t in _audioTracks) {
      if (t.id == id) {
        target = t;
        break;
      }
    }
    if (target == null) return;
    try {
      await p.setAudioTrack(target);
      _currentAudioId = target.id;
      showTransient(PlayerPanState(kind: PlayerTipKind.volume, text: '音轨：${audioTrackLabel(target)}'));
      notifyListeners();
    } catch (_) {}
  }

  /// 音轨显示名：优先标题，其次语言，最后「音轨 N」。
  String audioTrackLabel(AudioTrack t) {
    final title = (t.title ?? '').trim();
    if (title.isNotEmpty) return title;
    final lang = (t.language ?? '').trim();
    if (lang.isNotEmpty && lang != 'und') return lang;
    final idx = _audioTracks.indexOf(t);
    return idx >= 0 ? '音轨 ${idx + 1}' : '音轨';
  }

  void toggleHud() {
    if (_panState.kind != PlayerTipKind.none) return;
    _showHud = !_showHud;
    _showHud ? armHideHud() : watcher.clearHide();
    notifyListeners();
  }

  void togglePlay() {
    final c = _player;
    if (c == null) return;
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
    if (_isPlaying || c.state.playing) {
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
    final c = _player;
    if (c == null) return;
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
    final c = _player;
    if (c == null) return;
    _playRequested = false;
    c.pause();
    _safeSetWakelock(false);
    _isPlaying = false;
    _isBuffering = false;
    watcher.clearHide();
    notifyListeners();
  }

  /// 释放内置播放器会话（第三方播放器接管或换源前）。
  void handoffToExternalPlayer() {
    parkForCast();
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
    _disposePlayer();
    notifyListeners();
  }

  void pauseLocal() {
    _player?.pause().catchError((_) {});
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
      _player?.play().catchError((_) {});
      _safeSetWakelock(true);
      _isPlaying = true;
    } else {
      _player?.pause().catchError((_) {});
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
    _disposePlayer();
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
    final c = _player;
    if (c == null) return;
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
      await c.seek(target);
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
    _player?.setRate(speed);
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
    _player?.setVolume(next ? 0.0 : 1.0);
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
    _disposePlayer();
    super.dispose();
  }
}
