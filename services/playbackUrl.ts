import { Platform } from "react-native";
import { Dimensions } from "react-native";
import { getCachedAuthToken } from "./authToken";
import { isPrivateAccess } from "./api";

/**
 * 是否 TV 客户端。
 *
 * 注意不能用 Math.max(w,h) 判断：竖屏手机普遍是 750x1334 / 1080x2400，
 * max 一定 >=1024，会把手机全部误判成 TV，于是手机也带上 client=tv，
 * 服务端据此把每个分片都代理一遍 —— 手机端播极品源卡死就是这么来的。
 *
 * 这里用「短边」做断点：TV 一定是横屏大屏，短边 >=1024；
 * 手机竖屏短边 750~1080，手机横屏短边也基本 <= 800。
 * Platform.isTV 在部分 OEM Android TV（如 SHARP 6.0）上不可靠，仍需尺寸兜底。
 */
function isTVClient(): boolean {
  if (Platform.isTV) return true;
  if (Platform.OS !== "android" && Platform.OS !== "ios") return false;
  try {
    const { width, height } = Dimensions.get("window");
    return Math.min(width, height) >= 1024;
  } catch {
    return false;
  }
}

/** 内嵌外来广告分片 / 老 TV 无法直连的 CDN：走本站 /api/hls 清洗（与 web 端 hls-playback 一致） */
const HLS_SCRUB_HOST =
  /jipinvipplay|v155p|bbffvip|maoyanplay|vcsheaye|vcjuligi|fgxvqf|zhixunkeji|doudou520/i;

/** 115 / 极品 / 18AV / 51吃瓜 内置源 ID（与 server config 一致） */
const HLS_SCRUB_SOURCE_IDS = new Set(["3132827512", "1896829319", "7382916405", "3681729405"]);

function shouldScrubHls(link: string, sourceId?: string): boolean {
  const u = String(link || "");
  if (!/\.m3u8([?#]|$)/i.test(u)) return false;
  const sid = String(sourceId || "").trim();
  if (sid && HLS_SCRUB_SOURCE_IDS.has(sid)) return true;
  return HLS_SCRUB_HOST.test(u);
}

/**
 * 绝对 m3u8 先包成同源 /api/hls：由服务端代拉播放列表（带采集站 Referer/代理），
 * 避免 TV 直连第三方 CDN 时的 Referer/UA/TLS 问题；相对 /api/hls 原样返回。
 */
export function wrapHlsThroughServer(link: string, sourceId?: string): string {
  const raw = String(link || "");
  if (/\/api\/hls(?:[/?]|$)/i.test(raw)) return raw;
  if (!shouldScrubHls(raw, sourceId)) return raw;
  const params = new URLSearchParams({ url: raw });
  const sid = String(sourceId || "").trim();
  if (sid) params.set("source", sid);
  return `/api/hls?${params.toString()}`;
}

/**
 * 把胖虎返回的播放地址转成可直接交给播放器的最终地址：
 * - http(s) 直链原样返回（需清洗的 CDN 改包 /api/hls，同源 /api/hls 除外）
 * - 相对路径拼服务器 origin
 * - /api/hls 改写为 /api/hls.m3u8（便于播放器识别），私有化时追加 token
 * - TV 端追加 client=tv：老 Android TV 根证书不全，服务端据此把分片也代理下来
 */
export function toPlaybackUrl(link: string, origin: string, sourceId?: string): string {
  if (!link) return link;

  const wrapped = wrapHlsThroughServer(link, sourceId);
  const isAbsolute = /^https?:\/\//i.test(wrapped);
  let url = isAbsolute ? wrapped : wrapped.startsWith("/") ? `${origin}${wrapped}` : `${origin}/${wrapped}`;

  if (url.includes("/api/hls?")) {
    url = url.replace("/api/hls?", "/api/hls.m3u8?");
    if (isPrivateAccess()) {
      const token = getCachedAuthToken();
      if (token) {
        url += `&token=${token}`;
      }
    }
    if (isTVClient()) {
      url += `&client=tv`;
    }
  }

  return url;
}
