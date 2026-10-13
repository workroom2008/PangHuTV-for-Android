import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecohub_android/components/film_detail_dialog.dart';
import 'package:ecohub_android/components/notice_dialog.dart';
import 'package:ecohub_android/components/version_update_dialog.dart';
import 'package:ecohub_android/components/player/player_speed_sheet.dart';
import 'package:ecohub_android/components/cast/player_cast_sheet.dart';
import 'package:ecohub_android/components/server_history_dialog.dart';
import 'package:ecohub_android/utils/app_version_util.dart';
import 'package:ecohub_android/types/dlna_types.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dialog Landscape Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('FilmDetailDialog does not overflow in compact landscape', (tester) async {
      // 568x330 matches the exact overflow constraint from the user report
      tester.view.physicalSize = const Size(568, 330);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  FilmDetailDialog.show(
                    context,
                    name: '测试超长电影名称测试超长电影名称测试',
                    scoreText: '9.8',
                    tags: const ['科幻', '冒险', '动作', '2026', '中国大陆', '4K原画'],
                    director: '张三导演',
                    actor: '李四、王五、赵六、孙七、周八、吴九、郑十',
                    plot: '这是一个用于测试横屏弹窗自适应的超长剧情简介内容。' * 10,
                  );
                },
                child: const Text('Open Film Detail'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Film Detail'));
      await tester.pumpAndSettle();

      // Ensure no overflow exception occurred and content is displayed
      expect(tester.takeException(), isNull);
      expect(find.text('详细信息'), findsOneWidget);
      expect(find.text('我知道了'), findsOneWidget);

      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();
    });

    testWidgets('NoticeDialog does not overflow in compact landscape with long content', (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoticeDialog(
              title: '重要站点公告',
              content: '各位用户请注意，系统将于今晚进行例行网络升级与数据维护。\n' * 8,
              onClose: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('重要站点公告'), findsOneWidget);
      expect(find.text('我知道了'), findsOneWidget);
    });

    testWidgets('NoticeDialog respects large top safe area (Dynamic Island/notch)', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(top: 59.0, bottom: 34.0);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoticeDialog(
              title: '重要站点公告',
              content: '长公告内容测试\n' * 30,
              onClose: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final titleTopLeft = tester.getTopLeft(find.text('重要站点公告'));
      // 标题的 Y 坐标必须大于 topPadding (59.0)，绝对不能顶进灵动岛/状态栏
      expect(titleTopLeft.dy, greaterThan(59.0));
    });

    testWidgets('VersionUpdateDialog does not overflow in landscape', (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final updateInfo = AppUpdateInfo(
        hasUpdate: true,
        currentVersion: '1.0.0',
        latestVersion: '1.2.0',
        releaseName: 'v1.2.0 重大更新',
        releaseNotes: '1. 优化横屏弹窗布局\n2. 提升播放稳定性\n3. 增加投屏搜索\n4. 适配折叠屏\n' * 5,
        downloadUrl: 'https://example.com/update.apk',
        releaseUrl: 'https://example.com/releases/v1.2.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VersionUpdateDialog(
              updateInfo: updateInfo,
              onClose: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('前往更新'), findsOneWidget);
      expect(find.text('稍后再说'), findsOneWidget);
    });

    testWidgets('PlayerSpeedSheet does not overflow in landscape', (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PlayerSpeedSheet.show(context, 1.0, (_) {});
                },
                child: const Text('Open Speed'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Speed'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('播放倍速'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
      expect(find.text('3.0x'), findsOneWidget);
    });

    testWidgets('PlayerCastSheet does not overflow in landscape with multiple devices', (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PlayerCastSheet.show(
                    context,
                    mediaUrl: 'https://example.com/test.mp4',
                    mediaTitle: '测试电影',
                    seedDevice: const DlnaDevice(
                      usn: 'uuid:dev-1',
                      friendlyName: '客厅小米电视 4K',
                      location: 'http://192.168.1.100:8080/desc.xml',
                      controlURL: 'http://192.168.1.100:8080/ctl',
                      host: '192.168.1.100',
                      manufacturer: 'Xiaomi',
                    ),
                    connectedUsn: 'uuid:dev-1',
                    autoStartScan: false,
                    onCasted: (_) {},
                  );
                },
                child: const Text('Open Cast'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Cast'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('投屏到电视'), findsOneWidget);
      expect(find.text('客厅小米电视 4K'), findsOneWidget);

      Navigator.of(tester.element(find.text('投屏到电视'))).pop();
      await tester.pumpAndSettle();
    });

    testWidgets('showServerHistoryDialog does not overflow in landscape', (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final dummyHistory = List.generate(10, (i) => 'https://api.source-$i.example.com/api');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showServerHistoryDialog(
                    context: context,
                    historyOf: () => dummyHistory,
                    currentUrl: dummyHistory.first,
                    onSelect: (_) {},
                    onReload: () async {},
                    onToastCleared: () {},
                  );
                },
                child: const Text('Open Server History'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Server History'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('历史服务端'), findsOneWidget);
      expect(find.text('点击任意地址即可直接选择填入'), findsOneWidget);
    });

    testWidgets('NoticeDialog stays centered when stacked over page content', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const ColoredBox(color: Colors.black, child: SizedBox.expand()),
                NoticeDialog(
                  title: '站点公告',
                  content: '欢迎使用胖虎影视',
                  onClose: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final screen = tester.getSize(find.byType(Scaffold));
      final title = tester.getCenter(find.text('站点公告'));
      expect((title.dx - screen.width / 2).abs(), lessThan(24));
      expect(title.dy, greaterThan(screen.height * 0.2));
      expect(title.dy, lessThan(screen.height * 0.55));
    });

    testWidgets('VersionUpdateDialog stays centered when stacked over splash', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final updateInfo = AppUpdateInfo(
        hasUpdate: true,
        currentVersion: '1.0.0-preview',
        latestVersion: '1.0.1',
        releaseName: 'v1.0.1',
        releaseNotes: '稳定性优化',
        downloadUrl: 'https://example.com/update.apk',
        releaseUrl: 'https://example.com/releases/v1.0.1',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const ColoredBox(color: Colors.black, child: SizedBox.expand()),
                VersionUpdateDialog(
                  updateInfo: updateInfo,
                  onClose: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final screen = tester.getSize(find.byType(Scaffold));
      final title = tester.getCenter(find.text('发现新版本'));
      expect((title.dx - screen.width / 2).abs(), lessThan(24));
      expect(title.dy, greaterThan(screen.height * 0.15));
      expect(title.dy, lessThan(screen.height * 0.5));
    });

    testWidgets('VersionUpdateDialog jumps to releaseUrl instead of downloadUrl when clicking update', (tester) async {
      final mockPlatform = _MockUrlLauncher();
      UrlLauncherPlatform.instance = mockPlatform;

      var closed = false;
      final updateInfo = AppUpdateInfo(
        hasUpdate: true,
        currentVersion: '1.0.0',
        latestVersion: '1.0.1',
        releaseName: 'v1.0.1',
        releaseNotes: '稳定性优化',
        downloadUrl: 'https://example.com/update.apk',
        releaseUrl: 'https://github.com/workroom2008/PangHuTV-for-Android/releases/tag/v1.0.1',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VersionUpdateDialog(
              updateInfo: updateInfo,
              onClose: () {
                closed = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('前往更新'));
      await tester.pumpAndSettle();

      expect(mockPlatform.launchedUrl, 'https://github.com/workroom2008/PangHuTV-for-Android/releases/tag/v1.0.1');
      expect(closed, isTrue);
    });

    testWidgets('VersionUpdateDialog falls back to latestReleaseUrl when releaseUrl is empty', (tester) async {
      final mockPlatform = _MockUrlLauncher();
      UrlLauncherPlatform.instance = mockPlatform;

      var closed = false;
      final updateInfo = AppUpdateInfo(
        hasUpdate: true,
        currentVersion: '1.0.0',
        latestVersion: '1.0.1',
        releaseName: 'v1.0.1',
        releaseNotes: '稳定性优化',
        downloadUrl: 'https://example.com/update.apk',
        releaseUrl: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VersionUpdateDialog(
              updateInfo: updateInfo,
              onClose: () {
                closed = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('前往更新'));
      await tester.pumpAndSettle();

      expect(mockPlatform.launchedUrl, AppVersionUtil.latestReleaseUrl);
      expect(closed, isTrue);
    });

    testWidgets('NoticeDialog covers bottom navigation bar when displayed over scaffold with bottom bar', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Scaffold(
                body: const Center(child: Text('Content')),
                bottomNavigationBar: BottomNavigationBar(
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.home), label: '推荐'),
                    BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
                  ],
                ),
              ),
              NoticeDialog(
                title: '站点公告',
                content: '全屏遮罩测试',
                onClose: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dialogFinder = find.byType(NoticeDialog);
      expect(dialogFinder, findsOneWidget);
      final dialogSize = tester.getSize(dialogFinder);
      expect(dialogSize.width, 390.0);
      expect(dialogSize.height, 844.0);

      final navBar = tester.getRect(find.byType(BottomNavigationBar));
      expect(navBar.bottom, lessThanOrEqualTo(dialogSize.height));
      expect(navBar.top, greaterThan(0));
    });
  });
}

class _MockUrlLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  String? launchedUrl;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrl = url;
    return true;
  }
}
