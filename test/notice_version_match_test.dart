import 'package:flutter_test/flutter_test.dart';
import 'package:ecohub_android/models/api_parser.dart';
import 'package:ecohub_android/utils/app_version_util.dart';

void main() {
  group('notice version matching (OHOS parity)', () {
    test('empty / * / all match every app version', () {
      expect(AppVersionUtil.isVersionMatched('1.0.0-preview', ''), isTrue);
      expect(AppVersionUtil.isVersionMatched('1.0.0-preview', '*'), isTrue);
      expect(AppVersionUtil.isVersionMatched('1.0.0-preview', 'all'), isTrue);
    });

    test('explicit list still filters', () {
      expect(AppVersionUtil.isVersionMatched('1.0.0-preview', '1'), isFalse);
      expect(AppVersionUtil.isVersionMatched('1.0.0-preview', '1.0.0'), isFalse);
      expect(AppVersionUtil.isVersionMatched('1.0.0-preview', '1.0.0-preview'), isTrue);
      expect(AppVersionUtil.isVersionMatched('1.0.0-preview', '1.0.0, 1.0.0-preview'), isTrue);
    });

    test('parser keeps empty notice version empty (does not invent 1)', () {
      final config = ApiParser.parseBasicConfig({
        'siteName': '胖虎影视',
        'notice': {
          'enabled': true,
          'title': '站点公告',
          'content': '欢迎',
          'showInApp': true,
          'appVersion': '',
        },
      });
      expect(config.noticeEnabled, isTrue);
      expect(config.noticeAppVersion, '');
      expect(config.noticeVersion, '');
      expect(AppVersionUtil.isVersionMatched('1.0.0-preview', config.noticeAppVersion),
          isTrue);
    });
  });
}
