import { getCachedAuthToken } from "./authToken";
import { isPrivateAccess } from "./api";

/**
 * 把胖虎返回的播放地址转成可直接交给播放器的最终地址：
 * - http(s) 直链原样返回（同源 /api/hls 除外）
 * - 相对路径拼服务器 origin
 * - /api/hls 改写为 /api/hls.m3u8（便于播放器识别），私有化时追加 token
 */
export function toPlaybackUrl(link: string, origin: string): string {
  if (!link) return link;

  const isAbsolute = /^https?:\/\//i.test(link);
  let url = isAbsolute ? link : link.startsWith("/") ? `${origin}${link}` : `${origin}/${link}`;

  if (url.includes("/api/hls?")) {
    url = url.replace("/api/hls?", "/api/hls.m3u8?");
    if (isPrivateAccess()) {
      const token = getCachedAuthToken();
      if (token) {
        url += `&token=${token}`;
      }
    }
  }

  return url;
}
