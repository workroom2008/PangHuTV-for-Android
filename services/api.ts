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

  // 服务端 id 为 int64（MissAV 为 19 位），超出 JS 安全整数范围会丢精度
  // （7154237278261277233 → …278000），解析前把超长数字 id 转成字符串。
  const text = await response.text();
  const safeText = text.replace(
    /("(?:id|sourceMid|mid|dbId|rawId)"\s*:\s*)(-?\d{16,})(?=\s*[,}])/g,
    '$1"$2"'
  );
  const body = JSON.parse(safeText);
  if (body && (body.code === 0 || body.code === 1)) {
    return body.data;
  }
  throw new Error((body && body.msg) || "请求失败");
}
// endregion

// region: --- Interface Definitions ---
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
  /** 未拼 origin/token 的原始海报路径（存收藏/播放记录用，渲染时再过 processImageUrl） */
  rawPoster?: string;
  episodes: string[];
  source: string;
  source_name: string;
  class?: string;
  year: string;
  desc?: string;
  type_name?: string;
}

export interface SearchSourceTab {
  id: string;
  name: string;
  /** 该源下的命中数（"综合" tab 为总数） */
  count: number;
}

export interface SearchPageResult {
  list: SearchResult[];
  total: number;
  current: number;
  pageSize: number;
  hasMore: boolean;
  /** "综合" + 各采集源，来自响应体 sources 字段 */
  sources: SearchSourceTab[];
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
    // privateAccess 或 requireWebLogin 任一开启，/api/hls、/api/cover 都要求登录态
    //（播放器/Image 组件不带 Authorization，必须走 ?token=）
    setPrivateAccess(siteBasic.privateAccess || siteBasic.requireWebLogin);
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

  /** 海报/图片地址：相对路径拼 origin；cover/静态海报在私有化时追加 token（绝对地址同样处理） */
  processImageUrl(imageUrl: string): string {
    if (!imageUrl) return imageUrl;
    const isAbsolute = /^https?:\/\//i.test(imageUrl);
    const isCover =
      imageUrl.includes("/api/cover") || imageUrl.includes("/api/upload/pic/poster");
    if (isAbsolute) {
      if (isPrivateAccess() && isCover) {
        const token = getCachedAuthToken();
        if (token) {
          return `${imageUrl}${imageUrl.includes("?") ? "&" : "?"}token=${token}`;
        }
      }
      return imageUrl;
    }
    if (!imageUrl.startsWith("/")) return imageUrl;
    let url = `${this.baseURL}${imageUrl}`;
    if (isPrivateAccess() && isCover) {
      const token = getCachedAuthToken();
      if (token) {
        url += `${imageUrl.includes("?") ? "&" : "?"}token=${token}`;
      }
    }
    return url;
  }

  /** 热门搜索词（失败静默返回空数组） */
  async getHotKeywords(limit = 10): Promise<string[]> {
    try {
      const data = await panghuFetch(this.baseURL, `/api/hotKeywords?limit=${limit}`);
      return ((data || []) as any[]).map((w) => String(w));
    } catch {
      return [];
    }
  }

  /** 胖虎导航大类（pid=0 顶级，show 过滤）；source 限定采集源 */
  async getNavCategories(source?: string): Promise<{ pid: number; name: string }[]> {
    const url = source ? `/api/navCategory?source=${encodeURIComponent(source)}` : "/api/navCategory";
    const data = await panghuFetch(this.baseURL, url);
    return ((data || []) as any[])
      .filter((c) => c.pid === 0 && c.show !== false)
      .map((c) => ({ pid: Number(c.id), name: String(c.name ?? "") }));
  }

  /** 列表行映射（MovieBasicInfo → SearchResult） */
  mapMovieRows(list: any[]): SearchResult[] {
    const nameMap = new Map<string, string>();
    return (list || []).map((item) => this.mapMovieBasicToSearchResult(item, nameMap));
  }

  /** 每日更新 */
  async getDailyUpdates(
    pid: number,
    current: number,
    pageSize: number,
    source?: string
  ): Promise<SearchResult[]> {
    const params = new URLSearchParams({
      pid: String(pid),
      current: String(current),
      pageSize: String(pageSize),
    });
    if (source) params.set("source", source);
    const data = await panghuFetch(this.baseURL, `/api/dailyUpdates?${params.toString()}`);
    return this.mapMovieRows(data?.list || []);
  }

  /** 分类筛选页 */
  async getClassifyPage(
    pid: number,
    opts: {
      category?: string;
      area?: string;
      year?: string;
      current?: number;
      pageSize?: number;
      source?: string;
    }
  ): Promise<SearchResult[]> {
    const params = new URLSearchParams({
      Pid: String(pid),
      current: String(opts.current ?? 1),
      pageSize: String(opts.pageSize ?? 20),
    });
    if (opts.category) params.set("Category", opts.category);
    if (opts.area) params.set("Area", opts.area);
    if (opts.year) params.set("Year", opts.year);
    if (opts.source) params.set("source", opts.source);
    const data = await panghuFetch(this.baseURL, `/api/filmClassifySearch?${params.toString()}`);
    return this.mapMovieRows(data?.list || []);
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
      rawPoster: String(item.picture ?? ""),
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

  /**
   * 库存聚合搜索。
   *
   * 服务端细节（server/internal/handler/index_handler.go:234）：
   * - pageSize 默认 12、**硬上限 50**，调大无效；
   * - 响应里带 `sources: [{id,name,count}]`，是各采集源的命中数，
   *   直接用它渲染源选择器，不用再单独请求 /api/sources；
   * - `source` 传空 = 综合聚合，传具体 id = 只搜该源。
   */
  async searchByKeyword(
    q: string,
    current = 1,
    pageSize = 50,
    signal?: AbortSignal
  ): Promise<SearchPageResult> {
    const url = `/api/searchFilm?keyword=${encodeURIComponent(q)}&current=${current}&pageSize=${pageSize}`;
    const data = await panghuFetch(this.baseURL, url, { signal });
    return this.mapSearchPage(data);
  }

  /** 单源搜索（同一接口带 source 参数） */
  async searchBySource(
    q: string,
    resourceId: string,
    current = 1,
    pageSize = 50,
    signal?: AbortSignal
  ): Promise<SearchPageResult> {
    const url = `/api/searchFilm?keyword=${encodeURIComponent(q)}&source=${encodeURIComponent(resourceId)}&current=${current}&pageSize=${pageSize}`;
    const data = await panghuFetch(this.baseURL, url, { signal });
    return this.mapSearchPage(data);
  }

  private mapSearchPage(data: any): SearchPageResult {
    const nameMap = this.parseSourceNameMap(data);
    const list = ((data?.list || []) as any[]).map((item) =>
      this.mapMovieBasicToSearchResult(item, nameMap)
    );
    const page = data?.page || {};
    const total = Number(page.total ?? 0);
    const pageSize = Number(page.pageSize ?? 0) || list.length;
    const current = Number(page.current ?? 1) || 1;
    const tabs = ((data?.sources || []) as any[]).map((s) => ({
      id: String(s.id ?? ""),
      name: String(s.name ?? ""),
      count: Number(s.count ?? 0),
    }));
    return {
      list,
      total,
      current,
      pageSize,
      hasMore: pageSize > 0 && current * pageSize < total,
      sources: tabs,
    };
  }

  /** 详情 + 播放信息：detail.list 线路 → 每线路一个 SearchResult（胖虎"线路"对应 OrionTV"源"）
   *  服务端 JSON 字段（model/film.go）：detail.{id,name,picture} 顶层小写，
   *  元数据在 detail.descriptor.*（year/area/director/actor/content/blurb/cName/remarks），
   *  线路列表 detail.list[].{id,sourceId,name,linkList[].{episode,link}}。 */
  async getPlayInfoDetail(
    id: string,
    playFrom: string,
    episode: number,
    signal?: AbortSignal
  ): Promise<PlayInfoDetail> {
    const url = `/api/filmPlayInfo?id=${encodeURIComponent(id)}&playFrom=${encodeURIComponent(playFrom)}&episode=${episode}`;
    const data = await panghuFetch(this.baseURL, url, { signal });
    const d = data?.detail || {};
    const desc = d.descriptor || {};

    const rawPicture = String(d.picture ?? "");
    const videoDetail: VideoDetail = {
      id: String(d.id ?? id),
      title: d.name ?? "",
      poster: this.processImageUrl(rawPicture),
      source: String(data?.currentPlayFrom ?? playFrom ?? ""),
      source_name: String(data?.currentPlayFrom ?? playFrom ?? ""),
      desc: desc.content || desc.blurb || undefined,
      type: desc.cName || undefined,
      year: desc.year || undefined,
      area: desc.area || undefined,
      director: desc.director || undefined,
      actor: desc.actor || undefined,
      remarks: desc.remarks || undefined,
    };

    const sources: SearchResult[] = ((d.list || []) as any[])
      .map((line) => {
        const lineSourceId = String(line.id ?? line.sourceId ?? "");
        return {
          id: String(d.id ?? id),
          title: d.name ?? "",
          poster: videoDetail.poster,
          rawPoster: rawPicture,
          episodes: ((line.linkList || []) as any[]).map((l) =>
            toPlaybackUrl(String(l.link ?? ""), this.baseURL, lineSourceId)
          ),
          source: lineSourceId,
          source_name: line.name ?? "",
          year: desc.year || undefined,
          desc: videoDetail.desc,
          type_name: desc.cName || undefined,
        };
      })
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
