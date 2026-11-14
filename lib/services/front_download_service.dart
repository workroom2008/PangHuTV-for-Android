import 'package:flutter/foundation.dart';
import '../api/download_api.dart';
import '../models/download_models.dart';

/// 前台下载总开关（与 Web `useFrontDownloadEnabled` 对齐）。
class FrontDownloadService extends ChangeNotifier {
  static final FrontDownloadService instance = FrontDownloadService._();
  FrontDownloadService._();

  bool _enabled = false;
  bool _loaded = false;

  bool get enabled => _enabled;
  bool get loaded => _loaded;

  Future<void> refresh() async {
    _enabled = await DownloadApi.fetchEnabled();
    _loaded = true;
    notifyListeners();
  }

  void reset() {
    _enabled = false;
    _loaded = false;
    notifyListeners();
  }

  Future<bool> submitEpisode(String mid, int episode, {String sourceId = ''}) async {
    if (!isDownloadableFilmId(mid)) return false;
    final res = await DownloadApi.submitTask(
      mid: mid,
      episode: episode,
      sourceId: sourceId,
    );
    return res.code == 0;
  }

  /// 多集内容全集下载：服务端按播放列表集数展开并逐集判重
  /// （2048短剧/91AI短剧/XPorn AI短剧及任意源剧集形态通用；单集片等价于 episode=1）。
  Future<bool> submitAllEpisodes(String mid, {String sourceId = ''}) async {
    if (!isDownloadableFilmId(mid)) return false;
    final res = await DownloadApi.submitTask(
      mid: mid,
      episode: 1,
      allEpisodes: true,
      sourceId: sourceId,
    );
    return res.code == 0;
  }
}
