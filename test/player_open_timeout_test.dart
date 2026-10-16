import 'package:flutter_test/flutter_test.dart';
import 'package:ecohub_android/components/player/player_playback_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerPlaybackController open timeout', () {
    test('timeout is terminal: a late initialize failure does not replace the error', () {
      final ctrl = PlayerPlaybackController();
      ctrl.debugArmOpeningSession();
      final session = ctrl.initSessionId;
      expect(ctrl.isOpening, isTrue);
      expect(ctrl.errorText, isEmpty);

      ctrl.debugExpireOpenWatch();
      expect(ctrl.errorText, '视频打开超时(30s)');
      expect(ctrl.isOpening, isFalse);
      expect(ctrl.isBuffering, isFalse);
      expect(ctrl.initSessionId, greaterThan(session));

      ctrl.debugLateInitFailure(session, 'ExoPlayer: source error');
      expect(ctrl.errorText, '视频打开超时(30s)');
      expect(ctrl.isOpening, isFalse);
    });

    test('a failure on the current session still sets 视频加载失败', () {
      final ctrl = PlayerPlaybackController();
      ctrl.debugArmOpeningSession();
      ctrl.debugLateInitFailure(ctrl.initSessionId, 'bad url');
      expect(ctrl.errorText, '视频加载失败: bad url');
      expect(ctrl.isOpening, isFalse);
      expect(ctrl.isPlaying, isFalse);
    });

    test('MediaCodec failure shows external player hint', () {
      final ctrl = PlayerPlaybackController();
      ctrl.debugArmOpeningSession();
      ctrl.debugLateInitFailure(ctrl.initSessionId, 'MediaCodecVideoRenderer: decode failed');
      expect(ctrl.errorText, contains('其它播放器'));
    });

    test('initPlayer with empty url does not report error and keeps silent state', () async {
      final ctrl = PlayerPlaybackController();
      await ctrl.initPlayer('');
      expect(ctrl.errorText, isEmpty);
      expect(ctrl.isOpening, isFalse);
      expect(ctrl.isPlaying, isFalse);
      expect(ctrl.isBuffering, isFalse);
      expect(ctrl.isReady, isFalse);
    });
  });
}
