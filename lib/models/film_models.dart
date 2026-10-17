import '../common/app_branding.dart';

/// 赞赏渠道信息
class TipChannel {
  final String key;
  final String label;
  final String qrImage;
  final String link;

  TipChannel({
    required this.key,
    required this.label,
    required this.qrImage,
    required this.link,
  });
}

/// 站点基础配置
class BasicConfig {
  final String siteName;
  final String siteUrl;
  final String logo;
  final String keyword;
  final String describe;
  final bool state;
  final String hint;
  final bool tipEnabled;
  final String tipTitle;
  final String tipMessage;
  final List<TipChannel> tipChannels;
  final bool noticeEnabled;
  final String noticeTitle;
  final String noticeContent;
  final bool noticeShowInWeb;
  final bool noticeShowInApp;
  final String noticeAppVersion;
  final String noticeVersion;
  final bool privateAccess;
  final bool requireWebLogin;

  /// 与 Web `SiteGuard` 一致：私有化或全局强制 Web 登录时须账号。
  bool get loginRequired => privateAccess || requireWebLogin;

  BasicConfig({
    this.siteName = AppBranding.displayName,
    this.siteUrl = '',
    this.logo = '',
    this.keyword = '',
    this.describe = '',
    this.state = true,
    this.hint = '',
    this.tipEnabled = false,
    this.tipTitle = '赞赏支持',
    this.tipMessage = '',
    this.tipChannels = const [],
    this.noticeEnabled = false,
    this.noticeTitle = '站点公告',
    this.noticeContent = '',
    this.noticeShowInWeb = true,
    this.noticeShowInApp = true,
    this.noticeAppVersion = '',
    this.noticeVersion = '',
    this.privateAccess = false,
    this.requireWebLogin = false,
  });
}

/// 影片分类条目
class CategoryItem {
  final int id;
  final int pid;
  final String name;
  final bool show;
  final List<CategoryItem> children;

  CategoryItem({
    required this.id,
    required this.pid,
    required this.name,
    this.show = true,
    this.children = const [],
  });
}

/// 影片基础卡片信息
class MovieBasicInfo {
  final int id;
  final int cid;
  final int pid;
  final String name;
  final String subTitle;
  final String cName;
  final String state;
  final String picture;
  final String pictureSlide;
  final String poster;
  final String actor;
  final String director;
  final String blurb;
  final String remarks;
  final String area;
  final String year;
  final String language;
  final String classTag;
  final String mid;
  final String sourceId;
  final int sourceMid;

  MovieBasicInfo({
    required this.id,
    this.cid = 0,
    this.pid = 0,
    required this.name,
    this.subTitle = '',
    this.cName = '',
    this.state = '',
    this.picture = '',
    this.pictureSlide = '',
    this.poster = '',
    this.actor = '',
    this.director = '',
    this.blurb = '',
    this.remarks = '',
    this.area = '',
    this.year = '',
    this.language = '',
    this.classTag = '',
    this.mid = '',
    this.sourceId = '',
    this.sourceMid = 0,
  });
}

class SearchSourceTab {
  final String id;
  final String name;
  final int count;
  final bool loading;

  SearchSourceTab({
    required this.id,
    required this.name,
    this.count = 0,
    this.loading = false,
  });
}

/// 首页轮播海报条目
class BannerItem {
  final String id;
  final int mid;
  final String sourceId;
  final String name;
  final String year;
  final String cName;
  final String poster;
  final String picture;
  final String pictureSlide;
  final String remark;
  final String blurb;
  final String area;

  BannerItem({
    required this.id,
    required this.mid,
    this.sourceId = '',
    required this.name,
    this.year = '',
    this.cName = '',
    this.poster = '',
    this.picture = '',
    this.pictureSlide = '',
    this.remark = '',
    this.blurb = '',
    this.area = '',
  });
}

/// 首页分类区块数据
class HomeSection {
  final CategoryItem nav;
  final List<MovieBasicInfo> movies;
  final List<MovieBasicInfo> hot;

  HomeSection({
    required this.nav,
    required this.movies,
    required this.hot,
  });
}

/// 首页全量数据
class HomeData {
  final List<BannerItem> banners;
  final List<HomeSection> content;

  HomeData({
    required this.banners,
    required this.content,
  });
}

/// 分页基础元数据
class PageInfo {
  final int pageSize;
  final int current;
  final int pageCount;
  final int total;

  PageInfo({
    this.pageSize = 20,
    this.current = 1,
    this.pageCount = 1,
    this.total = 0,
  });
}

/// 每日更新分类
class DailyUpdateCategory {
  final int pid;
  final String name;
  final int count;

  DailyUpdateCategory({
    required this.pid,
    required this.name,
    required this.count,
  });
}

/// 每日更新返回结果
class DailyUpdateResult {
  final List<MovieBasicInfo> list;
  final PageInfo page;
  final List<DailyUpdateCategory> categories;

  DailyUpdateResult({
    required this.list,
    required this.page,
    required this.categories,
  });
}

/// 筛选搜索元数据
class FilterSearchMeta {
  final List<String> titles;
  final List<String> titleKeys;
  final List<String> sortList;
  final List<String> tagKeys;
  final List<List<String>> tagNames;
  final List<List<String>> tagValues;

  FilterSearchMeta({
    this.titles = const [],
    this.titleKeys = const [],
    this.sortList = const [],
    this.tagKeys = const [],
    this.tagNames = const [],
    this.tagValues = const [],
  });
}

/// 片库子分类快捷入口（对齐服务端 subNav）
class ClassifySubNavItem {
  final int id;
  final int pid;
  final String name;

  ClassifySubNavItem({
    required this.id,
    required this.pid,
    required this.name,
  });
}

/// 筛选结果
class FilterResult {
  final String titleName;
  final int titleId;
  final int resolvedPid;
  final List<ClassifySubNavItem> subNav;
  final List<MovieBasicInfo> list;
  final PageInfo page;
  final List<String> params;
  final List<String> paramKeys;
  final FilterSearchMeta search;

  FilterResult({
    required this.titleName,
    required this.titleId,
    this.resolvedPid = 0,
    this.subNav = const [],
    required this.list,
    required this.page,
    this.params = const [],
    this.paramKeys = const [],
    required this.search,
  });
}

/// 影片单集播放地址
class MovieUrlInfo {
  final String episode;
  final String link;

  MovieUrlInfo({
    required this.episode,
    required this.link,
  });

  Map<String, dynamic> toJson() => {
    'episode': episode,
    'link': link,
  };
}

/// 播放源
class PlaySource {
  final String id;
  final String sourceId;
  final String name;
  final List<MovieUrlInfo> linkList;

  PlaySource({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.linkList,
  });
}

/// 影片详情描述符
class MovieDescriptor {
  final String subTitle;
  final String cName;
  final String enName;
  final String classTag;
  final String actor;
  final String director;
  final String writer;
  final String blurb;
  final String remarks;
  final String releaseDate;
  final String area;
  final String language;
  final String year;
  final String state;
  final String updateTime;
  final String dbScore;
  final String content;

  MovieDescriptor({
    this.subTitle = '',
    this.cName = '',
    this.enName = '',
    this.classTag = '',
    this.actor = '',
    this.director = '',
    this.writer = '',
    this.blurb = '',
    this.remarks = '',
    this.releaseDate = '',
    this.area = '',
    this.language = '',
    this.year = '',
    this.state = '',
    this.updateTime = '',
    this.dbScore = '',
    this.content = '',
  });
}

/// 影片详情全量信息
class MovieDetail {
  final int id;
  final int cid;
  final int pid;
  final String name;
  final String picture;
  final String pictureSlide;
  final MovieDescriptor descriptor;
  final List<PlaySource> list;
  final int localUpdateTime;
  final int rawCid;

  MovieDetail({
    required this.id,
    this.cid = 0,
    this.pid = 0,
    required this.name,
    this.picture = '',
    this.pictureSlide = '',
    required this.descriptor,
    this.list = const [],
    this.localUpdateTime = 0,
    this.rawCid = 0,
  });
}

/// 播放初始化信息
class PlayInfo {
  final MovieDetail detail;
  final MovieUrlInfo current;
  final String currentPlayFrom;
  final int currentEpisode;

  PlayInfo({
    required this.detail,
    required this.current,
    required this.currentPlayFrom,
    required this.currentEpisode,
  });
}

/// 观看历史记录项
class HistoryItem {
  final String id;
  final String name;
  final String picture;
  final String sourceId;
  final String sourceName;
  final int episodeIndex;
  final String episode;
  final double currentTime;
  final double duration;
  final int timeStamp;

  HistoryItem({
    required this.id,
    required this.name,
    this.picture = '',
    this.sourceId = '',
    this.sourceName = '',
    this.episodeIndex = 0,
    this.episode = '',
    this.currentTime = 0,
    this.duration = 0,
    required this.timeStamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'picture': picture,
    'sourceId': sourceId,
    'sourceName': sourceName,
    'episodeIndex': episodeIndex,
    'episode': episode,
    'currentTime': currentTime,
    'duration': duration,
    'timeStamp': timeStamp,
  };

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      picture: '${json['picture'] ?? ''}',
      sourceId: '${json['sourceId'] ?? ''}',
      sourceName: '${json['sourceName'] ?? ''}',
      episodeIndex: (json['episodeIndex'] as num?)?.toInt() ?? 0,
      episode: '${json['episode'] ?? ''}',
      currentTime: (json['currentTime'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      timeStamp: (json['timeStamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// 收藏条目，对齐 OHOS `FavoriteItem`
class FavoriteItem {
  final String id;
  final String name;
  final String picture;
  final String cName;
  final String remarks;
  final String year;
  final String area;
  final String subTitle;
  final String actor;
  final String director;
  final int createdAt;

  FavoriteItem({
    required this.id,
    required this.name,
    this.picture = '',
    this.cName = '',
    this.remarks = '',
    this.year = '',
    this.area = '',
    this.subTitle = '',
    this.actor = '',
    this.director = '',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'picture': picture,
    'cName': cName,
    'remarks': remarks,
    'year': year,
    'area': area,
    'subTitle': subTitle,
    'actor': actor,
    'director': director,
    'createdAt': createdAt,
  };

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      picture: '${json['picture'] ?? ''}',
      cName: '${json['cName'] ?? ''}',
      remarks: '${json['remarks'] ?? ''}',
      year: '${json['year'] ?? ''}',
      area: '${json['area'] ?? ''}',
      subTitle: '${json['subTitle'] ?? ''}',
      actor: '${json['actor'] ?? ''}',
      director: '${json['director'] ?? ''}',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// 搜索返回结果
class SearchResult {
  final List<MovieBasicInfo> list;
  final PageInfo page;
  final List<SearchSourceTab> sources;
  final String error;

  SearchResult({
    required this.list,
    required this.page,
    this.sources = const [],
    this.error = '',
  });
}
