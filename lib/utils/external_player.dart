import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'playback_url.dart';

/// 调起系统/第三方播放器（MX Player、VLC 等）打开当前播放地址。
class ExternalPlayer {
  ExternalPlayer._();

  static String resolvePlayUrl(String rawLink) {
    return PlaybackUrl.prepareForPlayer(rawLink.trim());
  }

  /// 成功打开返回 true；无可用地址或无法调起返回 false。
  static Future<bool> open(String rawLink) async {
    final url = resolvePlayUrl(rawLink);
    if (url.isEmpty) return false;
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
