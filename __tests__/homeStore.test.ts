jest.mock("@react-native-async-storage/async-storage", () =>
  require("@react-native-async-storage/async-storage/jest/async-storage-mock")
);

jest.mock("../services/api", () => ({
  api: {
    getNavCategories: jest.fn(),
    getDailyUpdates: jest.fn(),
    getClassifyPage: jest.fn(),
  },
  SearchResult: {},
}));

jest.mock("../stores/authStore", () => ({
  __esModule: true,
  default: {
    getState: () => ({ isLoggedIn: true, checkLoginStatus: jest.fn() }),
  },
}));

jest.mock("../stores/settingsStore", () => ({
  useSettingsStore: {
    getState: () => ({ apiBaseUrl: "http://s" }),
  },
}));

import useHomeStore from "../stores/homeStore";
import { api } from "../services/api";
import { PlayRecordManager } from "../services/storage";

const mockedApi = api as jest.Mocked<typeof api>;

const ROW = {
  id: 101,
  name: "庆余年",
  picture: "/api/cover?url=p.jpg&source=src1",
  sourceId: "src1",
  year: "2024",
};

describe("homeStore（胖虎分类）", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    useHomeStore.setState({
      categories: [
        { title: "最近播放", kind: "record" },
        { title: "每日更新", kind: "daily" },
      ] as any,
      selectedCategory: { title: "最近播放", kind: "record" } as any,
      contentData: [],
      pageStart: 0,
      hasMore: true,
      error: null,
      navLoaded: true,
    });
  });

  it("daily 分类：调 getDailyUpdates 并渲染返回行", async () => {
    (mockedApi.getDailyUpdates as jest.Mock).mockResolvedValue([
      { id: "101", title: "庆余年", poster: "http://s/api/cover?url=p.jpg&source=src1", source: "src1", source_name: "源A", episodes: [] },
    ]);

    useHomeStore.getState().selectCategory({ title: "每日更新", kind: "daily" } as any);
    await useHomeStore.getState().fetchInitialData();

    expect(mockedApi.getDailyUpdates).toHaveBeenCalledWith(0, 1, 20);
    const state = useHomeStore.getState();
    expect(state.contentData).toHaveLength(1);
    expect(state.contentData[0].source).toBe("src1");
    expect(state.contentData[0].id).toBe("101");
  });

  it("pid 分类：调 getClassifyPage 传 pid", async () => {
    (mockedApi.getClassifyPage as jest.Mock).mockResolvedValue([]);

    useHomeStore.getState().selectCategory({ title: "电影", kind: "pid", pid: 6 } as any);
    await useHomeStore.getState().fetchInitialData();

    expect(mockedApi.getClassifyPage).toHaveBeenCalledWith(6, { current: 1 });
  });

  it("record 分类：走本地 PlayRecordManager 且零 api 调用", async () => {
    await PlayRecordManager.save("src1", "101", {
      title: "庆余年",
      source_name: "源A",
      cover: "c",
      index: 1,
      total_episodes: 36,
      play_time: 100,
      total_time: 1800,
      year: "2024",
    });

    useHomeStore.getState().selectCategory({ title: "最近播放", kind: "record" } as any);
    await useHomeStore.getState().fetchInitialData();

    const state = useHomeStore.getState();
    expect(state.contentData).toHaveLength(1);
    expect(mockedApi.getDailyUpdates).not.toHaveBeenCalled();
    expect(mockedApi.getClassifyPage).not.toHaveBeenCalled();
  });

  it("加载失败设 error", async () => {
    (mockedApi.getDailyUpdates as jest.Mock).mockRejectedValue(new Error("Network request failed"));

    useHomeStore.getState().selectCategory({ title: "每日更新", kind: "daily" } as any);
    await useHomeStore.getState().fetchInitialData();

    expect(useHomeStore.getState().error).toBeTruthy();
  });

  it("首次加载自动注入胖虎导航大类", async () => {
    (mockedApi.getNavCategories as jest.Mock).mockResolvedValue([
      { pid: 1, name: "电视剧" },
      { pid: 6, name: "电影" },
    ]);
    (mockedApi.getDailyUpdates as jest.Mock).mockResolvedValue([]);

    useHomeStore.setState({ navLoaded: false });
    useHomeStore.getState().selectCategory({ title: "每日更新", kind: "daily" } as any);
    await useHomeStore.getState().fetchInitialData();

    const titles = useHomeStore.getState().categories.map((c) => c.title);
    expect(titles).toContain("电视剧");
    expect(titles).toContain("电影");
  });
});
