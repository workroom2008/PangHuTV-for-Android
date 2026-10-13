import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// 应用升级信息
class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String releaseName;
  final String releaseNotes;
  final String releaseUrl;
  final String downloadUrl;

  AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    required this.releaseName,
    required this.releaseNotes,
    required this.releaseUrl,
    required this.downloadUrl,
  });
}

/// 版本工具与检查器
class AppVersionUtil {
  static const String appVersion = '1.0.2';
  static const String latestReleaseUrl = 'https://github.com/workroom2008/EcoHub-for-Android/releases/latest';
  static String _cachedVersionName = '';
  static AppUpdateInfo? _cachedUpdateInfo;
  static int _lastCheckTime = 0;
  static const int _cacheExpireMs = 10 * 60 * 1000; // 10分钟缓存

  static Future<String> getVersionName() async {
    if (_cachedVersionName.isNotEmpty) return _cachedVersionName;
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        _cachedVersionName = info.version;
        return _cachedVersionName;
      }
    } catch (_) {}
    _cachedVersionName = appVersion;
    return _cachedVersionName;
  }

  static bool isVersionMatched(String currentVersion, String? targetVersionsConfig) {
    final raw = (targetVersionsConfig ?? '').trim();
    if (raw.isEmpty || raw == '*' || raw.toLowerCase() == 'all') {
      return true;
    }
    final current = normalizeVersion(currentVersion).toLowerCase();
    final targets = raw
        .split(RegExp(r'[,;\s\n]+'))
        .map((e) => normalizeVersion(e).toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();

    if (targets.isEmpty) return true;
    return targets.contains(current);
  }

  static String normalizeVersion(String v) {
    var s = v.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1).trim();
    }
    return s;
  }

  static int compareVersion(String v1, String v2) {
    final s1 = normalizeVersion(v1);
    final s2 = normalizeVersion(v2);
    final base1 = s1.split('-')[0].split('+')[0];
    final base2 = s2.split('-')[0].split('+')[0];
    final parts1 = base1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 = base2.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (var i = 0; i < maxLen; i++) {
      final num1 = i < parts1.length ? parts1[i] : 0;
      final num2 = i < parts2.length ? parts2[i] : 0;
      if (num1 > num2) return 1;
      if (num1 < num2) return -1;
    }

    final hasPre1 = s1.contains('-');
    final hasPre2 = s2.contains('-');
    if (!hasPre1 && hasPre2) return 1;
    if (hasPre1 && !hasPre2) return -1;
    if (hasPre1 && hasPre2) {
      final pre1 = s1.substring(s1.indexOf('-') + 1).split('+')[0].split('.');
      final pre2 = s2.substring(s2.indexOf('-') + 1).split('+')[0].split('.');
      final preLen = pre1.length > pre2.length ? pre1.length : pre2.length;
      for (var i = 0; i < preLen; i++) {
        if (i >= pre1.length) return -1;
        if (i >= pre2.length) return 1;
        final p1 = pre1[i];
        final p2 = pre2[i];
        final n1 = int.tryParse(p1);
        final n2 = int.tryParse(p2);
        final isNum1 = n1 != null && '$n1' == p1;
        final isNum2 = n2 != null && '$n2' == p2;
        if (isNum1 && isNum2) {
          if (n1 != n2) return n1 > n2 ? 1 : -1;
        } else if (isNum1 && !isNum2) {
          return -1;
        } else if (!isNum1 && isNum2) {
          return 1;
        } else {
          final cmp = p1.compareTo(p2);
          if (cmp != 0) return cmp > 0 ? 1 : -1;
        }
      }
    }
    return 0;
  }

  static bool isNewerVersion(String latest, String current) {
    return compareVersion(latest, current) > 0;
  }

  static AppUpdateInfo? getCachedUpdateInfo() => _cachedUpdateInfo;

  /// 对齐 OHOS AppStorage HAS_APP_UPDATE / SHOW_APP_UPDATE_DIALOG
  static final ValueNotifier<bool> hasUpdate = ValueNotifier(false);
  static final ValueNotifier<bool> showUpdateDialog = ValueNotifier(false);
  static Future<AppUpdateInfo>? _inFlight;

  static void _publish(AppUpdateInfo info) {
    hasUpdate.value = info.hasUpdate;
  }

  static Future<AppUpdateInfo> checkUpdate({bool force = false, int timeoutMs = 10000}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && _cachedUpdateInfo != null && (now - _lastCheckTime < _cacheExpireMs)) {
      _publish(_cachedUpdateInfo!);
      return _cachedUpdateInfo!;
    }
    if (!force && _inFlight != null) {
      return _inFlight!;
    }

    Future<AppUpdateInfo> execute() async {
    final currentVersion = await getVersionName();
    var info = AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: currentVersion,
      hasUpdate: false,
      releaseName: '',
      releaseNotes: '',
      releaseUrl: '',
      downloadUrl: '',
    );

    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/workroom2008/EcoHub-for-Android/releases?per_page=10'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'EcoHub-App',
        },
      ).timeout(Duration(milliseconds: timeoutMs));

      if (res.statusCode != 200 || res.body.isEmpty) {
        throw Exception('HTTP ${res.statusCode}');
      }

      final releases = jsonDecode(res.body);
      if (releases is List && releases.isNotEmpty) {
        for (final item in releases) {
          if (item is! Map) continue;
          if (item['draft'] == true) continue;
          if (item['prerelease'] == true && !currentVersion.contains('-')) continue;

          final tagName = '${item['tag_name'] ?? ''}';
          final name = '${item['name'] ?? tagName}';
          final body = '${item['body'] ?? ''}';
          final htmlUrl = '${item['html_url'] ?? ''}';
          var downloadUrl = htmlUrl;

          final assets = item['assets'];
          if (assets is List && assets.isNotEmpty) {
            for (final asset in assets) {
              if (asset is! Map) continue;
              final assetName = '${asset['name'] ?? ''}';
              final bUrl = '${asset['browser_download_url'] ?? ''}';
              if ((assetName.endsWith('.apk') || assetName.endsWith('.ipa')) && bUrl.isNotEmpty) {
                downloadUrl = bUrl;
                break;
              }
            }
          }

          final normalizedTag = normalizeVersion(tagName);
          info = AppUpdateInfo(
            currentVersion: currentVersion,
            latestVersion: normalizedTag,
            hasUpdate: isNewerVersion(normalizedTag, currentVersion),
            releaseName: name.isNotEmpty ? name : 'v$normalizedTag',
            releaseNotes: body,
            releaseUrl: htmlUrl,
            downloadUrl: downloadUrl,
          );
          break;
        }
      }
      _cachedUpdateInfo = info;
      _lastCheckTime = now;
      _publish(info);
      return info;
    } catch (_) {
      if (_cachedUpdateInfo != null && !force) {
        _publish(_cachedUpdateInfo!);
        return _cachedUpdateInfo!;
      }
      _publish(info);
      return info;
    }
    }

    final req = execute();
    _inFlight = req;
    req.whenComplete(() {
      if (identical(_inFlight, req)) {
        _inFlight = null;
      }
    });
    return req;
  }
}
