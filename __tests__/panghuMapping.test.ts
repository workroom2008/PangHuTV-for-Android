jest.mock("@react-native-async-storage/async-storage", () =>
  require("@react-native-async-storage/async-storage/jest/async-storage-mock")
);

import { api, panghuFetch, setPrivateAccess } from "../services/api";
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
  });

  describe("toPlaybackUrl", () => {
    it("直链原样返回", () => {
      expect(toPlaybackUrl("http://x/v.m3u8", "http://s")).toBe("http://x/v.m3u8");
    });

    it("相对直链拼 origin", () => {
      expect(toPlaybackUrl("/v/1.mp4", "http://s")).toBe("http://s/v/1.mp4");
    });

    it("/api/hls 改写为 /api/hls.m3u8", () => {
      expect(toPlaybackUrl("/api/hls?url=a.m3u8&source=src1", "http://s")).toBe(
        "http://s/api/hls.m3u8?url=a.m3u8&source=src1"
      );
    });

    it("私有化时 hls 追加 token", async () => {
      await setAuthToken("jwt-t");
      setPrivateAccess(true);
      expect(toPlaybackUrl("/api/hls?url=a.m3u8&source=src1", "http://s")).toBe(
        "http://s/api/hls.m3u8?url=a.m3u8&source=src1&token=jwt-t"
      );
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

      const results = await api.searchByKeyword("庆余年");
      expect(results).toHaveLength(1);
      const r = results[0];
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
    const PLAY_INFO = {
      code: 0,
      msg: "ok",
      data: {
        detail: {
          Id: 101,
          Name: "庆余年",
          Picture: "/api/cover?url=p.jpg&source=src1",
          Year: "2024",
          Area: "内地",
          Director: "导演甲",
          Actor: "演员乙",
          Content: "简介内容",
          CName: "剧情",
          Remarks: "更新至36集",
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
          List: [
            {
              Id: "src2",
              Name: "线路B",
              LinkList: [{ episode: "1", link: "http://y/1.m3u8" }],
            },
            {
              Id: "src1",
              Name: "线路A",
              LinkList: [
                { episode: "1", link: "/api/hls?url=1&source=src1" },
                { episode: "2", link: "http://x/2.m3u8" },
                { episode: "3", link: "/api/hls?url=3&source=src1" },
              ],
            },
          ],
        },
      },
    };

    it("detail.List 线路 → sources（每线路一个 SearchResult，episodes 经 toPlaybackUrl）", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(jsonResponse(DETAIL_WITH_LINKS));

      const info = await api.getPlayInfoDetail("101", "src1", 0);
      expect(info.sources).toHaveLength(2);
      const lineA = info.sources.find((s) => s.source === "src1")!;
      expect(lineA.source_name).toBe("线路A");
      expect(lineA.episodes).toHaveLength(3);
      expect(lineA.episodes[0]).toBe("http://s/api/hls.m3u8?url=1&source=src1");
      expect(lineA.episodes[1]).toBe("http://x/2.m3u8");
      expect(info.detail.title).toBe("庆余年");
      expect(info.currentSource).toBe("src1");
    });

    it("preferred 线路排首位", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(jsonResponse(DETAIL_WITH_LINKS));

      const info = await api.getPlayInfoDetail("101", "src1", 0);
      expect(info.sources[0].source).toBe("src1");
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

  describe("getApiSources", () => {
    it("/api/sources → ApiSite[]", async () => {
      (global.fetch as jest.Mock).mockResolvedValue(
        jsonResponse({ code: 0, data: [{ id: "src1", name: "源A" }], msg: "ok" })
      );
      const sites = await api.getApiSources();
      expect(sites).toEqual([{ key: "src1", api: "", name: "源A" }]);
    });
  });

  it("panghuFetch 仍可用于底层调用", async () => {
    (global.fetch as jest.Mock).mockResolvedValue(
      jsonResponse({ code: 0, data: { ok: 1 }, msg: "" })
    );
    expect(await panghuFetch("http://s", "/api/session/status", {})).toEqual({ ok: 1 });
  });
});
