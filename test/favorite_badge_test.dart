import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecohub_android/api/http_client.dart';
import 'package:ecohub_android/models/film_models.dart';
import 'package:ecohub_android/utils/favorite_manager.dart';
import 'package:ecohub_android/utils/format_util.dart';
import 'package:ecohub_android/utils/history_manager.dart';
import 'package:ecohub_android/utils/play_resume.dart';
import 'package:ecohub_android/utils/server_config_manager.dart';
import 'package:ecohub_android/services/auth_session.dart';
import 'package:ecohub_android/components/film_card.dart';
import 'package:ecohub_android/components/search_result_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigManager.instance.init();
    await ServerConfigManager.instance.setServerUrl('https://demo.ecohub.com');
    await FavoriteManager.clear();
  });

  test('FavoriteManager in-memory sync check and version notifier', () async {
    expect(FavoriteManager.isFavoriteSync('1001'), isFalse);
    final initialVersion = FavoriteManager.favoriteVersion.value;

    final item = FavoriteItem(
      id: '1001',
      name: '测试影片',
      picture: 'https://example.com/poster.jpg',
      cName: '动作片',
      remarks: 'HD',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await FavoriteManager.save(item);
    expect(FavoriteManager.isFavoriteSync('1001'), isTrue);
    expect(FavoriteManager.favoriteVersion.value, greaterThan(initialVersion));

    await FavoriteManager.remove('1001');
    expect(FavoriteManager.isFavoriteSync('1001'), isFalse);
  });

  testWidgets('FilmCard displays favorite badge reactively', (tester) async {
    final film = MovieBasicInfo(
      id: 2002,
      name: '收藏电影',
      cName: '科幻片',
      remarks: '超清',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilmCard(film: film),
        ),
      ),
    );

    // Initial state: not favorited, remarks visible, badge not found
    expect(find.text('超清'), findsOneWidget);
    expect(find.text('已收藏'), findsNothing);

    // Save to favorites
    await FavoriteManager.save(FavoriteItem(
      id: '2002',
      name: '收藏电影',
      picture: '',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));

    await tester.pump();

    // Both badge and remarks tag should now be visible without overlap
    expect(find.text('已收藏'), findsOneWidget);
    expect(find.text('超清'), findsOneWidget);
    final favRect = tester.getRect(find.text('已收藏'));
    final remarksRect = tester.getRect(find.text('超清'));
    expect(remarksRect.top, greaterThan(favRect.bottom));

    // Remove from favorites
    await FavoriteManager.remove('2002');
    await tester.pump();

    // Badge should disappear
    expect(find.text('已收藏'), findsNothing);
  });

  testWidgets('SearchResultItem displays favorite badge reactively', (tester) async {
    final film = MovieBasicInfo(
      id: 3003,
      name: '搜索收藏片',
      cName: '喜剧片',
      remarks: '国语',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchResultItem(film: film),
        ),
      ),
    );

    // Initial: not favorited
    expect(find.text('已收藏'), findsNothing);

    // Favorite film
    await FavoriteManager.save(FavoriteItem(
      id: '3003',
      name: '搜索收藏片',
      picture: '',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));

    await tester.pump();
    expect(find.text('已收藏'), findsOneWidget);

    // Unfavorite
    await FavoriteManager.remove('3003');
    await tester.pump();
    expect(find.text('已收藏'), findsNothing);
  });

  test('HttpClient trackView includes X-Provide-Key header when configured', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? receivedKey;
    Map<String, dynamic>? receivedBody;

    server.listen((HttpRequest req) async {
      receivedKey = req.headers.value('X-Provide-Key');
      final bodyStr = await utf8.decodeStream(req);
      receivedBody = jsonDecode(bodyStr);
      req.response.statusCode = 200;
      req.response.write('{"code":0,"msg":"ok"}');
      await req.response.close();
    });

    final serverUrl = 'http://${server.address.host}:${server.port}?key=secret123';
    await ServerConfigManager.instance.setServerUrl(serverUrl);
    await AuthSession.instance.saveToken('unit-test-token');

    HttpClient.instance.trackView('classify', '1', 'DailyUpdatesTab', '', '电影', '测试片');

    for (int i = 0; i < 20; i++) {
      if (receivedKey != null) break;
      await Future.delayed(const Duration(milliseconds: 50));
    }

    expect(receivedKey, 'secret123');
    expect(receivedBody?['resource_cat'], '电影');
    expect(receivedBody?['resource_title'], '测试片');
    await server.close(force: true);
  });

  testWidgets('Live source collection badge displays correctly via FormatUtil.filmId', (tester) async {
    final liveFilm = MovieBasicInfo(
      id: 0,
      name: '采集源电影',
      sourceId: 'ffm',
      sourceMid: 8888,
    );

    expect(FormatUtil.filmId(liveFilm), 'ffm:8888');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                FilmCard(film: liveFilm),
                SearchResultItem(film: liveFilm),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('已收藏'), findsNothing);

    await FavoriteManager.save(FavoriteItem(
      id: 'ffm:8888',
      name: '采集源电影',
      picture: '',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));

    await tester.pump();
    expect(find.text('已收藏'), findsNWidgets(2));
  });

  test('History resume retains episodeIndex even when sourceId is provided', () async {
    await HistoryManager.save(HistoryItem(
      id: '5005',
      name: '多集连续剧',
      picture: '',
      sourceId: 'ty',
      sourceName: '通用源',
      episodeIndex: 9,
      episode: '第10集',
      currentTime: 120.0,
      duration: 2400.0,
      timeStamp: DateTime.now().millisecondsSinceEpoch,
    ));

    final resume = await PlayResume.fromHistory('5005');
    expect(resume.sourceId, 'ty');
    expect(resume.episodeIndex, 9);
    expect(resume.currentTime, 120.0);
  });
}
