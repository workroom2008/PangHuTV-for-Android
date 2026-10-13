/// 与胖虎影视服务端一致的应用品牌与自有 GitHub 仓库常量。
abstract final class AppBranding {
  static const displayName = '胖虎影视';
  static const tagline = '自托管高性能多源影视聚合系统';
  static const userAgentProduct = 'PangHuTV-App';
  static const defaultCastTitle = displayName;

  static const githubOwner = 'workroom2008';
  static const serverRepo = 'PangHuTV';
  static const androidRepo = 'PangHuTV-for-Android';

  static String githubRepoUrl(String repo) =>
      'https://github.com/$githubOwner/$repo';

  static String get serverRepoUrl => githubRepoUrl(serverRepo);

  static String get androidRepoUrl => githubRepoUrl(androidRepo);

  static String get androidReleasesLatestUrl =>
      '${androidRepoUrl}/releases/latest';

  static Uri get androidReleasesApiUri => Uri.parse(
        'https://api.github.com/repos/$githubOwner/$androidRepo/releases?per_page=10',
      );
}
