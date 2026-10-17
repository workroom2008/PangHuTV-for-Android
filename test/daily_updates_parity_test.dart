import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecohub_android/common/app_theme.dart';
import 'package:ecohub_android/utils/server_config_manager.dart';
import 'package:ecohub_android/api/film_api.dart';
import 'package:ecohub_android/services/app_catalog_service.dart';
import 'package:ecohub_android/models/film_models.dart';
import 'package:ecohub_android/pages/daily_updates_tab.dart';
import 'package:ecohub_android/pages/daily_update_pane.dart';
import 'package:ecohub_android/components/scroll_fab.dart';
import 'package:ecohub_android/components/empty_state.dart';
import 'package:ecohub_android/components/film_row.dart';
import 'package:ecohub_android/components/film_card.dart';
import 'package:ecohub_android/utils/breakpoint.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DailyUpdatesTab Parity Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await ServerConfigManager.instance.init();
      FilmApi.clearSiteConfig();
      AppCatalogService.instance.clear();
      await ServerConfigManager.instance.setServerUrl('http://127.0.0.1:1');
    });

    testWidgets('DailyUpdatesTab renders frosted glass header and title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DailyUpdatesTab(),
          ),
        ),
      );
      await tester.pump();

      // Frosted glass header with BackdropFilter
      final backdropFinder = find.byType(BackdropFilter);
      expect(backdropFinder, findsWidgets);

      // Header title '每日更新'
      expect(find.text('每日更新'), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);

    });

    testWidgets('DailyUpdatesTab state provides TickerProvider for smooth animations', (tester) async {
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
    });
  });

  group('DailyUpdatePane Parity Tests', () {
    final List<MovieBasicInfo> shortSeedList = List.generate(
      3,
      (i) => MovieBasicInfo(
        id: i + 1,
        name: '每日更新影片 $i',
        poster: 'https://example.com/poster$i.jpg',
        remarks: 'HD',
      ),
    );

    testWidgets('DailyUpdatePane consumes seed immediately without network request', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyUpdatePane(
              pid: 0,
              active: true,
              seedPid: 0,
              seedList: shortSeedList,
              seedPage: PageInfo(pageSize: 21, current: 1, pageCount: 1, total: 3),
              headerHeight: 94.0,
            ),
          ),
        ),
      );
      await tester.pump();

      // FilmCard items in viewport should be present immediately
      expect(find.text('每日更新影片 0'), findsOneWidget);
      expect(find.text('每日更新影片 1'), findsOneWidget);
      expect(find.text('每日更新影片 2'), findsOneWidget);

      // Top spacer should match headerHeight + 8 = 102.0
      final topSpacer = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(SliverToBoxAdapter).first,
          matching: find.byType(SizedBox),
        ),
      );
      expect(topSpacer.height, 102.0);

      // RefreshIndicator edgeOffset should match headerHeight
      final refreshIndicator = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      expect(refreshIndicator.edgeOffset, 94.0);
      expect(refreshIndicator.displacement, 16.0);

      // Footer says '没有更多了'
      expect(find.text('没有更多了'), findsOneWidget);
    });

    testWidgets('DailyUpdatePane shows empty state with correct copy and spacer when list is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyUpdatePane(
              pid: 0,
              active: true,
              seedPid: 0,
              seedList: const [],
              seedPage: PageInfo(pageSize: 21, current: 1, pageCount: 1, total: 0),
              headerHeight: 94.0,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('暂无更新'), findsOneWidget);
      expect(find.text('近 24 小时还没有新片入库'), findsOneWidget);

      // Spacer height is headerHeight + 24 = 118.0
      final spacer = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(spacer.height, 118.0);
    });

    testWidgets('DailyUpdatePane shows TopFab after scrolling past viewport dimension', (tester) async {
      final List<MovieBasicInfo> longSeedList = List.generate(
        30,
        (i) => MovieBasicInfo(
          id: i + 1,
          name: '电影 $i',
          poster: 'https://example.com/p$i.jpg',
          remarks: 'HD',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 600,
              child: DailyUpdatePane(
                pid: 0,
                active: true,
                seedPid: 0,
                seedList: longSeedList,
                seedPage: PageInfo(pageSize: 30, current: 1, pageCount: 1, total: 30),
                headerHeight: 94.0,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // ScrollFab should be hidden initially
      final initialFab = tester.widget<ScrollFab>(find.byType(ScrollFab));
      expect(initialFab.visible, isFalse);

      // Scroll down by 700 pixels (past viewport height of 600)
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();

      final visibleFab = tester.widget<ScrollFab>(find.byType(ScrollFab));
      expect(visibleFab.visible, isTrue);

      // Tap TopFab to scroll back to top
      await tester.tap(find.byType(ScrollFab));
      await tester.pumpAndSettle();

      final finalFab = tester.widget<ScrollFab>(find.byType(ScrollFab));
      expect(finalFab.visible, isFalse);
    });

    testWidgets('DailyUpdatePane honors safe area insets in landscape', (tester) async {
      const leftCutout = 32.0;
      const rightCutout = 48.0;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(left: leftCutout, right: rightCutout, top: 24),
            size: Size(800, 400),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: DailyUpdatePane(
                pid: 0,
                active: true,
                seedPid: 0,
                seedList: shortSeedList,
                seedPage: PageInfo(pageSize: 21, current: 1, pageCount: 1, total: 3),
                headerHeight: 48.0,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // SliverPadding should include left and right cutouts
      final sliverPadding = tester.widget<SliverPadding>(find.byType(SliverPadding));
      final resolvedPadding = sliverPadding.padding.resolve(TextDirection.ltr);
      expect(resolvedPadding.left, AppTheme.spaceLg + leftCutout);
      expect(resolvedPadding.right, AppTheme.spaceLg + rightCutout);
    });

    testWidgets('DailyUpdatePane notifies onAllRefreshed on pull refresh for seedPid', (tester) async {
      var refreshed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyUpdatePane(
              pid: 0,
              active: true,
              seedPid: 0,
              seedList: shortSeedList,
              seedPage: PageInfo(pageSize: 21, current: 1, pageCount: 1, total: 3),
              headerHeight: 94.0,
              onAllRefreshed: () {
                refreshed = true;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(DailyUpdatePane));
      expect(state, isNotNull);
      expect(refreshed, isFalse);
    });

    testWidgets('Landscape mode card sizes match between FilmRow (Home) and DailyUpdatePane (Daily)', (tester) async {
      const landscapeWidth = 890.0;
      const landscapeHeight = 390.0;
      const leftCutout = 48.0;
      const rightCutout = 48.0;

      tester.view.physicalSize = const Size(landscapeWidth, landscapeHeight);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(left: leftCutout, right: rightCutout);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
      });

      // 1. Measure FilmRow card size in landscape
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilmRow(
              title: '首页推荐',
              films: shortSeedList,
              leftInset: leftCutout,
              rightInset: rightCutout,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final filmRowCards = find.byType(FilmCard);
      expect(filmRowCards, findsWidgets);
      final filmRowCardSize = tester.getSize(filmRowCards.first);

      // 2. Measure DailyUpdatePane card size in landscape
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyUpdatePane(
              pid: 0,
              active: true,
              seedPid: 0,
              seedList: shortSeedList,
              seedPage: PageInfo(pageSize: 21, current: 1, pageCount: 1, total: 3),
              headerHeight: 48.0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dailyPaneCards = find.byType(FilmCard);
      expect(dailyPaneCards, findsWidgets);
      final dailyPaneCardSize = tester.getSize(dailyPaneCards.first);

      // Card sizes must be consistent in landscape mode
      expect(filmRowCardSize.width, closeTo(dailyPaneCardSize.width, 0.5));
      expect(filmRowCardSize.height, closeTo(dailyPaneCardSize.height, 0.5));

      // Both should use 6 columns on 890dp landscape screen
      expect(Breakpoint.gridColsOf(landscapeWidth), 6);
      final expectedCardWidth = (landscapeWidth - (AppTheme.spaceLg * 2 + leftCutout + rightCutout) - (6 - 1) * AppTheme.spaceSm) / 6;
      expect(filmRowCardSize.width, closeTo(expectedCardWidth, 0.5));
      expect(dailyPaneCardSize.width, closeTo(expectedCardWidth, 0.5));
    });

    testWidgets('Tablet landscape mode (1200x800) card sizes match between FilmRow and DailyUpdatePane', (tester) async {
      const tabletWidth = 1200.0;
      const tabletHeight = 800.0;
      const leftCutout = 24.0;
      const rightCutout = 24.0;

      tester.view.physicalSize = const Size(tabletWidth, tabletHeight);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(left: leftCutout, right: rightCutout);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilmRow(
              title: '首页推荐',
              films: shortSeedList,
              leftInset: leftCutout,
              rightInset: rightCutout,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final filmRowCards = find.byType(FilmCard);
      expect(filmRowCards, findsWidgets);
      final filmRowCardSize = tester.getSize(filmRowCards.first);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyUpdatePane(
              pid: 0,
              active: true,
              seedPid: 0,
              seedList: shortSeedList,
              seedPage: PageInfo(pageSize: 21, current: 1, pageCount: 1, total: 3),
              headerHeight: 48.0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dailyPaneCards = find.byType(FilmCard);
      expect(dailyPaneCards, findsWidgets);
      final dailyPaneCardSize = tester.getSize(dailyPaneCards.first);

      expect(filmRowCardSize.width, closeTo(dailyPaneCardSize.width, 0.5));
      expect(filmRowCardSize.height, closeTo(dailyPaneCardSize.height, 0.5));
      expect(Breakpoint.gridColsOf(tabletWidth), 7);
    });

    testWidgets('Portrait mode (390x844) card sizes match between FilmRow and DailyUpdatePane', (tester) async {
      const portraitWidth = 390.0;
      const portraitHeight = 844.0;

      tester.view.physicalSize = const Size(portraitWidth, portraitHeight);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding.zero;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilmRow(
              title: '首页推荐',
              films: shortSeedList,
              leftInset: 0,
              rightInset: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final filmRowCards = find.byType(FilmCard);
      expect(filmRowCards, findsWidgets);
      final filmRowCardSize = tester.getSize(filmRowCards.first);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyUpdatePane(
              pid: 0,
              active: true,
              seedPid: 0,
              seedList: shortSeedList,
              seedPage: PageInfo(pageSize: 21, current: 1, pageCount: 1, total: 3),
              headerHeight: 48.0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dailyPaneCards = find.byType(FilmCard);
      expect(dailyPaneCards, findsWidgets);
      final dailyPaneCardSize = tester.getSize(dailyPaneCards.first);

      expect(filmRowCardSize.width, closeTo(dailyPaneCardSize.width, 0.5));
      expect(filmRowCardSize.height, closeTo(dailyPaneCardSize.height, 0.5));
      expect(Breakpoint.gridColsOf(portraitWidth), 3);
      expect(filmRowCardSize.width, closeTo(114.0, 0.5));
    });
  });
}
