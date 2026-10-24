import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'collect_source_scope.dart';
import 'play_navigation.dart';

/// 路由封装，对齐 OHOS `NavUtil`
class NavUtil {
  static void openFavorite(BuildContext context) {
    Navigator.pushNamed(context, '/favorite');
  }

  static void openHistory(BuildContext context) {
    Navigator.pushNamed(context, '/history');
  }

  static void openTip(BuildContext context) {
    Navigator.pushNamed(context, '/tip');
  }

  static void openSettings(BuildContext context) {
    Navigator.pushNamed(context, '/settings');
  }

  static void openAbout(BuildContext context) {
    Navigator.pushNamed(context, '/about');
  }

  static Future<dynamic> openPlay(
    BuildContext context,
    String id, {
    String sourceId = '',
    String sourceMid = '',
    int? episodeIndex,
    double? currentTime,
    String title = '',
  }) {
    if (PlayNavigation.isLocalFilmId(id)) {
      // 未显式传源时兜底当前采集源 scope，避免全源冷启动按默认源解析错线路
      var filmSourceId = sourceId.trim();
      if (filmSourceId.isEmpty) {
        filmSourceId = CollectSourceScope.instance.activeId.trim();
      }
      final params = <String, dynamic>{'id': id};
      if (filmSourceId.isNotEmpty) params['sourceId'] = filmSourceId;
      if (episodeIndex != null && episodeIndex >= 0) {
        params['episodeIndex'] = '$episodeIndex';
      }
      if (currentTime != null && currentTime >= 0) {
        params['currentTime'] = '$currentTime';
      }
      return Navigator.pushNamed(context, '/play', arguments: params);
    }

    var liveSource = sourceId;
    var liveSid = sourceMid;
    final split = PlayNavigation.splitLivePlayId(id);
    if (split != null) {
      liveSource = split.sourceId;
      liveSid = split.sid;
    }
    if (liveSource.isEmpty || liveSid.isEmpty) {
      return Future<void>.value();
    }
    final params = <String, dynamic>{
      'sourceId': liveSource,
      'sourceMid': liveSid,
      if (title.isNotEmpty) 'title': title,
    };
    if (episodeIndex != null && episodeIndex >= 0) {
      params['episodeIndex'] = '$episodeIndex';
    }
    if (currentTime != null && currentTime >= 0) {
      params['currentTime'] = '$currentTime';
    }
    return Navigator.pushNamed(context, '/play/live', arguments: params);
  }

  static void openFilter(
    BuildContext context,
    String pid, {
    String category = '',
    String sort = '',
  }) {
    Navigator.pushNamed(
      context,
      '/filter',
      arguments: {'Pid': pid, 'Category': category, 'Sort': sort},
    );
  }

  static void openSearch(BuildContext context, [String keyword = '']) {
    if (keyword.isEmpty) {
      Navigator.pushNamed(context, '/search');
      return;
    }
    Navigator.pushNamed(context, '/search', arguments: {'keyword': keyword});
  }

  static void openCustomPlayer(BuildContext context, [String url = '']) {
    if (url.isEmpty) {
      Navigator.pushNamed(context, '/custom_player');
      return;
    }
    Navigator.pushNamed(context, '/custom_player', arguments: {'url': url});
  }

  static Future<void> openBrowser(String url) async {
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  static String param(Map<String, dynamic>? params, String key, [String fallback = '']) {
    if (params == null) return fallback;
    final value = params[key];
    if (value == null) return fallback;
    return '$value';
  }
}
