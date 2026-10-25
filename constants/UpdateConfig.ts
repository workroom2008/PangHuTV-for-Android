// 自更新分发仓库：形如 "owner/repo"，置空即禁用应用内自更新（自有分发就绪前保持为空）
const GITHUB_REPO_REF = "";

export const UPDATE_CONFIG = {
  // 自动检查更新
  AUTO_CHECK: true,

  // GitHub 仓库标识（由 GITHUB_REPO_REF 派生，供调用方短路判断）
  GITHUB_OWNER: GITHUB_REPO_REF.split("/")[0] || "",
  GITHUB_REPO: GITHUB_REPO_REF.split("/")[1] || "",

  // 检查更新间隔（毫秒）
  CHECK_INTERVAL: 12 * 60 * 60 * 1000, // 12小时

  // GitHub相关URL
  GITHUB_RAW_URL: GITHUB_REPO_REF
    ? `https://ghfast.top/https://raw.githubusercontent.com/${GITHUB_REPO_REF}/refs/heads/master/package.json?t=${Date.now()}`
    : "",

  // 获取平台特定的下载URL
  getDownloadUrl(version: string): string {
    return GITHUB_REPO_REF
      ? `https://ghfast.top/https://github.com/${GITHUB_REPO_REF}/releases/download/v${version}/orionTV.${version}.apk`
      : "";
  },

  // 是否显示更新日志
  SHOW_RELEASE_NOTES: true,

  // 是否允许跳过版本
  ALLOW_SKIP_VERSION: true,

  // 下载超时时间（毫秒）
  DOWNLOAD_TIMEOUT: 10 * 60 * 1000, // 10分钟

  // 是否在WIFI下自动下载
  AUTO_DOWNLOAD_ON_WIFI: false,

  // 更新通知设置
  NOTIFICATION: {
    ENABLED: true,
    TITLE: "OrionTV 更新",
    DOWNLOADING_TEXT: "正在下载新版本...",
    DOWNLOAD_COMPLETE_TEXT: "下载完成，点击安装",
  },
};
