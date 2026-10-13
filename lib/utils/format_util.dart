import 'package:flutter/material.dart';
import '../models/film_models.dart';
import 'play_navigation.dart';
import 'playback_url.dart';

/// 统一格式化工具类
class FormatUtil {
  static String text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final s = '$value'.trim();
    if (s.isEmpty || s == '0') return fallback;
    return s;
  }

  static String year(dynamic value) {
    final s = text(value);
    return s.length >= 4 ? s.substring(0, 4) : s;
  }

  static String remarks(dynamic value) {
    final t = text(value);
    if (t.isEmpty) return '';
    if (t.startsWith('更新至') || t.startsWith('全') || t.endsWith('全') || t == '完结') {
      return t;
    }
    final epMatch = RegExp(r'^第\s*(\d+)\s*集$').firstMatch(t);
    if (epMatch != null) return '更新至${epMatch.group(1)}集';
    final numMatch = RegExp(r'^(\d+)\s*集$').firstMatch(t);
    if (numMatch != null) return '更新至${numMatch.group(1)}集';
    final updateMatch = RegExp(r'^更新第?\s*(\d+)\s*集$').firstMatch(t);
    if (updateMatch != null) return '更新至${updateMatch.group(1)}集';
    return t;
  }

  /// 深度清洗 HTML 剧情简介文本
  static String cleanPlot(String raw) {
    if (raw.isEmpty) return '';
    final text = raw
        .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<\s*/(p|div|li|tr|h[1-6])\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'&emsp;|&ensp;|&thinsp;|&nbsp;|&#160;|&#12288;|\u3000'), ' ')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r"&apos;|&#39;"), "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');

    final lines = text.split('\n');
    final cleanedLines = <String>[];
    for (final line in lines) {
      final trimmed = line.replaceAll(RegExp(r'^[\s\u3000\u00A0\u2000-\u200B]+|[\s\u3000\u00A0\u2000-\u200B]+$'), '');
      if (trimmed.isNotEmpty) {
        cleanedLines.add(trimmed);
      }
    }
    return cleanedLines.join('\n\n');
  }

  static String poster(MovieBasicInfo film) {
    String raw = '';
    if (film.picture.isNotEmpty) {
      raw = film.picture;
    } else if (film.poster.isNotEmpty) {
      raw = film.poster;
    } else if (film.pictureSlide.isNotEmpty) {
      raw = film.pictureSlide;
    }
    return PlaybackUrl.prepareMediaUrl(raw);
  }

  static String bannerPoster(BannerItem item) {
    String raw = '';
    if (item.poster.isNotEmpty) {
      raw = item.poster;
    } else if (item.picture.isNotEmpty) {
      raw = item.picture;
    } else if (item.pictureSlide.isNotEmpty) {
      raw = item.pictureSlide;
    }
    return PlaybackUrl.prepareMediaUrl(raw);
  }

  static String bannerBackdrop(BannerItem item) {
    String raw = '';
    if (item.pictureSlide.isNotEmpty) {
      raw = item.pictureSlide;
    } else if (item.picture.isNotEmpty) {
      raw = item.picture;
    } else if (item.poster.isNotEmpty) {
      raw = item.poster;
    }
    return PlaybackUrl.prepareMediaUrl(raw);
  }

  static String filmId(MovieBasicInfo film) {
    if (film.id > 0) return '${film.id}';
    final midText = text(film.mid);
    if (midText.contains(':')) return midText;
    final sid = film.sourceMid > 0 ? '${film.sourceMid}' : midText;
    if (film.sourceId.isNotEmpty && sid.isNotEmpty && sid != '0') {
      return PlayNavigation.livePlayHistoryId(film.sourceId, sid);
    }
    return sid;
  }

  /// 根据图片 URL 动态生成防盗链与兼容性请求头（如 Bilibili、豆瓣等）
  static Map<String, String> imageHeaders(String url) {
    url = PlaybackUrl.prepareMediaUrl(url);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return const {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      };
    }

    final host = uri.host.toLowerCase();
    String? referer;

    if (host.contains('hdslb.com') || host.contains('bilibili.com') || host.contains('bilivideo.com')) {
      referer = 'https://www.bilibili.com/';
    } else if (host.contains('doubanio.com') || host.contains('douban.com')) {
      referer = 'https://movie.douban.com/';
    } else if (host.contains('sinaimg.cn') || host.contains('weibo.com')) {
      referer = 'https://weibo.com/';
    } else if (host.contains('xhscdn.com') || host.contains('xiaohongshu.com')) {
      referer = 'https://www.xiaohongshu.com/';
    } else if (host.contains('iqiyipic.com') || host.contains('iqiyi.com')) {
      referer = 'https://www.iqiyi.com/';
    } else if (host.contains('qq.com') || host.contains('qpic.cn')) {
      referer = 'https://v.qq.com/';
    } else if (host.contains('youku.com') || host.contains('ykimg.com')) {
      referer = 'https://www.youku.com/';
    } else if (host.contains('mgtv.com')) {
      referer = 'https://www.mgtv.com/';
    }

    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
    if (referer != null) {
      headers['Referer'] = referer;
    }
    return headers;
  }

  static String pad2(int value) {
    return value < 10 ? '0$value' : '$value';
  }

  static String duration(double seconds) {
    final total = seconds <= 0 ? 0 : seconds.floor();
    final hour = total ~/ 3600;
    final minute = (total % 3600) ~/ 60;
    final second = total % 60;
    if (hour > 0) {
      return '${pad2(hour)}:${pad2(minute)}:${pad2(second)}';
    }
    return '${pad2(minute)}:${pad2(second)}';
  }

  static String progress(double current, double duration) {
    if (current <= 0) return '未观看';
    if (duration <= 0) return '观看至 ${FormatUtil.duration(current)}';
    if (current >= duration - 2) return '已看完';
    final percent = ((current / duration) * 100).floor().clamp(1, 99);
    return '观看至 ${FormatUtil.duration(current)} ($percent%)';
  }

  static String dateTime(int stamp) {
    if (stamp <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(stamp);
    return '${dt.year}-${pad2(dt.month)}-${pad2(dt.day)} ${pad2(dt.hour)}:${pad2(dt.minute)}';
  }

  static String joinMeta(List<String> parts) {
    final items = <String>[];
    for (final p in parts) {
      final t = p.trim();
      if (t.isNotEmpty) items.add(t);
    }
    return items.join(' · ');
  }

  static const List<Color> _tagBg = [
    Color(0x47FA8C16), // rgba(250, 140, 22, 0.28)
    Color(0x4760A5FA), // rgba(96, 165, 250, 0.28)
    Color(0x4734D399), // rgba(52, 211, 153, 0.28)
    Color(0x47A78BFA), // rgba(167, 139, 250, 0.28)
    Color(0x47FB7185), // rgba(251, 113, 133, 0.28)
    Color(0x4722D3EE), // rgba(34, 211, 238, 0.28)
    Color(0x47FACC15), // rgba(250, 204, 21, 0.28)
    Color(0x47818CF8), // rgba(129, 140, 248, 0.28)
  ];

  static const List<Color> _tagBorder = [
    Color(0x7AFA8C16), // rgba(250, 140, 22, 0.48)
    Color(0x7A60A5FA), // rgba(96, 165, 250, 0.48)
    Color(0x7A34D399), // rgba(52, 211, 153, 0.48)
    Color(0x7AA78BFA), // rgba(167, 139, 250, 0.48)
    Color(0x7AFB7185), // rgba(251, 113, 133, 0.48)
    Color(0x7A22D3EE), // rgba(34, 211, 238, 0.48)
    Color(0x7AFACC15), // rgba(250, 204, 21, 0.48)
    Color(0x7A818CF8), // rgba(129, 140, 248, 0.48)
  ];

  static int _tagIndex(int id, String name) {
    int hash = id * 7;
    for (int i = 0; i < name.length; i++) {
      hash = (hash * 33 + name.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash % _tagBg.length;
  }

  static Color tagBg(int id, [String name = '']) {
    return _tagBg[_tagIndex(id, name)];
  }

  static Color tagBorder(int id, [String name = '']) {
    return _tagBorder[_tagIndex(id, name)];
  }
}
