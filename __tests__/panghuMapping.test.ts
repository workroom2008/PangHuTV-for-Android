jest.mock("@react-native-async-storage/async-storage", () =>
  require("@react-native-async-storage/async-storage/jest/async-storage-mock")
);

import { api, panghuFetch, setPrivateAccess, isPrivateAccess } from "../services/api";
import { toPlaybackUrl } from "../services/playbackUrl";
import { setAuthToken, clearAuthToken } from "../services/authToken";

const jsonResponse = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const MOVIE_BASIC = {
  id: 101,
  name: "庆余年",
  picture: "/api/cover?url=p.jpg&source=src1",
  sourceId: "src1",
  year: "2024",
  remarks: "更新至36集",
  cName: "剧情",
};

describe("胖虎接口映射", () => {
  beforeEach(() => {
    api.setBaseUrl("http://s");
    setPrivateAccess(false);
    global.fetch = jest.fn();
  });

  describe("getSiteBasic", () => {
    it("requireWebLogin:true 也视为需 token（播放/海报走 ?token=）", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(
        jsonResponse({
          code: 0,
          data: { siteName: "胖虎影视", privateAccess: false, requireWebLogin: true },
          msg: "ok",
        })
      );
      await api.getSiteBasic();
      expect(isPrivateAccess()).toBe(true);
      setPrivateAccess(false);
    });
  });

  describe("processImageUrl", () => {
    it("绝对地址原样返回", () => {
      expect(api.processImageUrl("http://x/p.jpg")).toBe("http://x/p.jpg");
    });

    it("相对路径拼 origin", () => {
      expect(api.processImageUrl("/api/cover?url=p.jpg&source=src1")).toBe(
        "http://s/api/cover?url=p.jpg&source=src1"
      );
    });

    it("私有化时 cover 代理追加 token", async () => {
      await setAuthToken("jwt-t");
      setPrivateAccess(true);
      expect(api.processImageUrl("/api/cover?url=p.jpg&source=src1")).toBe(
        "http://s/api/cover?url=p.jpg&source=src1&token=jwt-t"
      );
    });

    it("私有化时绝对地址 cover 也追加 token", async () => {
      await setAuthToken("jwt-t");
      setPrivateAccess(true);
      expect(api.processImageUrl("http://s/api/cover?url=p.jpg&source=src1")).toBe(
        "http://s/api/cover?url=p.jpg&source=src1&token=jwt-t"
      );
    });
  });

  describe("toPlaybackUrl", () => {
    it("直链原样返回", () => {
      expect(toPlaybackUrl("http://x/v.m3u8", "http://s")).toBe("http://x/v.m3u8");
    });

    it("相对直链拼 origin", () => {
      expect(toPlaybackUrl("/v/1.mp4", "http://s")).toBe("http://s/v/1.mp4");
    });

    it("/api/hls 改写为 /api/hls.m3u8（手机尺寸不追加 client=tv）", () => {
      // jest 默认窗口 750x1334（竖屏手机）：短边 <1024，不是 TV
      expect(toPlaybackUrl("/api/hls?url=a.m3u8&source=src1", "http://s")).toBe(
        "http://s/api/hls.m3u8?url=a.m3u8&source=src1"
      );
    });

    it("私有化时 hls 追加 token（手机尺寸不追加 client=tv）", async () => {
      await setAuthToken("jwt-t");
      setPrivateAccess(true);
      expect(toPlaybackUrl("/api/hls?url=a.m3u8&source=src1", "http://s")).toBe(
        "http://s/api/hls.m3u8?url=a.m3u8&source=src1&token=jwt-t"
      );
    });

    it("私有化时绝对地址 hls 也改写并追加 token（手机尺寸不追加 client=tv）", async () => {
      await setAuthToken("jwt-t");
      setPrivateAccess(true);
      expect(toPlaybackUrl("http://s/api/hls?url=a.m3u8&source=src1", "http://s")).toBe(
        "http://s/api/hls.m3u8?url=a.m3u8&source=src1&token=jwt-t"
      );
    });

    describe("TV 尺寸（短边 >=1024）追加 client=tv", () => {
      const { Dimensions } = require("react-native");
      const original = Dimensions.get;
      beforeEach(() => {
        // TV 一定是横屏大屏：1920x1080，短边 1080
        (Dimensions as any).get = () => ({ width: 1920, height: 1080, scale: 1, fontScale: 1 });
      });
      afterEach(() => {
        (Dimensions as any).get = original;
      });

      it("改写为 /api/hls.m3u8 并带 client=tv", () => {
        expect(toPlaybackUrl("/api/hls?url=a.m3u8&source=src1", "http://s")).toBe(
          "http://s/api/hls.m3u8?url=a.m3u8&source=src1&client=tv"
        );
      });
    });
  });

  describe("searchByKeyword", () => {
    it("searchFilm list → SearchResult（poster 已处理、episodes 置空、source_name 由 sources 解析）", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(
        jsonResponse({
          code: 0,
          data: {
            list: [MOVIE_BASIC],
            page: {},
            sources: [{ id: "src1", name: "源A", count: 1 }],
          },
          msg: "ok",
        })
      );

      const page = await api.searchByKeyword("庆余年");
      expect(page.list).toHaveLength(1);
      const r = page.list[0];
      expect(r.id).toBe("101");
      expect(r.title).toBe("庆余年");
      expect(r.source).toBe("src1");
      expect(r.source_name).toBe("源A");
      expect(r.episodes).toEqual([]);
      expect(r.poster).toBe("http://s/api/cover?url=p.jpg&source=src1");
      expect(r.year).toBe("2024");
    });

    it("searchBySource 带 source 参数", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(
        jsonResponse({ code: 0, data: { list: [], sources: [] }, msg: "ok" })
      );
      await api.searchBySource("庆余年", "src1");
      const url = (global.fetch as jest.Mock).mock.calls[0][0];
      expect(url).toContain("/api/searchFilm?");
      expect(url).toContain("keyword=");
      expect(url).toContain("source=src1");
    });
  });

  describe("getPlayInfoDetail", () => {
    // fixture 严格对照服务端真实 JSON（MovieDetailVo：id/name/picture 顶层小写，
    // 元数据在 descriptor.* 嵌套，线路列表 list[].{id,name,linkList[].link} 小写）
    const PLAY_INFO = {
      code: 0,
      msg: "ok",
      data: {
        detail: {
          id: 101,
          name: "庆余年",
          picture: "/api/cover?url=p.jpg&source=src1",
          descriptor: {
            year: "2024",
            area: "内地",
            director: "导演甲",
            actor: "演员乙",
            content: "简介内容",
            blurb: "简短简介",
            cName: "剧情",
            remarks: "更新至36集",
          },
        },
        current: { episode: 0, link: "http://s/api/hls.m3u8?url=1" },
        currentPlayFrom: "src1",
        currentEpisode: 0,
        relate: [],
      },
    };

    const DETAIL_WITH_LINKS = {
      ...PLAY_INFO,
      data: {
        ...PLAY_INFO.data,
        detail: {
          ...PLAY_INFO.data.detail,
          list: [
            {
              id: "src2",
              sourceId: "src2",
              name: "线路B",
              linkList: [{ episode: "1", link: "http://y/1.m3u8" }],
            },
            {
              id: "src1",
              sourceId: "src1",
              name: "线路A",
              linkList: [
                { episode: "1", link: "/api/hls?url=1&source=src1" },
                { episode: "2", link: "http://x/2.m3u8" },
                { episode: "3", link: "/api/hls?url=3&source=src1" },
              ],
            },
          ],
        },
      },
    };

    it("detail.list 线路 → sources（每线路一个 SearchResult，episodes 经 toPlaybackUrl）", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(jsonResponse(DETAIL_WITH_LINKS));

      const info = await api.getPlayInfoDetail("101", "src1", 0);
      expect(info.sources).toHaveLength(2);
      const lineA = info.sources.find((s) => s.source === "src1")!;
      expect(lineA.source_name).toBe("线路A");
      expect(lineA.episodes).toHaveLength(3);
      expect(lineA.episodes[0]).toBe("http://s/api/hls.m3u8?url=1&source=src1");
      expect(lineA.episodes[1]).toBe("http://x/2.m3u8");
      expect(info.detail.title).toBe("庆余年");
      expect(info.detail.year).toBe("2024");
      expect(info.detail.desc).toBe("简介内容");
      expect(info.detail.remarks).toBe("更新至36集");
      expect(info.currentSource).toBe("src1");
    });

    it("preferred 线路排首位", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(jsonResponse(DETAIL_WITH_LINKS));

      const info = await api.getPlayInfoDetail("101", "src1", 0);
      expect(info.sources[0].source).toBe("src1");
    });

    it("sources 携带 rawPoster（未拼 origin/token 的原始路径）", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(jsonResponse(DETAIL_WITH_LINKS));

      const info = await api.getPlayInfoDetail("101", "src1", 0);
      expect(info.sources[0].rawPoster).toBe("/api/cover?url=p.jpg&source=src1");
    });

    it("请求参数包含 id/playFrom/episode", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(jsonResponse(PLAY_INFO));
      await api.getPlayInfoDetail("101", "src1", 2);
      const url = (global.fetch as jest.Mock).mock.calls[0][0];
      expect(url).toContain("/api/filmPlayInfo?");
      expect(url).toContain("id=101");
      expect(url).toContain("playFrom=src1");
      expect(url).toContain("episode=2");
    });
  });

  describe("mapMovieRows", () => {
    it("MovieBasicInfo → SearchResult 行（poster 处理/sourceId/year）", () => {
      const rows = api.mapMovieRows([MOVIE_BASIC]);
      expect(rows).toHaveLength(1);
      expect(rows[0].id).toBe("101");
      expect(rows[0].source).toBe("src1");
      expect(rows[0].poster).toBe("http://s/api/cover?url=p.jpg&source=src1");
      expect(rows[0].year).toBe("2024");
      expect(rows[0].episodes).toEqual([]);
    });
  });

  describe("getApiSources", () => {
    it("/api/sources → ApiSite[]", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(
        jsonResponse({ code: 0, data: [{ id: "src1", name: "源A" }], msg: "ok" })
      );
      const sites = await api.getApiSources();
      expect(sites).toEqual([{ key: "src1", api: "", name: "源A" }]);
    });
  });

  describe("按源查询", () => {
    it("getNavCategories 带 source 参数", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(jsonResponse({ code: 0, data: [], msg: "ok" }));
      await api.getNavCategories("md2020");
      const url = (global.fetch as jest.Mock).mock.calls[0][0];
      expect(url).toContain("/api/navCategory?source=md2020");
    });

    it("getDailyUpdates 带 source 参数", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(
        jsonResponse({ code: 0, data: { list: [] }, msg: "ok" })
      );
      await api.getDailyUpdates(0, 1, 20, "md2020");
      const url = (global.fetch as jest.Mock).mock.calls[0][0];
      expect(url).toContain("/api/dailyUpdates?");
      expect(url).toContain("source=md2020");
    });

    it("getClassifyPage 带 source 参数", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(
        jsonResponse({ code: 0, data: { list: [] }, msg: "ok" })
      );
      await api.getClassifyPage(6, { current: 1, source: "md2020" });
      const url = (global.fetch as jest.Mock).mock.calls[0][0];
      expect(url).toContain("/api/filmClassifySearch?");
      expect(url).toContain("source=md2020");
    });
  });

  it("panghuFetch 仍可用于底层调用", async () => {
    (global.fetch as jest.Mock).mockResolvedValue(
      jsonResponse({ code: 0, data: { ok: 1 }, msg: "" })
    );
    expect(await panghuFetch("http://s", "/api/session/status", {})).toEqual({ ok: 1 });
  });
});
