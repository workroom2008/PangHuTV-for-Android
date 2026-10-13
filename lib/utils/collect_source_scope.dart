import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 前台采集源选择（与 Web `panghu_source` / ?source= 对齐），首页与每日更新共用。
class CollectSourceScope extends ChangeNotifier {
  CollectSourceScope._();
  static final CollectSourceScope instance = CollectSourceScope._();

  static const _prefKey = 'panghu_source';

  String _activeId = '';
  bool _loaded = false;

  String get activeId => _activeId;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final pref = await SharedPreferences.getInstance();
    _activeId = pref.getString(_prefKey)?.trim() ?? '';
    _loaded = true;
  }

  Future<void> pick(String id) async {
    final next = id.trim();
    if (_activeId == next) return;
    _activeId = next;
    notifyListeners();
    final pref = await SharedPreferences.getInstance();
    if (next.isEmpty) {
      await pref.remove(_prefKey);
    } else {
      await pref.setString(_prefKey, next);
    }
  }

  void syncFromCatalog(List<String> validIds) {
    if (_activeId.isEmpty) return;
    if (validIds.contains(_activeId)) return;
    _activeId = '';
    notifyListeners();
    SharedPreferences.getInstance().then((pref) => pref.remove(_prefKey));
  }
}
