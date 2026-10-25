import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecohub_android/utils/playback_url.dart';
import 'package:ecohub_android/utils/server_config_manager.dart';

// 手机端也必须让服务端代理分片：
// 实测极品源分片直连 CDN 只有 38KB/s（2.3MB 分片 60s 下不完），
// 经服务端代理是 1.9MB/s，差 50 倍。直连表现为"播 1-2 秒卡住 / 网络较慢"。
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigManager.instance.init();
    await ServerConfigManager.instance.setServerUrl('http://s');
  });

  group('appendServerMediaProxy', () {
    test('本站 /api/hls 补 client=tv', () {
      final out = PlaybackUrl.appendServerMediaProxy(
        'http://s/api/hls?source=1896829319&url=a.m3u8',
      );
      expect(out, contains('client=tv'));
    });

    test('hlsExoAlias 之后的 /api/hls.m3u8 也要补 client=tv', () {
      final aliased = PlaybackUrl.hlsExoAlias(
        'http://s/api/hls?source=1896829319&url=a.m3u8',
      );
      expect(aliased, contains('/api/hls.m3u8'));

      final out = PlaybackUrl.appendServerMediaProxy(aliased);
      expect(out, contains('client=tv'));
    });

    test('已带 client=tv 不重复追加', () {
      final out = PlaybackUrl.appendServerMediaProxy(
        'http://s/api/hls?source=1&url=a.m3u8&client=tv',
      );
      expect('client=tv'.allMatches(out).length, 1);
    });

    test('外部直链不改写', () {
      const raw = 'https://cdn.example.com/a/index.m3u8';
      expect(PlaybackUrl.appendServerMediaProxy(raw), raw);
    });

    test('本站非 hls 接口不改写（如 cover）', () {
      final out = PlaybackUrl.appendServerMediaProxy(
        'http://s/api/cover?source=1&url=p.jpg',
      );
      expect(out, isNot(contains('client=tv')));
    });
  });

  group('prepareForPlayer', () {
    test('极品 m3u8 最终地址带 client=tv 且保留 token', () {
      final out = PlaybackUrl.prepareForPlayer(
        '/api/hls?source=1896829319&url=https%3A%2F%2Fx%2Fa.m3u8',
      );
      expect(out, contains('/api/hls.m3u8'));
      expect(out, contains('client=tv'));
    });
  });
}
