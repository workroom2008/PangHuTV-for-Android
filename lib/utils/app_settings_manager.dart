import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用全局设置管理器，对齐 OHOS `AppSettingsManager.ets`
class AppSettingsManager {
  static const String keyAutoPlayNext = 'setting_auto_play_next';
  static const String keyPipAutoStart = 'setting_pip_auto_start';
  static const String keyPreferExternalPlayer = 'setting_prefer_external_player';
  static const String keyExternalPlayerPackage = 'setting_external_player_package';
  static const String keyExternalPlayerLabel = 'setting_external_player_label';
  static const MethodChannel _settingsChannel = MethodChannel('com.ecohub.ecohub/settings');

  static final AppSettingsManager instance = AppSettingsManager._();
  AppSettingsManager._();

  final ValueNotifier<bool> autoPlayNextNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> pipAutoStartNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> preferExternalPlayerNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> externalPlayerPackageNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> externalPlayerLabelNotifier = ValueNotifier<String>('');

  bool get autoPlayNext => autoPlayNextNotifier.value;
  bool get pipAutoStart => pipAutoStartNotifier.value;
  bool get preferExternalPlayer => preferExternalPlayerNotifier.value;
  String get externalPlayerPackage => externalPlayerPackageNotifier.value.trim();
  String get externalPlayerLabel => externalPlayerLabelNotifier.value.trim();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    autoPlayNextNotifier.value = prefs.getBool(keyAutoPlayNext) ?? true;
    pipAutoStartNotifier.value = prefs.getBool(keyPipAutoStart) ?? true;
    preferExternalPlayerNotifier.value = prefs.getBool(keyPreferExternalPlayer) ?? false;
    externalPlayerPackageNotifier.value = prefs.getString(keyExternalPlayerPackage) ?? '';
    externalPlayerLabelNotifier.value = prefs.getString(keyExternalPlayerLabel) ?? '';
  }

  Future<void> setAutoPlayNext(bool value) async {
    autoPlayNextNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyAutoPlayNext, value);
  }

  Future<void> setPipAutoStart(bool value) async {
    pipAutoStartNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyPipAutoStart, value);
  }

  Future<void> setPreferExternalPlayer(bool value) async {
    preferExternalPlayerNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyPreferExternalPlayer, value);
  }

  Future<void> setExternalPlayer({required String packageName, required String label}) async {
    final pkg = packageName.trim();
    final name = label.trim();
    externalPlayerPackageNotifier.value = pkg;
    externalPlayerLabelNotifier.value = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyExternalPlayerPackage, pkg);
    await prefs.setString(keyExternalPlayerLabel, name);
  }

  String externalPlayerSummary() {
    if (externalPlayerLabel.isNotEmpty) return externalPlayerLabel;
    if (externalPlayerPackage.isNotEmpty) return externalPlayerPackage;
    return '系统选择器';
  }

  Future<String> getCacheSize() async {
    try {
      final size = await _settingsChannel.invokeMethod<String>('getCacheSize');
      return size ?? '0.0 MB';
    } catch (_) {
      return '0.0 MB';
    }
  }

  Future<void> clearCache() async {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await _settingsChannel.invokeMethod('clearCache');
    } catch (_) {}
  }
}
