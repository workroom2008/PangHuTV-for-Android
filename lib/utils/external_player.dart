import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/external_player_app.dart';
import 'app_settings_manager.dart';
import 'playback_url.dart';

/// 调起系统/第三方播放器（MX Player、VLC 等）打开当前播放地址。
class ExternalPlayer {
  ExternalPlayer._();

  static const MethodChannel _channel = MethodChannel('com.ecohub.ecohub/external_player');

  static String resolvePlayUrl(String rawLink) {
    return PlaybackUrl.prepareForPlayer(rawLink.trim());
  }

  /// 枚举本机可处理 http(s) 视频链路的应用（仅 Android 有效）。
  static Future<List<ExternalPlayerApp>> listInstalled() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('listPlayers');
      if (raw == null) return const [];
      return raw.map((e) => ExternalPlayerApp.fromMap(Map<dynamic, dynamic>.from(e as Map))).toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ExternalPlayer.listInstalled failed: $e\n$st');
      }
      return const [];
    }
  }

  /// 成功打开返回 true；无可用地址或无法调起返回 false。
  static Future<bool> open(String rawLink, {String? packageName}) async {
    final url = resolvePlayUrl(rawLink);
    if (url.isEmpty) return false;

    final pkg = packageName ?? AppSettingsManager.instance.externalPlayerPackage;

    if (Platform.isAndroid) {
      try {
        final ok = await _channel.invokeMethod<bool>('open', {
          'url': url,
          'package': pkg,
        });
        if (ok == true) return true;
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('ExternalPlayer channel open failed: $e\n$st');
        }
      }
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;

    final modes = <LaunchMode>[
      LaunchMode.externalNonBrowserApplication,
      LaunchMode.externalApplication,
    ];
    for (final mode in modes) {
      try {
        final ok = await launchUrl(uri, mode: mode);
        if (ok) return true;
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('ExternalPlayer launch failed ($mode): $e\n$st');
        }
      }
    }
    return false;
  }
}
