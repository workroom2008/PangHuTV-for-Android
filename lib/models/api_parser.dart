import '../common/app_branding.dart';
import 'film_models.dart';
import '../utils/format_util.dart';

/// 健壮 API 数据解析器
class ApiParser {
  static Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry('$k', v));
    }
    return <String, dynamic>{};
  }

  static String str(Map<String, dynamic> map, String key, [String fallback = '']) {
    final v = map[key];
    if (v == null) return fallback;
    final s = '$v'.trim();
    return s.isEmpty ? fallback : s;
  }

  static int intVal(Map<String, dynamic> map, String key, [int fallback = 0]) {
    final v = map[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final parsed = int.tryParse(v.trim());
      if (parsed != null) return parsed;
      final d = double.tryParse(v.trim());
      if (d != null) return d.toInt();
    }
    return fallback;
  }

  static double doubleVal(Map<String, dynamic> map, String key, [double fallback = 0.0]) {
    final v = map[key];
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.trim()) ?? fallback;
    }
    return fallback;
  }

  static bool boolVal(Map<String, dynamic> map, String key, [bool fallback = false]) {
    final v = map[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return fallback;
  }

  static List<dynamic> listVal(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is List) return v;
    return [];
  }

  static Map<String, dynamic> mapVal(Map<String, dynamic> map, String key) {
    return asMap(map[key]);
  }

  static MovieBasicInfo parseMovie(dynamic raw) {
    final map = asMap(raw);
    return MovieBasicInfo(
      id: intVal(map, 'id'),
      cid: intVal(map, 'cid'),
      pid: intVal(map, 'pid'),
      name: str(map, 'name'),
      subTitle: str(map, 'subTitle'),
      cName: str(map, 'cName'),
      state: str(map, 'state'),
      picture: str(map, 'picture'),
      pictureSlide: str(map, 'pictureSlide'),
      poster: str(map, 'poster'),
      actor: str(map, 'actor'),
      director: str(map, 'director'),
      blurb: str(map, 'blurb'),
      remarks: str(map, 'remarks').isNotEmpty ? str(map, 'remarks') : str(map, 'remark'),
      area: str(map, 'area'),
      year: FormatUtil.year(str(map, 'year')),
      language: str(map, 'language'),
      classTag: str(map, 'classTag'),
      mid: str(map, 'mid'),
      sourceId: str(map, 'sourceId'),
      sourceMid: intVal(map, 'sourceMid'),
    );
  }

  static List<MovieBasicInfo> parseMovies(dynamic raw) {
    if (raw is! List) return [];
    final list = <MovieBasicInfo>[];
    for (final item in raw) {
      final movie = parseMovie(item);
      if (movie.id > 0 || movie.name.isNotEmpty) {
        list.add(movie);
      }
    }
    return list;
  }

  static CategoryItem parseCategory(dynamic raw) {
    final map = asMap(raw);
    return CategoryItem(
      id: intVal(map, 'id'),
      pid: intVal(map, 'pid'),
      name: str(map, 'name'),
      show: map.containsKey('show') ? boolVal(map, 'show', true) : true,
      children: parseCategories(listVal(map, 'children')),
    );
  }

  static List<CategoryItem> parseCategories(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => parseCategory(e)).toList();
  }

  static BannerItem parseBanner(dynamic raw) {
    final map = asMap(raw);
    return BannerItem(
      id: str(map, 'id'),
      mid: intVal(map, 'mid'),
      sourceId: str(map, 'sourceId'),
      name: str(map, 'name'),
      year: FormatUtil.year(str(map, 'year')),
      cName: str(map, 'cName'),
      poster: str(map, 'poster'),
      picture: str(map, 'picture'),
      pictureSlide: str(map, 'pictureSlide'),
      remark: str(map, 'remark').isNotEmpty ? str(map, 'remark') : str(map, 'remarks'),
      blurb: str(map, 'blurb'),
      area: str(map, 'area'),
    );
  }

  static HomeData parseHome(dynamic raw) {
    final map = asMap(raw);
    final bannersRaw = listVal(map, 'banners');
    final banners = bannersRaw.map((e) => parseBanner(e)).toList();

    final contentRaw = listVal(map, 'content');
    final content = <HomeSection>[];
    for (final s in contentRaw) {
      final smap = asMap(s);
      content.add(HomeSection(
        nav: parseCategory(mapVal(smap, 'nav')),
        movies: parseMovies(listVal(smap, 'movies')),
        hot: parseMovies(listVal(smap, 'hot')),
      ));
    }
    return HomeData(banners: banners, content: content);
  }

  static PageInfo parsePage(dynamic raw) {
    final map = asMap(raw);
    return PageInfo(
      pageSize: intVal(map, 'pageSize', 20),
      current: intVal(map, 'current', 1),
      pageCount: intVal(map, 'pageCount', 1),
      total: intVal(map, 'total', 0),
    );
  }

  static DailyUpdateResult parseDailyUpdate(dynamic raw) {
    final map = asMap(raw);
    final catsRaw = listVal(map, 'categories');
    final categories = <DailyUpdateCategory>[];
    for (final c in catsRaw) {
      final cmap = asMap(c);
      categories.add(DailyUpdateCategory(
        pid: intVal(cmap, 'pid'),
        name: str(cmap, 'name'),
        count: intVal(cmap, 'count'),
      ));
    }
    return DailyUpdateResult(
      list: parseMovies(listVal(map, 'list')),
      page: parsePage(mapVal(map, 'page')),
      categories: categories,
    );
  }

  static SearchResult parseSearch(dynamic raw) {
    final map = asMap(raw);
    return SearchResult(
      list: parseMovies(listVal(map, 'list')),
      page: parsePage(mapVal(map, 'page')),
      sources: parseSearchSources(listVal(map, 'sources')),
      error: str(map, 'error'),
    );
  }

  static List<SearchSourceTab> parseSearchSources(dynamic raw) {
    if (raw is! List) return const [];
    final tabs = <SearchSourceTab>[];
    for (final item in raw) {
      final map = asMap(item);
      tabs.add(SearchSourceTab(
        id: str(map, 'id'),
        name: str(map, 'name'),
        count: intVal(map, 'count'),
      ));
    }
    return tabs;
  }

  static FilterResult parseFilter(dynamic raw) {
    final map = asMap(raw);
    final titleObj = mapVal(map, 'title');
    final paramsObj = mapVal(map, 'params');
    final paramKeys = paramsObj.keys.toList();
    final params = paramKeys.map((k) => str(paramsObj, k)).toList();

    final searchObj = mapVal(map, 'search');
    final titlesObj = mapVal(searchObj, 'titles');
    final titleKeys = titlesObj.keys.toList();
    final titles = titleKeys.map((k) => str(titlesObj, k)).toList();

    final sortRaw = listVal(searchObj, 'sortList');
    final sortList = sortRaw.map((e) => '$e').toList();

    final tagsObj = mapVal(searchObj, 'tags');
    final tagKeys = tagsObj.keys.map((k) => k.toString()).toList();
    final tagNames = <List<String>>[];
    final tagValues = <List<String>>[];
    for (final k in tagKeys) {
      final tags = listVal(tagsObj, k);
      final names = <String>[];
      final values = <String>[];
      for (final t in tags) {
        final tmap = asMap(t);
        names.add(str(tmap, 'Name', str(tmap, 'name', str(tmap, 'n'))));
        values.add(str(tmap, 'Value', str(tmap, 'value', str(tmap, 'v'))));
      }
      tagNames.add(names);
      tagValues.add(values);
    }

    final searchMeta = FilterSearchMeta(
      titles: titles,
      titleKeys: titleKeys,
      sortList: sortList,
      tagKeys: tagKeys,
      tagNames: tagNames,
      tagValues: tagValues,
    );

    return FilterResult(
      titleName: str(titleObj, 'name', '全部'),
      titleId: intVal(titleObj, 'id'),
      list: parseMovies(listVal(map, 'list')),
      page: parsePage(mapVal(map, 'page')),
      params: params,
      paramKeys: paramKeys,
      search: searchMeta,
    );
  }

  static String _first(Iterable<String> values) {
    for (final v in values) {
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static const _scoreKeys = [
    'dbScore',
    'score',
    'doubanScore',
    'douban_score',
    'vod_douban_score',
    'vod_score',
  ];

  static PlayInfo parsePlay(dynamic raw) {
    final map = asMap(raw);
    final detailObj = mapVal(map, 'detail');
    final descObj = mapVal(detailObj, 'descriptor');
    final descriptor = MovieDescriptor(
      subTitle: _first([str(descObj, 'subTitle'), str(detailObj, 'subTitle')]),
      cName: _first([str(descObj, 'cName'), str(detailObj, 'cName'), str(detailObj, 'typeName')]),
      enName: _first([str(descObj, 'enName'), str(detailObj, 'enName')]),
      classTag: _first([str(descObj, 'classTag'), str(detailObj, 'classTag')]),
      actor: _first([str(descObj, 'actor'), str(detailObj, 'actor')]),
      director: _first([str(descObj, 'director'), str(detailObj, 'director')]),
      writer: _first([str(descObj, 'writer'), str(detailObj, 'writer')]),
      blurb: _first([str(descObj, 'blurb'), str(detailObj, 'blurb')]),
      remarks: _first([
        str(descObj, 'remarks'),
        str(detailObj, 'remarks'),
        str(descObj, 'remark'),
        str(detailObj, 'remark'),
      ]),
      releaseDate: _first([str(descObj, 'releaseDate'), str(detailObj, 'releaseDate')]),
      area: _first([str(descObj, 'area'), str(detailObj, 'area')]),
      language: _first([str(descObj, 'language'), str(detailObj, 'language')]),
      year: FormatUtil.year(_first([str(descObj, 'year'), str(detailObj, 'year')])),
      state: _first([str(descObj, 'state'), str(detailObj, 'state')]),
      updateTime: _first([str(descObj, 'updateTime'), str(detailObj, 'updateTime')]),
      dbScore: _first([
        ..._scoreKeys.map((k) => str(descObj, k)),
        ..._scoreKeys.map((k) => str(detailObj, k)),
      ]),
      content: _first([
        str(descObj, 'content'),
        str(detailObj, 'content'),
        str(descObj, 'blurb'),
        str(detailObj, 'blurb'),
      ]),
    );

    final sourceRaw = listVal(detailObj, 'list');
    final sources = <PlaySource>[];
    for (final s in sourceRaw) {
      final sObj = asMap(s);
      final linkRaw = listVal(sObj, 'linkList');
      final links = <MovieUrlInfo>[];
      for (final l in linkRaw) {
        final lObj = asMap(l);
        final ep = str(lObj, 'episode');
        final link = str(lObj, 'link');
        if (link.isNotEmpty) {
          links.add(MovieUrlInfo(episode: ep, link: link));
        }
      }
      sources.add(PlaySource(
        id: str(sObj, 'id'),
        sourceId: str(sObj, 'sourceId'),
        name: str(sObj, 'name', '默认源'),
        linkList: links,
      ));
    }

    final detail = MovieDetail(
      id: intVal(detailObj, 'id'),
      cid: intVal(detailObj, 'cid'),
      pid: intVal(detailObj, 'pid'),
      name: str(detailObj, 'name'),
      picture: str(detailObj, 'picture'),
      pictureSlide: str(detailObj, 'pictureSlide'),
      descriptor: descriptor,
      list: sources,
      localUpdateTime: intVal(detailObj, 'localUpdateTime'),
      rawCid: intVal(detailObj, 'rawCid') > 0 ? intVal(detailObj, 'rawCid') : intVal(detailObj, 'cid'),
    );

    final currentObj = mapVal(map, 'current');
    final current = MovieUrlInfo(
      episode: str(currentObj, 'episode'),
      link: str(currentObj, 'link'),
    );

    return PlayInfo(
      detail: detail,
      current: current,
      currentPlayFrom: str(map, 'currentPlayFrom'),
      currentEpisode: intVal(map, 'currentEpisode'),
    );
  }

  static BasicConfig parseBasicConfig(dynamic raw) {
    final map = asMap(raw);
    final tip = mapVal(map, 'tip');
    final notice = mapVal(map, 'notice');
    final channelRaw = listVal(tip, 'channels');
    final channels = <TipChannel>[];
    for (final c in channelRaw) {
      final cmap = asMap(c);
      channels.add(TipChannel(
        key: str(cmap, 'key'),
        label: str(cmap, 'label'),
        qrImage: str(cmap, 'qrImage'),
        link: str(cmap, 'link'),
      ));
    }

    final appVer = str(notice, 'appVersion').isNotEmpty ? str(notice, 'appVersion') : str(notice, 'version');

    return BasicConfig(
      siteName: str(map, 'siteName', AppBranding.displayName),
      siteUrl: str(map, 'siteUrl'),
      logo: str(map, 'logo'),
      keyword: str(map, 'keyword'),
      describe: str(map, 'describe'),
      state: map.containsKey('state') ? boolVal(map, 'state', true) : true,
      hint: str(map, 'hint', '网站升级中, 暂时无法访问'),
      tipEnabled: boolVal(tip, 'enabled'),
      tipTitle: str(tip, 'title', '赞赏支持'),
      tipMessage: str(tip, 'message'),
      tipChannels: channels,
      noticeEnabled: boolVal(notice, 'enabled'),
      noticeTitle: str(notice, 'title', '站点公告'),
      noticeContent: str(notice, 'content'),
      noticeShowInWeb: notice.containsKey('showInWeb') ? boolVal(notice, 'showInWeb', true) : true,
      noticeShowInApp: notice.containsKey('showInApp') ? boolVal(notice, 'showInApp', true) : true,
      noticeAppVersion: appVer,
      noticeVersion: appVer,
    );
  }

  static List<String> parseStringList(dynamic raw) {
    if (raw is! List) return [];
    final list = <String>[];
    for (final item in raw) {
      final s = '$item'.trim();
      if (s.isNotEmpty) list.add(s);
    }
    return list;
  }
}
