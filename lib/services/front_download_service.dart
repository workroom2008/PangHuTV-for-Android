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
}
