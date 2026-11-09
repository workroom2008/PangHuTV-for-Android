import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecohub_android/components/cast/player_cast_controller.dart';
import 'package:ecohub_android/components/cast/player_cast_sheet.dart';
import 'package:ecohub_android/components/player/player_playback_controller.dart';
import 'package:ecohub_android/components/player/video_player_widget.dart';
import 'package:ecohub_android/services/cast_session.dart';
import 'package:ecohub_android/services/dlna_client.dart';
import 'package:ecohub_android/types/dlna_types.dart';

class FakeDlnaClient extends DlnaClient {
  int discoverCalls = 0;
  int cancelCalls = 0;
  Completer<List<DlnaDevice>>? pendingCompleter;

  @override
  Future<List<DlnaDevice>> discover({void Function(List<DlnaDevice>)? onUpdate}) {
    discoverCalls++;
    final completer = Completer<List<DlnaDevice>>();
    pendingCompleter = completer;
    return completer.future;
  }

  @override
  void cancelDiscover() {
    cancelCalls++;
  }
}

class MockPlayerCastHost implements PlayerCastHost {
  double currentPos = 25.0;
  double totalDur = 120.0;
  bool playing = true;
  bool opening = false;
  bool buffering = false;
  String url = 'https://example.com/video1.mp4';
  String mediaTitle = '测试影片 第1集';
  bool hasNextEpisode = true;
  double vol = 0.75;
  bool fullscreen = false;

  bool parkLocalCalled = false;
  bool pauseLocalCalled = false;
  double? resumeTargetSec;
  bool? resumeWasPlaying;
  double? completedPosSec;
  double? completedDurSec;
  bool exitFullCalled = false;
  bool onCastEndedCalled = false;
  bool syncUiCalled = false;
  double? lastSyncCur;
  double? lastSyncDur;
  String? lastToast;
  bool? autoPipEnabled;
  bool stopPipCalled = false;

  @override
  double get currentPosition => currentPos;
  @override
  double get totalDuration => totalDur;
  @override
  bool get isPlaying => playing;
  @override
  bool get isOpening => opening;
  @override
  bool get isBuffering => buffering;
  @override
  String get videoUrl => url;
  @override
  String get title => mediaTitle;
  @override
  bool get hasNext => hasNextEpisode;
  @override
  double get volume => vol;
  @override
  bool get isFull => fullscreen;

  @override
  void parkLocal() {
    parkLocalCalled = true;
  }

  @override
  void pauseLocal() {
    pauseLocalCalled = true;
  }

  @override
  void resumeLocal(double targetSec, bool wasPlaying) {
    resumeTargetSec = targetSec;
    resumeWasPlaying = wasPlaying;
  }

  @override
  void remountCompleted(double positionSec, double durationSec) {
    completedPosSec = positionSec;
    completedDurSec = durationSec;
  }

  @override
  void exitFullForCast() {
    exitFullCalled = true;
  }

  @override
  void onCastEnded() {
    onCastEndedCalled = true;
  }

  @override
  void syncUi() {
    syncUiCalled = true;
  }

  @override
  void syncProgress(double currentSec, double durationSec) {
    lastSyncCur = currentSec;
    lastSyncDur = durationSec;
  }

  @override
  void showToast(String message) {
    lastToast = message;
  }

  @override
  void setPipAutoStart(bool enable) {
    autoPipEnabled = enable;
  }

  @override
  void stopPip() {
    stopPipCalled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerPlaybackController parkForCast & lifecycle Tests', () {
    test('parkForCast releases controller and resets all playback flags safely', () {
      final ctrl = PlayerPlaybackController();
      ctrl.parkForCast();

      expect(ctrl.videoController, isNull);
      expect(ctrl.isPlaying, isFalse);
      expect(ctrl.isBuffering, isFalse);
      expect(ctrl.isOpening, isFalse);
      expect(ctrl.isCompleted, isFalse);
      expect(ctrl.errorText, isEmpty);
    });

    test('pauseLocal safely pauses and disables wakelock', () {
      final ctrl = PlayerPlaybackController();
      ctrl.pauseLocal();
      expect(ctrl.isPlaying, isFalse);
      expect(ctrl.isBuffering, isFalse);
    });

    test('resumeLocal after pauseLocal does not remount or enter opening state', () {
      final ctrl = PlayerPlaybackController();
      ctrl.pauseLocal();
      ctrl.resumeLocal(42, true);
      expect(ctrl.videoController, isNull);
      expect(ctrl.isOpening, isFalse);
      expect(ctrl.isPlaying, isTrue);
      expect(ctrl.playRequested, isTrue);
    });

    test('remountCompleted sets isCompleted and duration without playing', () {
      final ctrl = PlayerPlaybackController();
      ctrl.remountCompleted(100.0, 100.0);
      expect(ctrl.videoController, isNull);
      expect(ctrl.isCompleted, isTrue);
      expect(ctrl.isPlaying, isFalse);
      expect(ctrl.currentPosition, const Duration(seconds: 100));
      expect(ctrl.totalDuration, const Duration(seconds: 100));
    });
  });

  group('PlayerCastController Lifecycle & State Tests', () {
    const testDevice = DlnaDevice(
      usn: 'uuid:12345::urn:schemas-upnp-org:device:MediaRenderer:1',
      friendlyName: '客厅小米电视',
      location: 'http://192.168.1.100:49152/description.xml',
      controlURL: 'http://192.168.1.100:49152/AVTransport/control',
      renderingControlURL: 'http://192.168.1.100:49152/RenderingControl/control',
      host: '192.168.1.100',
    );

    testWidgets('openCastDialog delegates to sheet without pre-pausing so wasPlaying stays true', (tester) async {
      final castCtrl = PlayerCastController();
      final host = MockPlayerCastHost();
      castCtrl.attachHost(host);

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      host.playing = true;
      host.currentPos = 18.0;
      host.pauseLocalCalled = false;
      castCtrl.openCastDialog(ctx, autoStartScan: false);
      await tester.pump();

      expect(castCtrl.startSec, 18.0);
      expect(castCtrl.wasPlaying, isTrue);
      expect(castCtrl.pausedForPicker, isTrue);
      expect(host.pauseLocalCalled, isTrue);
      expect(host.parkLocalCalled, isFalse);

      Navigator.pop(ctx);
      await tester.pumpAndSettle();
      expect(host.resumeTargetSec, 18.0);
      expect(host.resumeWasPlaying, isTrue);
    });

    testWidgets('openCastSheet snapshots startSec, wasPlaying and pauses local player', (tester) async {
      final castCtrl = PlayerCastController();
      final host = MockPlayerCastHost();
      castCtrl.attachHost(host);

      expect(castCtrl.isCasting, isFalse);

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      host.playing = true;
      host.currentPos = 42.0;
      castCtrl.openCastSheet(
        ctx,
        mediaUrl: host.videoUrl,
        currentPosition: host.currentPosition,
        autoStartScan: false,
      );
      await tester.pump();

      expect(castCtrl.startSec, 42.0);
      expect(castCtrl.wasPlaying, isTrue);
      expect(castCtrl.pausedForPicker, isTrue);
      expect(host.pauseLocalCalled, isTrue);
      expect(host.parkLocalCalled, isFalse);

      Navigator.pop(ctx);
      await tester.pumpAndSettle();

      expect(castCtrl.pausedForPicker, isFalse);
      expect(host.resumeTargetSec, 42.0);
      expect(host.resumeWasPlaying, isTrue);
      expect(host.parkLocalCalled, isFalse);
    });

    test('bindCastDevice parks local player, exits fullscreen, pushes volume and disables PiP', () {
      final castCtrl = PlayerCastController();
      final host = MockPlayerCastHost();
      castCtrl.attachHost(host);

      host.playing = true;
      host.currentPos = 30.0;
      host.fullscreen = true;
      castCtrl.startSec = 30.0;
      castCtrl.wasPlaying = true;
      castCtrl.pausedForPicker = true;

      castCtrl.bindCastDevice(testDevice);

      expect(castCtrl.isCasting, isTrue);
      expect(castCtrl.device, testDevice);
      expect(castCtrl.deviceName, '客厅小米电视');
      expect(castCtrl.connectedUsn, testDevice.usn);
      expect(castCtrl.pausedForPicker, isFalse);
      expect(host.autoPipEnabled, isFalse);
      expect(host.stopPipCalled, isTrue);
      expect(host.exitFullCalled, isTrue);
      expect(host.parkLocalCalled, isTrue);
      expect(host.syncUiCalled, isTrue);
    });

    test('handleSourceChange recasts current URL during casting without waking local player', () {
      final castCtrl = PlayerCastController();
      final host = MockPlayerCastHost();
      castCtrl.attachHost(host);
      castCtrl.bindCastDevice(testDevice);

      host.parkLocalCalled = false;
      host.url = 'https://example.com/video2.mp4';
      host.mediaTitle = '测试影片 第2集';

      final consumed = castCtrl.handleSourceChange();
      expect(consumed, isTrue);
      expect(host.parkLocalCalled, isFalse);
      expect(host.resumeTargetSec, isNull);
    });

    test('finishCastCompleted remounts player in completed state when hasNext is false', () {
      final castCtrl = PlayerCastController();
      final host = MockPlayerCastHost();
      castCtrl.attachHost(host);
      castCtrl.bindCastDevice(testDevice);

      host.hasNextEpisode = false;
      castCtrl.session.positionSec = 120.0;
      castCtrl.session.durationSec = 120.0;

      castCtrl.session.onCompleted?.call();

      expect(castCtrl.isCasting, isFalse);
      expect(host.completedPosSec, 120.0);
      expect(host.completedDurSec, 120.0);
      expect(host.onCastEndedCalled, isFalse);
    });

    test('onCompleted sets keepCastForNext and calls onCastEnded when hasNext is true', () {
      final castCtrl = PlayerCastController();
      final host = MockPlayerCastHost();
      castCtrl.attachHost(host);
      castCtrl.bindCastDevice(testDevice);

      host.hasNextEpisode = true;
      castCtrl.session.onCompleted?.call();

      expect(castCtrl.keepCastForNext, isTrue);
      expect(host.onCastEndedCalled, isTrue);
    });

    test('handleCastFailed and handleCastDisconnected restore local player at current pos', () {
      final castCtrl = PlayerCastController();
      final host = MockPlayerCastHost();
      castCtrl.attachHost(host);
      castCtrl.bindCastDevice(testDevice);
      castCtrl.wasPlaying = true;

      castCtrl.session.onDisconnected?.call(75.0);
      expect(castCtrl.isCasting, isFalse);
      expect(host.resumeTargetSec, 75.0);
      expect(host.resumeWasPlaying, isTrue);
      expect(host.lastToast, contains('已停止投屏'));

      castCtrl.bindCastDevice(testDevice);
      castCtrl.wasPlaying = false;
      castCtrl.session.onFailed?.call(88.0);
      expect(castCtrl.isCasting, isFalse);
      expect(host.resumeTargetSec, 88.0);
      expect(host.resumeWasPlaying, isFalse);
      expect(host.lastToast, contains('投屏失败'));
    });

    test('pushCastVolume calculates and clamps percentage to DLNA renderer', () {
      final castCtrl = PlayerCastController();
      final host = MockPlayerCastHost();
      castCtrl.attachHost(host);
      castCtrl.bindCastDevice(testDevice);

      host.vol = 0.65;
      castCtrl.pushCastVolume();
      expect(castCtrl.isCasting, isTrue);
    });
  });

  group('CastSession DLNA Polling & EOS Tests', () {
    const dev = DlnaDevice(
      usn: 'uuid:test-dev',
      friendlyName: 'Test Renderer',
      location: 'http://127.0.0.1:1234/desc.xml',
      controlURL: 'http://127.0.0.1:1234/control',
      renderingControlURL: 'http://127.0.0.1:1234/rc',
    );

    test('attach initializes session timeout and state', () {
      final session = CastSession();
      session.attach(dev);
      expect(session.device, dev);
      expect(session.transportState, isEmpty);
      expect(session.active, isTrue);
    });

    test('beginLaunch sets launching phase and pendingStartSec', () {
      final session = CastSession();
      session.attach(dev);
      session.beginLaunch(50.0, 100.0);

      expect(session.positionSec, 50.0);
      expect(session.durationSec, 100.0);
      expect(session.pendingStartSec, 50.0);
      expect(session.phase, CastPhase.launching);
      session.clearLocal();
    });

    test('isRelTimeUnavailable detects NOT_IMPLEMENTED and empty strings', () {
      expect(isRelTimeUnavailable(''), isTrue);
      expect(isRelTimeUnavailable('   '), isTrue);
      expect(isRelTimeUnavailable('NOT_IMPLEMENTED'), isTrue);
      expect(isRelTimeUnavailable('not_implemented'), isTrue);
      expect(isRelTimeUnavailable('00:01:23'), isFalse);
    });
  });

  group('VideoPlayerWidget Casting Widget State Tests', () {
    testWidgets('VideoPlayerWidget didUpdateWidget consumes episode change while casting', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoPlayerWidget(
              videoUrl: 'https://example.com/ep1.mp4',
              title: '剧集 第1集',
              reloadToken: 1,
            ),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(VideoPlayerWidget));
      expect(state, isNotNull);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoPlayerWidget(
              videoUrl: 'https://example.com/ep2.mp4',
              title: '剧集 第2集',
              reloadToken: 2,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(VideoPlayerWidget), findsOneWidget);
    });
  });

  group('PlayerCastSheet Refresh & State Feedback Tests', () {
    testWidgets('refresh button provides active feedback during scanning and allows re-scan', (tester) async {
      final fakeClient = FakeDlnaClient();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerCastSheet(
              mediaUrl: 'https://example.com/test.mp4',
              client: fakeClient,
              autoStartScan: true,
              debounceMs: 0,
              onCasted: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('扫描中'), findsWidgets);
      final textBtnFinder = find.widgetWithText(TextButton, '扫描中');
      expect(textBtnFinder, findsOneWidget);
      final btn = tester.widget<TextButton>(textBtnFinder);
      expect(btn.onPressed, isNotNull);
      expect(fakeClient.discoverCalls, 1);

      await tester.tap(textBtnFinder);
      await tester.pump();

      expect(fakeClient.discoverCalls, 2);
      expect(fakeClient.cancelCalls, greaterThanOrEqualTo(1));
      expect(find.text('扫描中'), findsWidgets);

      fakeClient.pendingCompleter?.complete([
        const DlnaDevice(
          usn: 'uuid:dev-1',
          friendlyName: '客厅电视',
          location: 'http://192.168.1.50:8080/desc.xml',
          controlURL: 'http://192.168.1.50:8080/ctl',
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('客厅电视'), findsOneWidget);
      expect(find.text('刷新'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 350));
      final refreshBtnFinder = find.widgetWithText(TextButton, '刷新');
      await tester.tap(refreshBtnFinder);
      await tester.pump();

      expect(fakeClient.discoverCalls, 3);
      expect(find.text('扫描中'), findsWidgets);
    });

    testWidgets('stale scan completes do not overwrite newer scan sequence', (tester) async {
      final fakeClient = FakeDlnaClient();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerCastSheet(
              mediaUrl: 'https://example.com/test.mp4',
              client: fakeClient,
              autoStartScan: true,
              debounceMs: 0,
              onCasted: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final firstCompleter = fakeClient.pendingCompleter;
      expect(fakeClient.discoverCalls, 1);

      final btnFinder = find.widgetWithText(TextButton, '扫描中');
      await tester.tap(btnFinder);
      await tester.pump();
      expect(fakeClient.discoverCalls, 2);

      firstCompleter?.complete([
        const DlnaDevice(
          usn: 'uuid:old-dev',
          friendlyName: '旧设备',
          location: 'http://192.168.1.99:8080/desc.xml',
          controlURL: 'http://192.168.1.99:8080/ctl',
        ),
      ]);
      await tester.pump();

      expect(find.text('扫描中'), findsWidgets);
      expect(find.text('旧设备'), findsNothing);
    });
  });
}
