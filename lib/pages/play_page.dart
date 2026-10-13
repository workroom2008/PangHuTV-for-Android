import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../api/film_api.dart';
import '../api/http_client.dart';
import '../utils/history_manager.dart';
import '../utils/app_orientation.dart';
import '../utils/breakpoint.dart';
import '../utils/play_resume.dart';
import '../utils/server_config_manager.dart';
import '../utils/source_guard.dart';
import '../utils/format_util.dart';
import '../utils/split_cutout_insets.dart';
import '../utils/app_settings_manager.dart';
import '../components/player/video_player_widget.dart';
import '../components/player/live_play_body.dart';
import '../components/loading_view.dart';
import '../components/empty_state.dart';
import '../services/pip_manager.dart';

/// 影片播放主页面
class PlayPage extends StatefulWidget {
  final String id;
  final String sourceId;
  final int? episodeIndex;
  final double? currentTime;

  const PlayPage({
    super.key,
    required this.id,
    this.sourceId = '',
    this.episodeIndex,
    this.currentTime,
  });

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> with WidgetsBindingObserver {
  late String _filmId;
  bool _loading = true;
  String _errorText = '';
  String _name = '';
  String _picture = '';
  String _subTitle = '';
  String _actor = '';
  String _plot = '';
  MovieDescriptor? _descriptor;
  List<PlaySource> _sources = [];
  String _playingSourceId = '';
  String _viewingSourceId = '';
  int _episodeIndex = 0;
  String _playUrl = '';
  int _playToken = 0;
  String _playTitle = '';
  double _initialTime = 0;
  List<MovieBasicInfo> _related = [];
  bool _relateLoading = false;
  int _activeTab = 0;
  bool _playerFull = false;
  final GlobalKey _videoKey = GlobalKey();
  String _sourceName = '默认源';
  double _lastCurrentTime = 0;
  double _lastDuration = 0;
  bool _persistEnabled = true;
  bool _isPipActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PipManager.instance.addListener(_onPipChanged);
    _isPipActive = PipManager.instance.isPipActive;
    _filmId = widget.id;
    _episodeIndex = widget.episodeIndex ?? 0;
    _initialTime = widget.currentTime ?? 0;
    _lastCurrentTime = _initialTime;
    SourceGuard.onReconnect(_onReconnect);

    _initPlay();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PipManager.instance.removeListener(_onPipChanged);
    _persistHistory(_lastCurrentTime, _lastDuration);
    try {
      SystemChrome.setPreferredOrientations(kAutoRotationOrientations);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    SourceGuard.offReconnect(_onReconnect);
    super.dispose();
  }

  void _onPipChanged(bool active) {
    if (mounted && _isPipActive != active) {
      setState(() => _isPipActive = active);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _lastCurrentTime > 0) {
      _persistHistory(_lastCurrentTime, _lastDuration);
    }
  }

  void _onReconnect() {
    _persistEnabled = false;
    _loadPlay(_playingSourceId);
    _loadRelate();
  }

  Future<void> _initPlay() async {
    var targetSourceId = widget.sourceId;
    int targetEpIndex = widget.episodeIndex ?? -1;
    double targetTime = widget.currentTime ?? -1;

    if (_filmId.isNotEmpty) {
      try {
        final prev = await HistoryManager.find(_filmId);
        if (prev != null) {
          if (targetSourceId.isEmpty && prev.sourceId.isNotEmpty) {
            targetSourceId = prev.sourceId;
          }
          if (targetEpIndex < 0 && prev.episodeIndex >= 0) {
            targetEpIndex = prev.episodeIndex;
          }
          if (targetTime < 0) {
            final ended = prev.duration > 0 && prev.currentTime >= prev.duration - 3;
            targetTime = ended ? 0 : prev.currentTime;
          }
          _lastDuration = prev.duration;
        }
      } catch (_) {}
    }

    _episodeIndex = targetEpIndex >= 0 ? targetEpIndex : 0;
    _initialTime = targetTime >= 0 ? targetTime : 0;
    _lastCurrentTime = _initialTime;
    _loadPlay(targetSourceId);
    _loadRelate();
  }

  Future<void> _loadPlay(String sourceId) async {
    if (_filmId.isEmpty) {
      setState(() {
        _errorText = '未找到影片参数';
        _loading = false;
      });
      return;
    }

    if (_name.isEmpty) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final info = await FilmApi.getPlayInfo(_filmId, playFrom: sourceId, episode: _episodeIndex);
      if (!mounted) return;

      final detail = info.detail;
      if (_name.isEmpty) {
        final openedSource = sourceId.isNotEmpty ? sourceId : info.currentPlayFrom;
        HttpClient.instance.trackView(
          'play',
          _filmId,
          'PlayPage',
          '',
          detail.descriptor.cName,
          detail.name,
          openedSource,
        );
      }
      setState(() {
        _name = detail.name;
        _picture = detail.picture;
        _descriptor = detail.descriptor;
        _subTitle = detail.descriptor.subTitle;
        _actor = detail.descriptor.actor;
        _plot = detail.descriptor.content.isNotEmpty ? detail.descriptor.content : detail.descriptor.blurb;
        _sources = detail.list;
        _playingSourceId = info.currentPlayFrom.isNotEmpty
            ? info.currentPlayFrom
            : (detail.list.isNotEmpty ? detail.list.first.id : '');
        _viewingSourceId = _playingSourceId;
        _episodeIndex = info.currentEpisode;
        _playUrl = info.current.link;
        _playTitle = '${detail.name} · ${info.current.episode}';
        _sourceName = _findSource(_playingSourceId)?.name ?? '默认源';
        _errorText = _playUrl.trim().isEmpty ? '暂无可用播放地址，请切换线路或稍后重试' : '';
        _loading = false;
        _persistEnabled = true;
      });
      _persistHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_name.isEmpty) {
          _errorText = '$e';
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      });
    }
  }

  Future<void> _loadRelate() async {
    if (_filmId.isEmpty) return;
    setState(() {
      _relateLoading = true;
    });
    try {
      final list = await FilmApi.getRelate(_filmId);
      if (!mounted) return;
      setState(() {
        _related = list;
        _relateLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _related = [];
        _relateLoading = false;
      });
    }
  }

  PlaySource? _findSource(String id) {
    for (final s in _sources) {
      if (s.id == id) return s;
    }
    return _sources.isNotEmpty ? _sources.first : null;
  }

  void _selectEpisode(String sourceId, int index) {
    if (_playingSourceId == sourceId && _episodeIndex == index && _playUrl.isNotEmpty) {
      return;
    }
    final source = _findSource(sourceId);
    if (source == null || index < 0 || index >= source.linkList.length) return;
    final ep = source.linkList[index];

    setState(() {
      _playingSourceId = sourceId;
      _viewingSourceId = sourceId;
      _episodeIndex = index;
      _initialTime = 0;
      _lastCurrentTime = 0;
      _lastDuration = 0;
      _playUrl = ep.link;
      _playToken++;
      _playTitle = '$_name · ${ep.episode}';
      _sourceName = source.name;
    });
    _persistHistory(0, 0);
  }

  bool _hasNext() {
    final s = _findSource(_playingSourceId);
    return s != null && _episodeIndex < s.linkList.length - 1;
  }

  bool _hasPrev() => _episodeIndex > 0 && _findSource(_playingSourceId) != null;

  void _playPrev() {
    if (!_hasPrev()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已经是第一集了')));
      return;
    }
    _selectEpisode(_playingSourceId, _episodeIndex - 1);
  }

  void _playNext() {
    if (!_hasNext()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已经是最后一集了')));
      return;
    }
    _selectEpisode(_playingSourceId, _episodeIndex + 1);
  }

  void _persistHistory([double? currentTime, double? duration]) {
    if (!_persistEnabled || _filmId.isEmpty || _name.isEmpty) return;
    if (ServerConfigManager.instance.storageScope().isEmpty) return;

    final source = _findSource(_playingSourceId);
    final sourceName = source != null ? source.name : _sourceName;
    final fallback = MovieUrlInfo(episode: _playTitle, link: _playUrl);
    final ep = (source != null && source.linkList.length > _episodeIndex)
        ? source.linkList[_episodeIndex]
        : fallback;

    HistoryManager.find(_filmId).then((prev) {
      final cur = currentTime ?? (prev?.currentTime ?? 0);
      final dur = duration ?? (prev?.duration ?? 0);
      HistoryManager.save(HistoryItem(
        id: _filmId,
        name: _name,
        picture: _picture,
        sourceId: _playingSourceId,
        sourceName: sourceName,
        episodeIndex: _episodeIndex,
        episode: ep.episode,
        currentTime: cur,
        duration: dur,
        timeStamp: DateTime.now().millisecondsSinceEpoch,
      ));
    });
  }

  Future<void> _openRelated(MovieBasicInfo film) async {
    final id = FormatUtil.filmId(film);
    if (id.isEmpty || id == _filmId) return;

    _filmId = id;
    final resume = await PlayResume.fromHistory(_filmId);
    if (!mounted) return;
    setState(() {
      _name = '';
      _sources = [];
      _playUrl = '';
      _loading = true;
      _episodeIndex = resume.episodeIndex;
      _initialTime = resume.currentTime;
      _lastCurrentTime = resume.currentTime;
      _lastDuration = resume.duration;
      _activeTab = 0;
    });
    _loadPlay(resume.sourceId);
    _loadRelate();
  }

  void _setFullscreen(bool full, {bool isPortrait = false}) {
    if (_playerFull == full) return;
    setState(() => _playerFull = full);
    try {
      if (full) {
        // 全量对齐 OHOS：竖屏视频（短剧等）全屏必须按竖屏方向（portraitUp）播放；
        // 横屏视频必须按横屏方向（landscapeLeft / landscapeRight）播放。
        SystemChrome.setPreferredOrientations(isPortrait
            ? [DeviceOrientation.portraitUp]
            : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setPreferredOrientations(kAutoRotationOrientations);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (_) {}
  }

  Widget _buildVideoPlayer({
    required bool isFull,
    bool edgeHud = false,
    double? overrideLeftInset,
  }) {
    // 对齐 OHOS hud inset：全屏/分屏时把安全区传给播放器控件，竖屏时归零（视频已在 SafeArea 内）。
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final useInset = isFull || edgeHud;
    return VideoPlayerWidget(
      key: _videoKey,
      videoUrl: _playUrl,
      reloadToken: _playToken,
      title: _playTitle,
      poster: ServerConfigManager.instance.resolveMediaUrl(_picture),
      initialTime: _initialTime,
      showBack: true,
      isFull: isFull,
      edgeHud: edgeHud,
      topInset: useInset ? viewPadding.top : 0,
      bottomInset: useInset ? viewPadding.bottom : 0,
      leftInset: overrideLeftInset ?? (useInset ? viewPadding.left : 0),
      rightInset: isFull
          ? viewPadding.right
          : (edgeHud ? AppTheme.safeEdge : 0),
      hasPrev: _hasPrev(),
      hasNext: _hasNext(),
      onBack: () => _playerFull ? _setFullscreen(false) : Navigator.pop(context),
      onEnded: () {
        if (AppSettingsManager.instance.autoPlayNext && _hasNext()) _playNext();
      },
      onPrev: _playPrev,
      onNext: _playNext,
      onFullscreenChange: _setFullscreen,
      onProgress: (cur, dur) {
        _lastCurrentTime = cur;
        _lastDuration = dur;
        _persistHistory(cur, dur);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // 对齐 OHOS `isWideScreen()`：横屏宽屏（宽>=600 且宽>高）时进入分屏，而非全屏。
    final split = !_playerFull && size.width >= Breakpoint.md && size.width > size.height;
    final isFullMode = _playerFull;

    return PopScope(
      canPop: !_isPipActive && !isFullMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isFullMode) {
          _setFullscreen(false);
        }
      },
      child: Scaffold(
        backgroundColor: (_isPipActive || isFullMode) ? Colors.black : AppTheme.bg,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          top: !_isPipActive && !isFullMode && !split,
          bottom: !_isPipActive && !isFullMode && !split,
          left: !_isPipActive && !isFullMode && !split,
          right: !_isPipActive && !isFullMode && !split,
          child: _buildPlayBody(isFullMode: isFullMode, split: split),
        ),
      ),
    );
  }

  Widget _buildPlayBody({required bool isFullMode, required bool split}) {
    // 对齐 OHOS 顶层 build：先按 loading/error 守卫，避免 playUrl 为空时渲染播放器报错。
    if (_loading && _sources.isEmpty) {
      return const LoadingView(label: '正在打开播放页');
    }
    if (_errorText.isNotEmpty && _sources.isEmpty) {
      return EmptyState(
        title: '当前内容无法播放',
        subtitle: _errorText,
        icon: Icons.play_disabled_rounded,
      );
    }

    if (_isPipActive) {
      // 画中画模式：整屏独占渲染播放器画面，其它详情与选集等 UI 彻底隐藏，避免在系统浮窗中呈现缩略图
      return SizedBox.expand(
        child: _buildVideoPlayer(isFull: false),
      );
    }

    if (isFullMode) {
      return SizedBox.expand(
        child: _buildVideoPlayer(isFull: true),
      );
    }

    return LivePlayBody(
      isSplit: split,
      playerWidget: _buildVideoPlayer(
        isFull: false,
        edgeHud: split,
        overrideLeftInset: split ? SplitCutoutInsets.resolve(MediaQuery.viewPaddingOf(context), padding: MediaQuery.paddingOf(context), displayFeatures: MediaQuery.displayFeaturesOf(context), size: MediaQuery.sizeOf(context)).left : null,
      ),
      activeTab: _activeTab,
      onTabChange: (tab) => setState(() => _activeTab = tab),
      filmId: _filmId,
      picture: _picture,
      name: _name,
      subTitle: _subTitle,
      actor: _actor,
      plot: _plot,
      descriptor: _descriptor,
      sources: _sources,
      playingSourceId: _playingSourceId,
      viewingSourceId: _viewingSourceId,
      episodeIndex: _episodeIndex,
      onViewSource: (id) => setState(() => _viewingSourceId = id),
      onSelectEpisode: (sourceId, index) => _selectEpisode(sourceId, index),
      relateLoading: _relateLoading,
      related: _related,
      onOpenRelated: _openRelated,
      sourceName: '',
    );
  }
}
