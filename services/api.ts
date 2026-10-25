import AsyncStorage from "@react-native-async-storage/async-storage";
import {
  getAuthToken,
  getCachedAuthToken,
  setAuthToken,
  clearAuthToken,
  setServerFlags,
  clearServerFlags,
} from "./authToken";
import { toPlaybackUrl } from "./playbackUrl";

// region: --- 胖虎请求基座 ---
// 会话恢复回调（由 authStore 注册），401 时自动重登并重试一次
let sessionRestorer: (() => Promise<boolean>) | null = null;

export function setSessionRestorer(restorer: (() => Promise<boolean>) | null) {
  sessionRestorer = restorer;
}

// 私有化开关的同步镜像（getSiteBasic 成功后更新，供 URL 构造函数同步取用）
let privateAccess = false;

export function isPrivateAccess(): boolean {
  return privateAccess;
}

export function setPrivateAccess(v: boolean): void {
  privateAccess = v;
}

/**
 * 胖虎统一请求：Bearer 鉴权 + {code,data,msg} 包裹解析 + X-Auth-Token 续签 + 401 重登重试。
 * 判成败先看 HTTP 状态码（401/403 非 200），再看 code（0|1 成功）。
 */
export async function panghuFetch(
  baseURL: string,
  path: string,
  options: RequestInit = {}
): Promise<any> {
  if (!baseURL) {
    throw new Error("API_URL_NOT_SET");
  }

  const request = async (): Promise<Response> => {
    const headers: Record<string, string> = {
      ...((options.headers as Record<string, string>) || {}),
    };
    const token = await getAuthToken();
    if (token) {
      headers.Authorization = `Bearer ${token}`;
    }
    return fetch(`${baseURL}${path}`, { ...options, headers });
  };

  let response = await request();

  if (response.status === 401 && sessionRestorer && !path.startsWith("/api/login")) {
    const restored = await sessionRestorer();
    if (restored) {
      response = await request();
    }
  }

  // 服务端 JWT 过期但会话有效时经 X-Auth-Token 下发续签 token
  const refreshed = response.headers?.get?.("X-Auth-Token");
  if (refreshed) {
    await setAuthToken(refreshed);
  }

  if (response.status === 401) {
    throw new Error("UNAUTHORIZED");
  }
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }

  const body = await response.json();
  if (body && (body.code === 0 || body.code === 1)) {
    return body.data;
  }
  throw new Error((body && body.msg) || "请求失败");
}
// endregion

// region: --- Interface Definitions ---
export interface DoubanItem {
  title: string;
  poster: string;
  rate?: string;
}

export interface DoubanResponse {
  code: number;
  message: string;
  list: DoubanItem[];
}

export interface VideoDetail {
  id: string;
  title: string;
  poster: string;
  source: string;
  source_name: string;
  desc?: string;
  type?: string;
  year?: string;
  area?: string;
  director?: string;
  actor?: string;
  remarks?: string;
}

export interface SearchResult {
  id: string;
  title: string;
  poster: string;
  episodes: string[];
  source: string;
  source_name: string;
  class?: string;
  year: string;
  desc?: string;
  type_name?: string;
}

export interface PlayInfoDetail {
  detail: VideoDetail;
  sources: SearchResult[];
  currentSource: string;
  currentEpisode: number;
  relate: SearchResult[];
}

export interface Favorite {
  cover: string;
  title: string;
  source_name: string;
  total_episodes: number;
  search_title: string;
  year: string;
  save_time?: number;
}

export interface PlayRecord {
  title: string;
  source_name: string;
  cover: string;
  index: number;
  total_episodes: number;
  play_time: number;
  total_time: number;
  save_time: number;
  year: string;
}

export interface ApiSite {
  key: string;
  api: string;
  name: string;
  detail?: string;
}

export interface SiteBasic {
  siteName: string;
  privateAccess: boolean;
  requireWebLogin: boolean;
}

export interface SessionStatus {
  authenticated: boolean;
  licenseEnforced: boolean;
  licensed: boolean;
  requireWebLogin: boolean;
}

export class API {
  public baseURL: string = "";

  // 会话恢复回调（由 authStore 注册），401 时自动重登并重试一次
  private sessionRestorer: (() => Promise<boolean>) | null = null;

  constructor(baseURL?: string) {
    if (baseURL) {
      this.baseURL = baseURL;
    }
  }

  public setBaseUrl(url: string) {
    this.baseURL = url;
  }

  public setSessionRestorer(restorer: (() => Promise<boolean>) | null) {
    setSessionRestorer(restorer);
    this.sessionRestorer = restorer;
  }

  private async _fetch(url: string, options: RequestInit = {}): Promise<Response> {
    if (!this.baseURL) {
      throw new Error("API_URL_NOT_SET");
    }

    // 框架默认会携带 cookie，无需手动设置
    const response = await fetch(`${this.baseURL}${url}`, options);

    if (response.status === 401) {
      // 会话过期：自动重登后重试一次（登录接口本身除外，避免循环）
      if (this.sessionRestorer && !url.startsWith("/api/login")) {
        const restored = await this.sessionRestorer();
        if (restored) {
          const retryResponse = await fetch(`${this.baseURL}${url}`, options);
          if (retryResponse.status === 401) {
            throw new Error("UNAUTHORIZED");
          }
          if (!retryResponse.ok) {
            throw new Error(`HTTP error! status: ${retryResponse.status}`);
          }
          return retryResponse;
        }
      }
      throw new Error("UNAUTHORIZED");
    }

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    return response;
  }

  async login(username: string, password: string): Promise<{ ok: boolean }> {
    const data = await panghuFetch(this.baseURL, "/api/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    });
    if (!data?.token) {
      throw new Error("登录响应缺少 token");
    }
    await setAuthToken(data.token);
    return { ok: true };
  }

  async logout(): Promise<{ ok: boolean }> {
    try {
      await panghuFetch(this.baseURL, "/api/logout", { method: "POST" });
    } finally {
      await clearAuthToken();
      await clearServerFlags();
      setPrivateAccess(false);
    }
    return { ok: true };
  }

  /** 站点基础配置（免登录），并同步私有化开关 */
  async getSiteBasic(): Promise<SiteBasic> {
    const data = await panghuFetch(this.baseURL, "/api/config/basic");
    const siteBasic: SiteBasic = {
      siteName: data?.siteName ?? "",
      privateAccess: !!data?.privateAccess,
      requireWebLogin: !!data?.requireWebLogin,
    };
    setPrivateAccess(siteBasic.privateAccess);
    await setServerFlags({
      privateAccess: siteBasic.privateAccess,
      requireWebLogin: siteBasic.requireWebLogin,
    });
    return siteBasic;
  }

  /** 登录/授权门禁探测（免登录，带 token 则校验） */
  async getSessionStatus(): Promise<SessionStatus> {
    return panghuFetch(this.baseURL, "/api/session/status");
  }

  /** 海报/图片地址：相对路径拼 origin；cover/静态海报在私有化时追加 token */
  processImageUrl(imageUrl: string): string {
    if (!imageUrl || /^https?:\/\//i.test(imageUrl) || !imageUrl.startsWith("/")) {
      return imageUrl;
    }
    let url = `${this.baseURL}${imageUrl}`;
    if (
      isPrivateAccess() &&
      (imageUrl.startsWith("/api/cover") || imageUrl.startsWith("/api/upload/pic/poster"))
    ) {
      const token = getCachedAuthToken();
      if (token) {
        url += `${imageUrl.includes("?") ? "&" : "?"}token=${token}`;
      }
    }
    return url;
  }

  /** 豆瓣数据（Task 5 换成胖虎首页后删除） */
  async getDoubanData(
    type: "movie" | "tv",
    tag: string,
    pageSize: number = 16,
    pageStart: number = 0
  ): Promise<DoubanResponse> {
    const url = `/api/douban?type=${type}&tag=${encodeURIComponent(tag)}&pageSize=${pageSize}&pageStart=${pageStart}`;
    const data = await panghuFetch(this.baseURL, url, {});
    return data as DoubanResponse;
  }

  /** 启用采集源列表 */
  async getApiSources(signal?: AbortSignal): Promise<ApiSite[]> {
    const data = await panghuFetch(this.baseURL, "/api/sources", { signal });
    return (data || []).map((s: any) => ({ key: String(s.id), api: "", name: s.name ?? "" }));
  }

  private mapMovieBasicToSearchResult(item: any, sourceNameMap: Map<string, string>): SearchResult {
    const sourceId = String(item.sourceId ?? "");
    return {
      id: String(item.id),
      title: item.name ?? "",
      poster: this.processImageUrl(item.picture ?? ""),
      episodes: [],
      source: sourceId,
      source_name: sourceNameMap.get(sourceId) ?? sourceId,
      year: String(item.year ?? ""),
      desc: item.blurb || undefined,
      type_name: item.cName || undefined,
    };
  }

  private parseSourceNameMap(data: any): Map<string, string> {
    return new Map<string, string>(
      ((data?.sources || []) as any[]).map((s) => [String(s.id), String(s.name ?? "")])
    );
  }

  /** 库存聚合搜索 */
  async searchByKeyword(
    q: string,
    current = 1,
    pageSize = 50,
    signal?: AbortSignal
  ): Promise<SearchResult[]> {
    const url = `/api/searchFilm?keyword=${encodeURIComponent(q)}&current=${current}&pageSize=${pageSize}`;
    const data = await panghuFetch(this.baseURL, url, { signal });
    const nameMap = this.parseSourceNameMap(data);
    return ((data?.list || []) as any[]).map((item) => this.mapMovieBasicToSearchResult(item, nameMap));
  }

  /** 单源库存搜索 */
  async searchBySource(
    q: string,
    resourceId: string,
    signal?: AbortSignal
  ): Promise<SearchResult[]> {
    const url = `/api/searchFilm?keyword=${encodeURIComponent(q)}&source=${encodeURIComponent(resourceId)}&current=1&pageSize=50`;
    const data = await panghuFetch(this.baseURL, url, { signal });
    const nameMap = this.parseSourceNameMap(data);
    return ((data?.list || []) as any[]).map((item) => this.mapMovieBasicToSearchResult(item, nameMap));
  }

  /** 详情 + 播放信息：detail.List 线路 → 每线路一个 SearchResult（胖虎"线路"对应 OrionTV"源"） */
  async getPlayInfoDetail(
    id: string,
    playFrom: string,
    episode: number,
    signal?: AbortSignal
  ): Promise<PlayInfoDetail> {
    const url = `/api/filmPlayInfo?id=${encodeURIComponent(id)}&playFrom=${encodeURIComponent(playFrom)}&episode=${episode}`;
    const data = await panghuFetch(this.baseURL, url, { signal });
    const d = data?.detail || {};

    const videoDetail: VideoDetail = {
      id: String(d.Id ?? id),
      title: d.Name ?? "",
      poster: this.processImageUrl(d.Picture ?? ""),
      source: String(data?.currentPlayFrom ?? playFrom ?? ""),
      source_name: String(data?.currentPlayFrom ?? playFrom ?? ""),
      desc: d.Content || d.Blurb || undefined,
      type: d.CName || undefined,
      year: d.Year || undefined,
      area: d.Area || undefined,
      director: d.Director || undefined,
      actor: d.Actor || undefined,
      remarks: d.Remarks || undefined,
    };

    const sources: SearchResult[] = ((d.List || []) as any[])
      .map((line) => ({
        id: String(d.Id ?? id),
        title: d.Name ?? "",
        poster: videoDetail.poster,
        episodes: ((line.LinkList || []) as any[]).map((l) =>
          toPlaybackUrl(String(l.link ?? ""), this.baseURL)
        ),
        source: String(line.Id ?? line.SourceId ?? ""),
        source_name: line.Name ?? "",
        year: d.Year || undefined,
        desc: videoDetail.desc,
        type_name: d.CName || undefined,
      }))
      .filter((s) => !!s.source);

    if (playFrom) {
      sources.sort((a, b) => Number(b.source === playFrom) - Number(a.source === playFrom));
    }

    const relateNameMap = new Map<string, string>();
    const relate = ((data?.relate || []) as any[]).map((item) =>
      this.mapMovieBasicToSearchResult(item, relateNameMap)
    );

    return {
      detail: videoDetail,
      sources,
      currentSource: String(data?.currentPlayFrom ?? ""),
      currentEpisode: Number(data?.currentEpisode ?? 0),
      relate,
    };
  }
}

// 默认实例
export let api = new API();
