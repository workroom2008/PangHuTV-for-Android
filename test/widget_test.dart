import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecohub_android/models/api_parser.dart';
import 'package:ecohub_android/utils/format_util.dart';
import 'package:ecohub_android/utils/server_config_manager.dart';
import 'package:ecohub_android/api/http_client.dart';
import 'package:ecohub_android/utils/app_version_util.dart';
import 'package:ecohub_android/utils/clipboard_sniffer.dart';
import 'package:ecohub_android/utils/nav_util.dart';
import 'package:ecohub_android/utils/breakpoint.dart';
import 'package:ecohub_android/utils/split_cutout_insets.dart';
import 'package:ecohub_android/common/app_theme.dart';
import 'package:ecohub_android/components/filter_tag_row.dart';
import 'package:ecohub_android/components/filter_bar.dart';
import 'package:ecohub_android/components/dynamic_sliver_appbar.dart';
import 'package:ecohub_android/components/sticky_appbar.dart';
import 'package:ecohub_android/components/home_banner.dart';
import 'package:ecohub_android/models/film_models.dart';
import 'package:ecohub_android/components/film_card.dart';
import 'package:ecohub_android/components/film_grid.dart';
import 'package:ecohub_android/components/film_row.dart';
import 'package:ecohub_android/components/player/play_detail_panel.dart';
import 'package:ecohub_android/components/player/video_player_widget.dart';
import 'package:ecohub_android/components/player/player_skin_view.dart';
import 'package:ecohub_android/components/player/player_video_surface.dart';
import 'package:ecohub_android/components/player/player_scale.dart';
import 'package:ecohub_android/components/player/player_playback_controller.dart';
import 'package:ecohub_android/components/player/player_bars.dart';
import 'package:ecohub_android/components/player/player_gesture_handler.dart';
import 'package:ecohub_android/pages/server_config_page.dart';
import 'package:ecohub_android/pages/daily_updates_tab.dart';
import 'package:ecohub_android/pages/settings_page.dart';
import 'package:ecohub_android/pages/profile_tab.dart';
import 'package:ecohub_android/pages/about_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _setViewInsets(WidgetTester tester, FakeViewPadding insets) {
  tester.view.padding = insets;
  tester.view.viewPadding = insets;
}

void _resetViewInsets(WidgetTester tester) {
  tester.view.resetPadding();
  tester.view.resetViewPadding();
}

SplitCutoutInsets _cutoutOf(BuildContext context) {
  final mq = MediaQuery.of(context);
  return SplitCutoutInsets.resolve(
    mq.viewPadding,
    padding: mq.padding,
    displayFeatures: mq.displayFeatures,
    size: mq.size,
  );
}

void _mockClipboard(WidgetTester tester, String text) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.getData') {
        if (text.isEmpty) return null;
        return <String, dynamic>{'text': text};
      }
      return null;
    },
  );
}

void main() {
  group('ApiParser Tests', () {
    test('parseBasicConfig with full fields', () {
      final json = {
        'siteName': 'TestHub',
        'siteUrl': 'https://test.com',
        'state': true,
        'hint': 'hello',
        'tip': {
          'enabled': true,
          'title': '赞赏',
          'message': '谢谢支持',
          'channels': [
            {'key': 'wx', 'label': '微信', 'qrImage': '/wx.png', 'link': 'https://wx.com'}
          ]
        },
        'notice': {
          'enabled': true,
          'title': '公告',
          'content': '测试公告',
          'appVersion': '1.0.0',
        }
      };

      final config = ApiParser.parseBasicConfig(json);
      expect(config.siteName, 'TestHub');
      expect(config.tipEnabled, true);
      expect(config.tipChannels.length, 1);
      expect(config.tipChannels.first.label, '微信');
      expect(config.noticeEnabled, true);
      expect(config.noticeTitle, '公告');
      expect(config.noticeAppVersion, '1.0.0');
    });

    test('parseMovie and parseHome with fallback', () {
      final json = {
        'banners': [
          {'id': '101', 'mid': 101, 'name': 'Banner Movie', 'year': '2026'}
        ],
        'content': [
          {
            'nav': {'id': 1, 'name': '电影', 'show': true},
            'movies': [
              {'id': 1001, 'name': 'Movie 1', 'year': '2025', 'cName': '科幻'}
            ],
            'hot': []
          }
        ]
      };

      final home = ApiParser.parseHome(json);
      expect(home.banners.length, 1);
      expect(home.banners.first.name, 'Banner Movie');
      expect(home.content.length, 1);
      expect(home.content.first.nav.name, '电影');
      expect(home.content.first.movies.first.name, 'Movie 1');
    });

    test('parseFilter keeps all tag rows even if sortList only has Sort', () {
      final result = ApiParser.parseFilter({
        'title': {'name': '剧集', 'id': 1},
        'list': [],
        'page': {'current': 1, 'pageCount': 1, 'total': 10, 'pageSize': 21},
        'params': {'Sort': 'update_stamp'},
        'search': {
          'titles': {'Category': '类型', 'Plot': '剧情', 'Sort': '排序'},
          'sortList': ['Sort'],
          'tags': {
            'Category': [
              {'Name': '全部', 'Value': ''},
              {'Name': '韩剧', 'Value': '2'},
            ],
            'Plot': [
              {'name': '全部', 'value': ''},
              {'name': '爱情', 'value': '爱情'},
            ],
            'Sort': [
              {'Name': '最近更新', 'Value': 'update_stamp'},
              {'Name': '人气', 'Value': 'hits'},
            ],
          },
        },
      });
      expect(result.search.sortList, ['Sort']);
      expect(result.search.tagKeys.toSet(), {'Category', 'Plot', 'Sort'});
      expect(result.search.tagNames[result.search.tagKeys.indexOf('Category')], ['全部', '韩剧']);
      expect(result.search.tagNames[result.search.tagKeys.indexOf('Plot')], ['全部', '爱情']);
    });

    test('parsePlay falls back from detail root when descriptor empty', () {
      final info = ApiParser.parsePlay({
        'detail': {
          'id': 1,
          'name': 'Film',
          'descriptor': {},
          'subTitle': 'ST',
          'typeName': '剧情',
          'actor': 'A',
          'director': 'D',
          'blurb': '简介',
          'year': '2024',
          'list': [],
        },
        'current': {'episode': '1', 'link': 'http://x'},
        'currentPlayFrom': 's1',
        'currentEpisode': 0,
      });
      expect(info.detail.descriptor.subTitle, 'ST');
      expect(info.detail.descriptor.cName, '剧情');
      expect(info.detail.descriptor.actor, 'A');
      expect(info.detail.descriptor.director, 'D');
      expect(info.detail.descriptor.blurb, '简介');
      expect(info.detail.descriptor.content, '简介');
      expect(info.detail.descriptor.year, '2024');
    });

    test('parsePlay score from detail.vod_score', () {
      final info = ApiParser.parsePlay({
        'detail': {
          'id': 2,
          'name': 'Film2',
          'descriptor': {},
          'vod_score': '8.5',
          'list': [],
        },
        'current': {},
      });
      expect(info.detail.descriptor.dbScore, '8.5');
    });
  });

  group('FormatUtil Tests', () {
    test('duration formatting', () {
      expect(FormatUtil.duration(0), '00:00');
      expect(FormatUtil.duration(65), '01:05');
      expect(FormatUtil.duration(3665), '01:01:05');
    });

    test('progress formatting', () {
      expect(FormatUtil.progress(0, 100), '未观看');
      expect(FormatUtil.progress(50, 100), '观看至 00:50 (50%)');
      expect(FormatUtil.progress(99, 100), '已看完');
    });

    test('joinMeta formatting', () {
      expect(FormatUtil.joinMeta(['2026', '电影', '中国']), '2026 · 电影 · 中国');
      expect(FormatUtil.joinMeta(['2026', '', '中国']), '2026 · 中国');
    });

    test('imageHeaders for bilibili and douban anti-hotlink', () {
      final biliHeaders = FormatUtil.imageHeaders('https://i0.hdslb.com/bfs/bangumi/image/19a2d01429bcba6b31791277c016e0d1aa465974.png');
      expect(biliHeaders['Referer'], 'https://www.bilibili.com/');
      expect(biliHeaders.containsKey('User-Agent'), true);

      final doubanHeaders = FormatUtil.imageHeaders('https://img9.doubanio.com/view/photo/s_ratio_poster/public/p480747492.jpg');
      expect(doubanHeaders['Referer'], 'https://movie.douban.com/');

      final genericHeaders = FormatUtil.imageHeaders('https://example.com/cover.jpg');
      expect(genericHeaders.containsKey('Referer'), false);
      expect(genericHeaders.containsKey('User-Agent'), true);
    });
  });

  group('ServerConfigManager Tests', () {
    test('normalizeRaw and stripApiSuffix', () {
      final manager = ServerConfigManager.instance;
      expect(manager.normalizeRaw('demo.example.com'), 'https://demo.example.com');
      expect(manager.normalizeRaw('http://demo.example.com/'), 'http://demo.example.com');
      expect(ServerConfigManager.stripApiSuffix('https://demo.example.com/api'), 'https://demo.example.com');
      expect(ServerConfigManager.stripApiSuffix('https://demo.example.com/api/'), 'https://demo.example.com');
      expect(ServerConfigManager.stripApiSuffix('https://demo.example.com/api/provide/app'), 'https://demo.example.com');
      expect(ServerConfigManager.stripApiSuffix('https://demo.example.com/api/provide/app/'), 'https://demo.example.com');
      expect(ServerConfigManager.extractProvideKey('https://demo.example.com/api/provide/app?key=mykey'), 'mykey');
      expect(ServerConfigManager.stripProvideKey('https://demo.example.com/api/provide/app?key=mykey'), 'https://demo.example.com/api/provide/app');
      expect(ServerConfigManager.buildServerUrl('https://demo.example.com/api/provide/app', 'mykey'), 'https://demo.example.com/api/provide/app?key=mykey');
      expect(ServerConfigManager.buildServerUrl('https://demo.example.com/api/provide/app?key=oldkey', 'mykey'), 'https://demo.example.com/api/provide/app?key=mykey');
      expect(ServerConfigManager.buildServerUrl('https://demo.example.com/api/provide/app', ''), 'https://demo.example.com/api/provide/app');
    });

    test('testConnection empty url returns invalid message', () async {
      final res = await HttpClient.instance.testConnection('');
      expect(res.ok, false);
      expect(res.message, '请输入有效的服务端地址');
    });

    test('formatConnectionError correctly identifies 502/503/504 and connection refused as service error', () {
      final client = HttpClient.instance;
      expect(client.formatConnectionError(Exception('HTTP 502')), contains('服务未启动或网关异常 (服务错误)'));
      expect(client.formatConnectionError(Exception('504 Gateway Timeout')), contains('服务未启动或网关异常 (服务错误)'));
      expect(client.formatConnectionError(Exception('Connection refused, errno = 111')), contains('服务未启动或网关异常 (服务错误)'));
      expect(client.formatConnectionError(Exception('SocketException: OS Error: Connection refused')), contains('服务未启动或网关异常 (服务错误)'));
      expect(client.formatConnectionError(Exception('Future not completed: TimeoutException')), contains('连接超时'));
    });

    test('ConnectionResult fields', () {
      const res = ConnectionResult(ok: false, isPrivate: true, message: '该软件源已开启私有化访问，请在地址后追加 ?key=密钥');
      expect(res.ok, false);
      expect(res.isPrivate, true);
      expect(res.message, contains('私有化'));
    });
  });

  group('AppVersionUtil Tests', () {
    test('version comparison', () {
      expect(AppVersionUtil.compareVersion('1.0.1', '1.0.0'), 1);
      expect(AppVersionUtil.compareVersion('1.0.0', '1.0.0'), 0);
      expect(AppVersionUtil.compareVersion('1.0.0', '1.0.1'), -1);
      expect(AppVersionUtil.isNewerVersion('1.2.0', '1.1.9'), true);
      expect(AppVersionUtil.compareVersion('1.1.5', '1.1.5-beta'), 1);
      expect(AppVersionUtil.compareVersion('1.1.5-beta', '1.1.5'), -1);
      expect(AppVersionUtil.compareVersion('1.1.5-beta.2', '1.1.5-beta.1'), 1);
    });

    test('version match filter', () {
      expect(AppVersionUtil.isVersionMatched('1.0.0', '*'), true);
      expect(AppVersionUtil.isVersionMatched('1.0.0', 'all'), true);
      expect(AppVersionUtil.isVersionMatched('1.0.0', '1.0.0, 1.0.1'), true);
      expect(AppVersionUtil.isVersionMatched('1.0.2', '1.0.0, 1.0.1'), false);
      expect(AppVersionUtil.isVersionMatched('1.0.0', 'v1.0.0'), true);
      expect(AppVersionUtil.isVersionMatched('v1.0.0', '1.0.0'), true);
    });
  });

  group('ClipboardSniffer Tests', () {
    setUp(ClipboardSniffer.reset);
    tearDown(ClipboardSniffer.reset);

    test('extractVideoUrl empty and non-http', () {
      expect(ClipboardSniffer.extractVideoUrl(''), '');
      expect(ClipboardSniffer.extractVideoUrl('   '), '');
      expect(ClipboardSniffer.extractVideoUrl('没有链接'), '');
      expect(ClipboardSniffer.extractVideoUrl('ftp://x.com/a.mp4'), '');
    });

    test('extractVideoUrl from mixed text and trailing punct', () {
      expect(
        ClipboardSniffer.extractVideoUrl('看这个 https://cdn.example.com/a.m3u8 真好看'),
        'https://cdn.example.com/a.m3u8',
      );
      expect(
        ClipboardSniffer.extractVideoUrl('http://host/v.mp4。'),
        'http://host/v.mp4',
      );
      expect(
        ClipboardSniffer.extractVideoUrl('https://host/v.m3u8)'),
        'https://host/v.m3u8',
      );
      expect(
        ClipboardSniffer.extractVideoUrl('地址："https://host/v.mp4"'),
        'https://host/v.mp4',
      );
    });

    test('extractVideoUrl stops at CJK and takes first url', () {
      expect(
        ClipboardSniffer.extractVideoUrl('https://a.com/x中文.mp4'),
        'https://a.com/x',
      );
      expect(
        ClipboardSniffer.extractVideoUrl('https://a.com/1.mp4 https://b.com/2.m3u8'),
        'https://a.com/1.mp4',
      );
    });

    testWidgets('sniff reads clipboard once and skips handled raw', (tester) async {
      const raw = '看这个 https://cdn.example.com/a.m3u8';
      _mockClipboard(tester, raw);

      final first = await ClipboardSniffer.sniff();
      expect(first.url, 'https://cdn.example.com/a.m3u8');
      expect(first.raw, raw);

      ClipboardSniffer.markHandled(first.raw);
      final second = await ClipboardSniffer.sniff();
      expect(second.url, '');
      expect(second.raw, raw);

      ClipboardSniffer.reset();
      final third = await ClipboardSniffer.sniff();
      expect(third.url, 'https://cdn.example.com/a.m3u8');
    });

    testWidgets('sniff empty clipboard', (tester) async {
      _mockClipboard(tester, '');
      final res = await ClipboardSniffer.sniff();
      expect(res.url, '');
      expect(res.raw, '');
    });
  });

  group('NavUtil Tests', () {
    test('param reads string and fallback', () {
      expect(NavUtil.param({'url': 'https://a.com/v.mp4'}, 'url'), 'https://a.com/v.mp4');
      expect(NavUtil.param({'url': 1}, 'url'), '1');
      expect(NavUtil.param({}, 'url', 'x'), 'x');
      expect(NavUtil.param(null, 'url', 'x'), 'x');
    });
  });

  group('Breakpoint Tests', () {
    test('cardWidthOf matches OHOS formula', () {
      expect(Breakpoint.cardWidthOf(360), 104);
      expect(Breakpoint.cardWidthOf(390), 114);
      expect(Breakpoint.cardWidthOf(600), 136);
    });
  });

  group('FilterTagRow', () {
    testWidgets('highlights selected chip with accent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilterTagRow(
              filterKey: 'Sort',
              title: '排序',
              names: const ['最新', '最热'],
              values: const ['update_stamp', 'hits'],
              selected: 'update_stamp',
              onPick: (k, v) {},
            ),
          ),
        ),
      );
      expect(find.text('排序'), findsOneWidget);
      expect(find.text('最新'), findsOneWidget);
      final latest = tester.widget<Text>(find.text('最新'));
      expect(latest.style?.color, AppTheme.textPrimary);
      final hot = tester.widget<Text>(find.text('最热'));
      expect(hot.style?.color, AppTheme.textSecondary);
    });

    testWidgets('sliver filter chrome lays out', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                const DynamicSliverAppBar(
                  maxHeight: 88,
                  child: SizedBox(height: 88, child: ColoredBox(color: Colors.black)),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: StickyAppbar(child: const SizedBox(height: 48)),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DynamicSliverAppBar), findsOneWidget);
    });

    testWidgets('FilterBar parent stretches to all rows', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                DynamicSliverAppBar(
                  maxHeight: 800,
                  child: FilterBar(
                    keys: const ['Sort', 'Category', 'Plot'],
                    titleOf: (k) => k,
                    namesOf: (k) => const ['全部'],
                    valuesOf: (k) => const [''],
                    selectedOf: (k) => '',
                    onPick: (a, b) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(FilterTagRow), findsNWidgets(3));
      expect(
        tester.getSize(find.byType(FilterBar)).height,
        44 * 3 + AppTheme.spaceSm * 2,
      );
    });
  });

  group('HomeBanner Tests', () {
    final sampleBanners = [
      BannerItem(id: '1', mid: 1, name: 'Banner 1', remark: 'HD', year: '2024'),
      BannerItem(id: '2', mid: 2, name: 'Banner 2', remark: '超清', year: '2025'),
      BannerItem(id: '3', mid: 3, name: 'Banner 3', remark: '全集', year: '2026'),
    ];

    testWidgets('empty banners renders empty sized box', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeBanner(banners: []),
          ),
        ),
      );
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('single banner renders without indicator and loop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeBanner(banners: [sampleBanners.first]),
          ),
        ),
      );
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('Banner 1'), findsOneWidget);
      expect(find.byType(AnimatedContainer), findsNothing);
    });

    testWidgets('multi banners loop smoothly forward and backward', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeBanner(banners: sampleBanners),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Banner 1'), findsOneWidget);
      expect(find.byType(AnimatedContainer), findsNWidgets(3));

      // Drag right (swipe backwards from 0 to previous banner)
      await tester.drag(find.byType(PageView), const Offset(500, 0));
      await tester.pumpAndSettle();

      // Wraps seamlessly to Banner 3
      expect(find.text('Banner 3'), findsOneWidget);

      // Drag left (swipe forward to Banner 1)
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Banner 1'), findsOneWidget);

      // Drag left again to Banner 2
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Banner 2'), findsOneWidget);
    });

    testWidgets('auto-scroll advances to next banner smoothly', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeBanner(banners: sampleBanners),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Banner 1'), findsOneWidget);

      // Advance timer by 4800ms + animation duration
      await tester.pump(const Duration(milliseconds: 4850));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Banner 2'), findsOneWidget);
    });

    testWidgets('auto-scroll seamlessly loops across end boundary back to first banner', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeBanner(banners: sampleBanners),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Banner 1'), findsOneWidget);

      // 1 -> 2
      await tester.pump(const Duration(milliseconds: 4850));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Banner 2'), findsOneWidget);

      // 2 -> 3
      await tester.pump(const Duration(milliseconds: 4850));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Banner 3'), findsOneWidget);

      // 3 -> 1 (seamless forward loop across boundary without rewinding)
      await tester.pump(const Duration(milliseconds: 4850));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Banner 1'), findsOneWidget);
    });
  });

  group('ServerConfigPage Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'server_url': 'https://demo.example.com/api',
        'server_history': <String>['https://demo.example.com/api'],
      });
    });

    testWidgets('ServerConfigPage is vertically centered in portrait', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ServerConfigPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('EcoHub'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);

      final titleCenter = tester.getCenter(find.text('EcoHub'));
      final buttonCenter = tester.getCenter(find.byType(ElevatedButton));
      final contentMidY = (titleCenter.dy + buttonCenter.dy) / 2;

      // In an 800px tall screen, content midpoint should be close to 400 (within 50px)
      expect(contentMidY, greaterThan(350));
      expect(contentMidY, lessThan(450));
    });

    testWidgets('ServerConfigPage is vertically centered in landscape', (tester) async {
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ServerConfigPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('EcoHub'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);

      final buttonCenter = tester.getCenter(find.byType(ElevatedButton));
      // In a 400px tall screen with key field, button should be vertically centered near 200~260
      expect(buttonCenter.dy, greaterThan(150));
      expect(buttonCenter.dy, lessThan(280));
    });

    testWidgets('ServerConfigPage scrolls without overflow on compact heights', (tester) async {
      tester.view.physicalSize = const Size(400, 250);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ServerConfigPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('SplitCutoutInsets Tests', () {
    test('asymmetric padding zeroes non-cutout side', () {
      final s = SplitCutoutInsets.resolve(const EdgeInsets.fromLTRB(59, 0, 48, 0));
      expect(s.left, 59);
      expect(s.right, 0);

      final s2 = SplitCutoutInsets.resolve(const EdgeInsets.fromLTRB(48, 0, 59, 0));
      expect(s2.left, 0);
      expect(s2.right, 59);
    });

    test('right-only padding insets right', () {
      final s = SplitCutoutInsets.resolve(const EdgeInsets.fromLTRB(0, 0, 64, 0));
      expect(s.left, 0);
      expect(s.right, 64);
    });

    test('left-only padding insets left', () {
      final s = SplitCutoutInsets.resolve(const EdgeInsets.fromLTRB(64, 0, 0, 0));
      expect(s.left, 64);
      expect(s.right, 0);
    });

    test('equal non-zero keeps both', () {
      final s = SplitCutoutInsets.resolve(const EdgeInsets.fromLTRB(48, 0, 48, 0));
      expect(s.left, 48);
      expect(s.right, 48);
    });

    test('both zero stays zero', () {
      final s = SplitCutoutInsets.resolve(EdgeInsets.zero);
      expect(s.left, 0);
      expect(s.right, 0);
    });

    test('right punch hole from displayFeatures when padding is 0', () {
      const hole = DisplayFeature(
        bounds: Rect.fromLTWH(984, 180, 40, 40),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      );
      final s = SplitCutoutInsets.resolve(
        EdgeInsets.zero,
        displayFeatures: const [hole],
        size: const Size(1024, 466),
      );
      expect(s.left, 0);
      expect(s.right, 40);
    });

    test('left punch hole from displayFeatures when padding is 0', () {
      const hole = DisplayFeature(
        bounds: Rect.fromLTWH(0, 180, 40, 40),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      );
      final s = SplitCutoutInsets.resolve(
        EdgeInsets.zero,
        displayFeatures: const [hole],
        size: const Size(1024, 466),
      );
      expect(s.left, 40);
      expect(s.right, 0);
    });

    test('right punch hole zeros left padding', () {
      const hole = DisplayFeature(
        bounds: Rect.fromLTWH(984, 180, 40, 40),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      );
      final s = SplitCutoutInsets.resolve(
        const EdgeInsets.fromLTRB(64, 0, 0, 0),
        displayFeatures: const [hole],
        size: const Size(1024, 466),
      );
      expect(s.left, 0);
      expect(s.right, 40);
    });

    testWidgets('displayFeatures survive SafeArea consuming padding', (tester) async {
      tester.view.physicalSize = const Size(1024, 466);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const hole = DisplayFeature(
        bounds: Rect.fromLTWH(984, 180, 40, 40),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      );

      late SplitCutoutInsets cutout;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(1024, 466),
            padding: EdgeInsets.fromLTRB(64, 0, 0, 0),
            viewPadding: EdgeInsets.fromLTRB(64, 0, 0, 0),
            displayFeatures: [hole],
          ),
          child: SafeArea(
            child: Builder(
              builder: (context) {
                final mq = MediaQuery.of(context);
                cutout = SplitCutoutInsets.resolve(
                  mq.viewPadding,
                  padding: mq.padding,
                  displayFeatures: mq.displayFeatures,
                  size: mq.size,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(cutout.left, 0);
      expect(cutout.right, 40);
    });

    testWidgets('PlayerPlaybackController parkForCast releases controller and resets states', (tester) async {
      final ctrl = PlayerPlaybackController();
      ctrl.parkForCast();
      expect(ctrl.controller, isNull);
      expect(ctrl.isPlaying, isFalse);
      expect(ctrl.isBuffering, isFalse);
      expect(ctrl.isOpening, isFalse);
    });
  });

  group('FilmGrid and FilmCard Layout Tests', () {
    test('filmCardAspectRatio and gridAspectRatio calculations', () {
      final ratio1 = Breakpoint.filmCardAspectRatio(107.9);
      expect(ratio1, closeTo(0.5319, 0.001));

      final ratio2 = Breakpoint.filmCardAspectRatio(100.0);
      expect(ratio2, closeTo(0.5235, 0.001));

      final gridRatio = Breakpoint.gridAspectRatio(
        width: 350.0,
        columns: 3,
        horizontalPadding: 24.0,
        crossAxisSpacing: 8.0,
      );
      expect(gridRatio, closeTo(0.5272, 0.001));
    });

    testWidgets('FilmGrid does not overflow in landscape split-screen width', (tester) async {
      tester.view.physicalSize = const Size(890, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockFilms = List.generate(
        6,
        (i) => MovieBasicInfo(
          id: i + 1,
          name: '测试影片 $i',
          subTitle: '2024 · 动作',
          remarks: '更新至第${i + 1}集',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 350,
              height: 390,
              child: FilmGrid(
                films: mockFilms,
                columns: 3,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('测试影片 0'), findsOneWidget);
    });

    testWidgets('FilmCard does not overflow even under tight height constraint', (tester) async {
      final film = MovieBasicInfo(
        id: 1,
        name: '很长很长的影片标题测试文字',
        subTitle: '2024 · 剧情 · 中国大陆',
        remarks: 'HD国语',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 108,
              height: 190,
              child: FilmCard(film: film),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('很长很长的影片标题测试文字'), findsOneWidget);
    });

    testWidgets('PlayDetailPanel layout positions in landscape split', (tester) async {
      tester.view.physicalSize = const Size(890, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final sources = [
        PlaySource(
          id: 's1',
          sourceId: 'src_1',
          name: '默认源',
          linkList: List.generate(150, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i')),
        ),
        PlaySource(
          id: 's2',
          sourceId: 'src_2',
          name: '蓝光极速源',
          linkList: List.generate(150, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i')),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                const Expanded(flex: 7, child: SizedBox()),
                Expanded(
                  flex: 5,
                  child: PlayDetailPanel(
                    filmId: '1',
                    name: '测试影片标题',
                    sources: sources,
                    playingSourceId: 's1',
                    viewingSourceId: 's1',
                    episodeIndex: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      // Test starting in portrait and rotating to landscape
      tester.view.physicalSize = const Size(390, 890);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpAndSettle();

      final portraitGroup0 = tester.getTopLeft(find.text('1-100'));
      expect(portraitGroup0.dx, greaterThan(0));

      // Now rotate to landscape
      tester.view.physicalSize = const Size(890, 390);
      await tester.pumpAndSettle();

      final rotatedGroup0 = tester.getTopLeft(find.text('1-100'));
      final rotatedSource0 = tester.getTopLeft(find.text('默认源'));

      // Both should be left-aligned in the flex: 5 panel (starting at ~519.2)
      // group0 text is at 519.2 + 12 (padding) + 14 (chip padding) = 545.2
      // source0 text is at 519.2 + 12 (padding) + 12 (padding) + 16 (chip padding) = 559.2
      expect(rotatedGroup0.dx, closeTo(545.2, 1.0));
      expect(rotatedSource0.dx, closeTo(559.2, 1.0));
    });

    testWidgets('PlayDetailPanel precisely centers selected source chip on initial entry and clicks in split', (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final sources = [
        PlaySource(id: 's1', sourceId: 'src_1', name: '金鹰1(JY)', linkList: List.generate(10, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i'))),
        PlaySource(id: 's2', sourceId: 'src_2', name: '速博(SUBO)', linkList: List.generate(10, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i'))),
        PlaySource(id: 's3', sourceId: 'src_3', name: 'HD(SN)', linkList: List.generate(10, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i'))),
        PlaySource(id: 's4', sourceId: 'src_4', name: '金鹰2(JY)', linkList: List.generate(10, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i'))),
        PlaySource(id: 's5', sourceId: 'src_5', name: '红牛(HN)', linkList: List.generate(10, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i'))),
        PlaySource(id: 's6', sourceId: 'src_6', name: '非凡(FF)', linkList: List.generate(10, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i'))),
        PlaySource(id: 's7', sourceId: 'src_7', name: '暴风(BF)', linkList: List.generate(10, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i'))),
        PlaySource(id: 's8', sourceId: 'src_8', name: '量子(LZ)', linkList: List.generate(10, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i'))),
        PlaySource(id: 's9', sourceId: 'src_9', name: '卧龙(WL)', linkList: List.generate(10, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i'))),
        PlaySource(id: 's10', sourceId: 'src_10', name: '极速(JS)', linkList: List.generate(10, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i'))),
      ];

      String viewingId = 's2';

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Row(
                  children: [
                    const Expanded(flex: 7, child: SizedBox()),
                    Expanded(
                      flex: 5,
                      child: PlayDetailPanel(
                        filmId: '1',
                        name: '测试影片标题',
                        sources: sources,
                        playingSourceId: 's2',
                        viewingSourceId: viewingId,
                        episodeIndex: 2,
                        isSplit: true,
                        onViewSource: (id) => setState(() => viewingId = id),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final panelLeft = 800 * 7 / 12; // 466.666
      final panelWidth = 800 * 5 / 12; // 333.333
      final panelCenter = panelLeft + panelWidth / 2; // 633.333

      // 1. 首次进入时恢复播放非首个源，选中源胶囊居中聚焦
      final suboFinder = find.text('速博(SUBO)');
      final suboChip = find.ancestor(of: suboFinder, matching: find.byType(InkWell)).first;
      final suboRect = tester.getRect(suboChip);
      expect(suboRect.center.dx, closeTo(panelCenter, 15.0));

      // 2. 点击切换到 HD(SN) 后胶囊居中聚焦
      await tester.tap(find.text('HD(SN)'));
      await tester.pumpAndSettle();
      final hdsnFinder = find.text('HD(SN)');
      final hdsnChip = find.ancestor(of: hdsnFinder, matching: find.byType(InkWell)).first;
      final hdsnRect = tester.getRect(hdsnChip);
      expect(hdsnRect.center.dx, closeTo(panelCenter, 15.0));

      // 3. 点击切换到金鹰2(JY)、红牛(HN)
      await tester.tap(find.text('金鹰2(JY)'));
      await tester.pumpAndSettle();
      final jy2Finder = find.text('金鹰2(JY)');
      final jy2Chip = find.ancestor(of: jy2Finder, matching: find.byType(InkWell)).first;
      final jy2Rect = tester.getRect(jy2Chip);
      expect(jy2Rect.center.dx, closeTo(panelCenter, 15.0));

      await tester.tap(find.text('红牛(HN)'));
      await tester.pumpAndSettle();
      final hnFinder = find.text('红牛(HN)');
      final hnChip = find.ancestor(of: hnFinder, matching: find.byType(InkWell)).first;
      final hnRect = tester.getRect(hnChip);
      expect(hnRect.center.dx, closeTo(panelCenter, 15.0));
    });

    testWidgets('Landscape split mode honors right safe area insets', (tester) async {
      tester.view.physicalSize = const Size(890, 390);
      tester.view.devicePixelRatio = 1.0;
      _setViewInsets(tester, const FakeViewPadding(right: 48.0));
      addTearDown(() {
        tester.view.resetPhysicalSize();
        _resetViewInsets(tester);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final cutout = _cutoutOf(context);
              return Scaffold(
                body: Row(
                  children: [
                    const Expanded(flex: 7, child: SizedBox()),
                    Expanded(
                      flex: 5,
                      child: Container(
                        color: AppTheme.bgElevated,
                        child: SafeArea(
                          top: true,
                          bottom: true,
                          left: false,
                          right: false,
                          child: Padding(
                            padding: EdgeInsets.only(right: cutout.right),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('左侧标题'),
                                Text('右侧收藏按钮'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final buttonTopRight = tester.getTopRight(find.text('右侧收藏按钮'));
      // In 890 width screen with 48px right inset, rightmost widget must not exceed 890 - 48 = 842
      expect(buttonTopRight.dx, closeTo(890.0 - 48.0, 0.01));
    });

    testWidgets('Landscape split mode adapts insets dynamically based on cutout side', (tester) async {
      tester.view.physicalSize = const Size(1024, 466);
      tester.view.devicePixelRatio = 1.0;
      // 仅左侧有切口时，右侧详情贴齐平整短边
      _setViewInsets(tester, const FakeViewPadding(left: 59.0, right: 0.0));
      addTearDown(() {
        tester.view.resetPhysicalSize();
        _resetViewInsets(tester);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final cutout = _cutoutOf(context);

              return Scaffold(
                body: Row(
                  children: [
                    const Expanded(flex: 7, child: SizedBox()),
                    Expanded(
                      flex: 5,
                      child: Container(
                        color: AppTheme.bgElevated,
                        child: Padding(
                          padding: EdgeInsets.only(right: cutout.right),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('左侧'),
                              Text('贴边右侧按钮'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 当刘海在左侧时，右侧按钮紧贴屏幕边缘（1024），不被向内挤压
      final buttonPos = tester.getTopRight(find.text('贴边右侧按钮'));
      expect(buttonPos.dx, closeTo(1024.0, 0.01));
    });

    testWidgets('Landscape split zeroes right inset when cutout is on left with right system nav inset', (tester) async {
      tester.view.physicalSize = const Size(1024, 466);
      tester.view.devicePixelRatio = 1.0;
      _setViewInsets(tester, const FakeViewPadding(left: 59.0, right: 48.0));
      addTearDown(() {
        tester.view.resetPhysicalSize();
        _resetViewInsets(tester);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final cutout = _cutoutOf(context);

              return Scaffold(
                body: Row(
                  children: [
                    const Expanded(flex: 7, child: SizedBox()),
                    Expanded(
                      flex: 5,
                      child: Container(
                        color: AppTheme.bgElevated,
                        child: Padding(
                          padding: EdgeInsets.only(right: cutout.right),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('左侧'),
                              Text('无刘海贴边右侧按钮'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final buttonPos = tester.getTopRight(find.text('无刘海贴边右侧按钮'));
      expect(buttonPos.dx, closeTo(1024.0, 0.01));
    });

    testWidgets('Landscape split ignores left padding when punch hole is on right', (tester) async {
      tester.view.physicalSize = const Size(1024, 466);
      tester.view.devicePixelRatio = 1.0;
      _setViewInsets(tester, const FakeViewPadding(left: 64.0));
      addTearDown(() {
        tester.view.resetPhysicalSize();
        _resetViewInsets(tester);
      });

      const hole = DisplayFeature(
        bounds: Rect.fromLTWH(984, 180, 40, 40),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (outer) {
              return MediaQuery(
                data: MediaQuery.of(outer).copyWith(displayFeatures: const [hole]),
                child: Builder(
                  builder: (context) {
                    final cutout = _cutoutOf(context);
                    expect(cutout.left, 0);
                    return Scaffold(
                      body: Row(
                        children: [
                          const Expanded(flex: 7, child: SizedBox()),
                          Expanded(
                            flex: 5,
                            child: Padding(
                              padding: EdgeInsets.only(right: cutout.right),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('左侧'),
                                  Text('右侧按钮'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final buttonPos = tester.getTopRight(find.text('右侧按钮'));
      expect(buttonPos.dx, closeTo(1024.0 - 40.0, 0.01));
    });

    testWidgets('Landscape split insets right from punch-hole displayFeature', (tester) async {
      tester.view.physicalSize = const Size(1024, 466);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const hole = DisplayFeature(
        bounds: Rect.fromLTWH(984, 180, 40, 40),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (outer) {
              return MediaQuery(
                data: MediaQuery.of(outer).copyWith(displayFeatures: const [hole]),
                child: Builder(
                  builder: (context) {
                    final cutout = _cutoutOf(context);
                    return Scaffold(
                      body: Row(
                        children: [
                          const Expanded(flex: 7, child: SizedBox()),
                          Expanded(
                            flex: 5,
                            child: Padding(
                              padding: EdgeInsets.only(right: cutout.right),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('左侧'),
                                  Text('避让挖孔'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final buttonPos = tester.getTopRight(find.text('避让挖孔'));
      expect(buttonPos.dx, closeTo(1024.0 - 40.0, 0.01));
    });

    testWidgets('PlayDetailPanel uses 3 columns when isSplit is true on wide screens', (tester) async {
      tester.view.physicalSize = const Size(1024, 466);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
      });

      final sources = [
        PlaySource(
          id: 's1',
          sourceId: 'src_1',
          name: '默认源',
          linkList: List.generate(10, (i) => MovieUrlInfo(episode: '第${i + 1}集', link: 'url$i')),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                const Expanded(flex: 7, child: SizedBox()),
                Expanded(
                  flex: 5,
                  child: PlayDetailPanel(
                    filmId: '1',
                    name: '测试影片标题',
                    sources: sources,
                    playingSourceId: 's1',
                    viewingSourceId: 's1',
                    episodeIndex: 0,
                    isSplit: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check episode 1, 2, 3 positions - row 1 should contain 3 columns
      final ep1 = tester.getTopLeft(find.text('第1集'));
      final ep2 = tester.getTopLeft(find.text('第2集'));
      final ep3 = tester.getTopLeft(find.text('第3集'));
      final ep4 = tester.getTopLeft(find.text('第4集'));

      // ep1, ep2, ep3 are in the same horizontal row (same dy)
      expect(ep1.dy, equals(ep2.dy));
      expect(ep2.dy, equals(ep3.dy));
      // ep4 is wrapped to the next row (greater dy)
      expect(ep4.dy, greaterThan(ep1.dy));
    });

    testWidgets('Split mode video back button stays at edge when cutout is on right', (tester) async {
      tester.view.physicalSize = const Size(1024, 466);
      tester.view.devicePixelRatio = 1.0;
      _setViewInsets(tester, const FakeViewPadding(right: 64.0, left: 0.0));
      addTearDown(() {
        tester.view.resetPhysicalSize();
        _resetViewInsets(tester);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final cutout = _cutoutOf(context);
              return Scaffold(
                body: Row(
                  children: [
                    Expanded(
                      flex: 7,
                      child: VideoPlayerWidget(
                        videoUrl: 'http://example.com/test.mp4',
                        title: '测试',
                        showBack: true,
                        isFull: false,
                        edgeHud: true,
                        leftInset: cutout.left,
                        rightInset: 16.0,
                      ),
                    ),
                    const Expanded(flex: 5, child: SizedBox()),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Back icon should be near left edge (_edge(6, 0) = 6)
      final backButton = find.byIcon(Icons.arrow_back_ios_new_rounded);
      expect(backButton, findsOneWidget);
      final backButtonPos = tester.getTopLeft(backButton);
      // Container left is 6.0, icon centered in 36x36 container (6 + (36 - 18) / 2 = 15)
      expect(backButtonPos.dx, closeTo(15.0, 1.0));
    });

    testWidgets('Split mode video back button avoids cutout when cutout is on left', (tester) async {
      tester.view.physicalSize = const Size(1024, 466);
      tester.view.devicePixelRatio = 1.0;
      _setViewInsets(tester, const FakeViewPadding(left: 64.0, right: 0.0));
      addTearDown(() {
        tester.view.resetPhysicalSize();
        _resetViewInsets(tester);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final cutout = _cutoutOf(context);
              return Scaffold(
                body: Row(
                  children: [
                    Expanded(
                      flex: 7,
                      child: VideoPlayerWidget(
                        videoUrl: 'http://example.com/test.mp4',
                        title: '测试',
                        showBack: true,
                        isFull: false,
                        edgeHud: true,
                        leftInset: cutout.left,
                        rightInset: 16.0,
                      ),
                    ),
                    const Expanded(flex: 5, child: SizedBox()),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Back icon should be offset past the 64px cutout
      final backButton = find.byIcon(Icons.arrow_back_ios_new_rounded);
      expect(backButton, findsOneWidget);
      final backButtonPos = tester.getTopLeft(backButton);
      // Container left is 64.0, icon centered in 36x36 container (64 + 9 = 73)
      expect(backButtonPos.dx, closeTo(73.0, 1.0));
    });

    testWidgets('FilmRow honors left and right safe area insets via padding', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(left: 48.0, right: 36.0);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetPadding();
      });

      final testFilms = [
        MovieBasicInfo(id: 1, name: '片A'),
        MovieBasicInfo(id: 2, name: '片B'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilmRow(
              title: '推荐电影',
              films: testFilms,
              leftInset: 48.0,
              rightInset: 36.0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 标题起始位置：AppTheme.spaceLg (16) + leftInset (48) + 指示条宽与间距 (3.5 + 8) ≈ 75.5
      final titlePos = tester.getTopLeft(find.text('推荐电影'));
      expect(titlePos.dx, closeTo(16.0 + 48.0 + 3.5 + 8.0, 1.0));

      // 查看全部按钮右侧：800 - (16 + 36) = 748
      final morePos = tester.getTopRight(find.text('查看全部'));
      expect(morePos.dx, lessThanOrEqualTo(800.0 - 36.0 - 16.0));

      // 第一张卡片左侧起始位置：AppTheme.spaceLg (16) + leftInset (48) = 64
      final firstCardPos = tester.getTopLeft(find.text('片A'));
      expect(firstCardPos.dx, greaterThanOrEqualTo(64.0));
    });

    testWidgets('FilmRow with empty films renders nothing (SizedBox.shrink)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FilmRow(
              title: '演唱会',
              films: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('演唱会'), findsNothing);
      expect(find.text('暂无影片'), findsNothing);
      expect(find.byType(FilmRow), findsOneWidget);
      final size = tester.getSize(find.byType(FilmRow));
      expect(size.width, 0.0);
      expect(size.height, 0.0);
    });

    testWidgets('PlayerSkinView portrait back header has highest layer and responds to click even when error pad is active', (tester) async {
      bool backClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 225,
              child: PlayerSkinView(
                isFull: false,
                showHud: false,
                showBack: true,
                title: '测试标题',
                isPlaying: false,
                isBuffering: false,
                errorText: '视频加载失败: 403 Forbidden',
                currentPosition: Duration.zero,
                totalDuration: Duration.zero,
                onBack: () => backClicked = true,
                onTogglePlay: () {},
                onToggleFull: () {},
                onToggleMute: () {},
                onSpeed: () {},
                onRetry: () {},
                onSeekBack10: () {},
                onSeekFwd10: () {},
                onSeekTo: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 错误垫片正常展示
      expect(find.text('播放异常'), findsOneWidget);

      // 返回按钮正常可见且可点击
      final backBtn = find.byIcon(Icons.arrow_back_ios_new_rounded);
      expect(backBtn, findsOneWidget);

      await tester.tap(backBtn);
      await tester.pumpAndSettle();

      // 验证点击成功穿透/最顶层响应，而不是被错误层拦截
      expect(backClicked, isTrue);
    });

    testWidgets('PlayerSkinView fullscreen header is visible and clickable on error', (tester) async {
      bool backClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: PlayerSkinView(
                isFull: true,
                showHud: false,
                showBack: true,
                title: '全屏测试标题',
                isPlaying: false,
                isBuffering: false,
                errorText: '视频加载失败: 403 Forbidden',
                currentPosition: Duration.zero,
                totalDuration: Duration.zero,
                onBack: () => backClicked = true,
                onTogglePlay: () {},
                onToggleFull: () {},
                onToggleMute: () {},
                onSpeed: () {},
                onRetry: () {},
                onSeekBack10: () {},
                onSeekFwd10: () {},
                onSeekTo: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('播放异常'), findsOneWidget);
      expect(find.text('全屏测试标题'), findsOneWidget);

      final backBtn = find.byIcon(Icons.arrow_back_ios_new_rounded);
      expect(backBtn, findsOneWidget);

      await tester.tap(backBtn);
      await tester.pumpAndSettle();

      expect(backClicked, isTrue);
    });

    testWidgets('PlayerSkinView error prompt content stays within safe area when cutout is on left', (tester) async {
      const cutoutWidth = 64.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 300,
              child: PlayerSkinView(
                isFull: false,
                edgeHud: true,
                showHud: false,
                showBack: true,
                title: '分屏测试',
                leftInset: cutoutWidth,
                isPlaying: false,
                isBuffering: false,
                errorText: '视频加载失败: PlatformException(VideoError, Failed to load video...)',
                currentPosition: Duration.zero,
                totalDuration: Duration.zero,
                onBack: () {},
                onTogglePlay: () {},
                onToggleFull: () {},
                onToggleMute: () {},
                onSpeed: () {},
                onRetry: () {},
                onSeekBack10: () {},
                onSeekFwd10: () {},
                onSeekTo: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final errorTextFinder = find.text('视频加载失败: PlatformException(VideoError, Failed to load video...)');
      expect(errorTextFinder, findsOneWidget);

      final errorTextPos = tester.getTopLeft(errorTextFinder);
      // 必须完整避开左侧 64px 挖孔（且保留至少 16px 呼吸间距，位置应 >= 80px）
      expect(errorTextPos.dx, greaterThanOrEqualTo(cutoutWidth + 16.0));
    });

    testWidgets('PlayerSkinView does not show loading card when paused even if buffering', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 300,
              child: PlayerSkinView(
                isFull: false,
                edgeHud: false,
                showHud: true,
                showBack: true,
                title: '测试',
                isPlaying: false, // 已暂停
                isBuffering: true, // 仍处于底层缓冲中
                isOpening: false,
                currentPosition: const Duration(seconds: 10),
                totalDuration: const Duration(seconds: 60),
                onBack: () {},
                onTogglePlay: () {},
                onToggleFull: () {},
                onToggleMute: () {},
                onSpeed: () {},
                onRetry: () {},
                onSeekBack10: () {},
                onSeekFwd10: () {},
                onSeekTo: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 暂停状态下不应该显示“加载中...”或“正在打开...”
      expect(find.text('加载中...'), findsNothing);
      expect(find.text('正在打开...'), findsNothing);
      // 应该展示中心播放大按钮
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('PlayerVideoSurface displays poster in opening phase before video ready', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 300,
              child: PlayerVideoSurface(
                controller: null,
                scaleMode: PlayerScaleMode.fit,
                poster: 'https://example.com/poster.jpg',
                isOpening: true,
                isReady: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('Player Seeking and Gesture Tests', () {
    testWidgets('PlayerBottomBar dragging slider smoothly triggers callbacks without snap-back', (tester) async {
      Duration? startedAt;
      final progressUpdates = <Duration>[];
      Duration? endedAt;
      Duration? seekToAt;
      final positionNotifier = ValueNotifier<Duration>(const Duration(seconds: 10));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 100,
              child: ValueListenableBuilder<Duration>(
                valueListenable: positionNotifier,
                builder: (context, pos, _) {
                  return PlayerBottomBar(
                    isReady: true,
                    isOpening: false,
                    showHud: true,
                    errorText: '',
                    cinemaHud: false,
                    isFull: false,
                    isPlaying: true,
                    muted: false,
                    currentPosition: pos,
                    totalDuration: const Duration(seconds: 100),
                    currentSpeed: 1.0,
                    scaleLabel: '适应',
                    onTogglePlay: () {},
                    onToggleFull: () {},
                    onToggleMute: () {},
                    onSpeed: () {},
                    onSeekStart: (p) => startedAt = p,
                    onSeekProgress: (p) => progressUpdates.add(p),
                    onSeekEnd: (p) => endedAt = p,
                    onSeekTo: (p) => seekToAt = p,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);
      expect(find.text('00:10 / 01:40'), findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(sliderFinder));
      await tester.pump();

      expect(startedAt, isNotNull);

      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();

      expect(progressUpdates, isNotEmpty);

      // Updating currentPosition during drag should NOT override the dragged time
      positionNotifier.value = const Duration(seconds: 12);
      await tester.pump();

      // Still in dragging state, text is derived from drag position rather than 00:12
      expect(find.text('00:12 / 01:40'), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(endedAt, isNotNull);
      expect(seekToAt, isNotNull);
      expect(seekToAt, equals(endedAt));
    });

    test('PlayerPlaybackController drag preview and state management', () {
      final ctrl = PlayerPlaybackController();
      expect(ctrl.isDragging, isFalse);
      expect(ctrl.isSeeking, isFalse);
      expect(ctrl.playRequested, isFalse);

      ctrl.setDragPreview(const Duration(seconds: 42));
      expect(ctrl.isDragging, isTrue);
      expect(ctrl.dragPreviewPosition, const Duration(seconds: 42));
      expect(ctrl.displayPosition, const Duration(seconds: 42));

      ctrl.setDragPreview(null);
      expect(ctrl.isDragging, isFalse);
      expect(ctrl.dragPreviewPosition, isNull);

      ctrl.pauseLocal();
      expect(ctrl.playRequested, isFalse);
    });

    testWidgets('PlayerSkinView does not intercept touch gestures with center tips while playing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 300,
              child: PlayerSkinView(
                isFull: false,
                edgeHud: false,
                showHud: true,
                showBack: true,
                title: '测试',
                isPlaying: true, // 播放中
                isBuffering: false,
                isOpening: false,
                panState: const PlayerPanState(
                  kind: PlayerTipKind.seekFwd,
                  text: '00:30 (+00:15)',
                ),
                currentPosition: const Duration(seconds: 15),
                totalDuration: const Duration(seconds: 60),
                onBack: () {},
                onTogglePlay: () {},
                onToggleFull: () {},
                onToggleMute: () {},
                onSpeed: () {},
                onRetry: () {},
                onSeekBack10: () {},
                onSeekFwd10: () {},
                onSeekTo: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('00:30 (+00:15)'), findsOneWidget);

      final ignorePointers = tester.widgetList<IgnorePointer>(find.byType(IgnorePointer));
      final centerIgnore = ignorePointers.firstWhere((w) => w.ignoring == true);
      expect(centerIgnore.ignoring, isTrue);
    });

    testWidgets('PlayerGestureHandler horizontal swipe triggers onSeekProgress and onSeekEnd', (tester) async {
      Duration? progressPos;
      Duration? endedPos;
      PlayerPanState? lastPan;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: PlayerGestureHandler(
                currentPosition: const Duration(seconds: 10),
                totalDuration: const Duration(seconds: 100),
                isPlaying: true,
                isFull: false,
                onSingleTap: () {},
                onDoubleTap: () {},
                onSpeedChange: (_) {},
                onSeekProgress: (pos) => progressPos = pos,
                onSeekEnd: (pos) => endedPos = pos,
                onPanStateChange: (pan) => lastPan = pan,
                child: Container(color: Colors.black),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(300, 200));
      // First move to cross touch slop and initiate drag
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      // Second move to update drag progress
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();

      expect(progressPos, isNotNull);
      expect(lastPan?.kind, PlayerTipKind.seekFwd);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(endedPos, isNotNull);
      expect(lastPan?.kind, PlayerTipKind.none);
    });
  });

  group('DailyUpdatesTab Tests', () {
    testWidgets('DailyUpdatesTab state supports multiple tickers for refresh recreation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DailyUpdatesTab(),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(DailyUpdatesTab));
      expect(state, isA<TickerProvider>());
      final tickerProvider = state as TickerProvider;

      final ticker1 = tickerProvider.createTicker((_) {});
      final ticker2 = tickerProvider.createTicker((_) {});

      expect(ticker1, isNotNull);
      expect(ticker2, isNotNull);

      ticker1.dispose();
      ticker2.dispose();
    });

    testWidgets('VideoPlayerWidget handles episode switching without stale disposed errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoPlayerWidget(
              videoUrl: 'http://example.com/ep1.mp4',
              title: '第1集',
              isFull: true,
              reloadToken: 1,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoPlayerWidget(
              videoUrl: 'http://example.com/ep2.mp4',
              title: '第2集',
              isFull: true,
              reloadToken: 2,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('第2集'), findsOneWidget);
    });
  });

  group('SettingsPage and ProfileTab Tests', () {
    testWidgets('SettingsPage renders sections and switches properly', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('播放'), findsOneWidget);
      expect(find.text('回到桌面开启画中画'), findsOneWidget);
      expect(find.text('自动连播下一集'), findsOneWidget);
      expect(find.text('通用'), findsOneWidget);
      expect(find.text('清理本地缓存'), findsOneWidget);

      // Tap on 清理本地缓存 to open dialog
      await tester.tap(find.text('清理本地缓存'));
      await tester.pumpAndSettle();

      expect(find.text('确定清理本地缓存吗？'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('清理'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('确定清理本地缓存吗？'), findsNothing);
    });

    testWidgets('ProfileTab renders Settings menu item', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ProfileTab()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);
      expect(find.text('自定义播放'), findsOneWidget);
      expect(find.text('版本检查'), findsNothing);
    });

    testWidgets('AboutPage renders version update item and removes demo site', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(
          home: AboutPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('关于'), findsOneWidget);
      expect(find.text('版本更新'), findsOneWidget);
      expect(find.text('在线演示站点'), findsNothing);
      expect(find.text('EcoHub 开源项目'), findsOneWidget);
      expect(find.text('EcoHub for OHOS'), findsOneWidget);
      expect(find.text('EcoHub for Android'), findsOneWidget);
      expect(find.text('Telegram 交流群组'), findsOneWidget);
    });
  });
}
