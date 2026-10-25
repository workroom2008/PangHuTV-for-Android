jest.mock("@react-native-async-storage/async-storage", () =>
  require("@react-native-async-storage/async-storage/jest/async-storage-mock")
);

import {
  PlayRecordManager,
  FavoriteManager,
  SearchHistoryManager,
} from "../services/storage";

describe("storage 本地模式（胖虎无云端收藏/记录接口）", () => {
  beforeEach(() => {
    global.fetch = jest.fn();
  });

  it("PlayRecordManager save→getAll 往返命中本地且零 fetch", async () => {
    await PlayRecordManager.save("src1", "101", {
      title: "庆余年",
      source_name: "源A",
      cover: "c",
      index: 2,
      total_episodes: 36,
      play_time: 600,
      total_time: 1800,
      year: "2024",
    });

    const all = await PlayRecordManager.getAll();
    expect(all["src1+101"].title).toBe("庆余年");
    expect(all["src1+101"].index).toBe(2);
    expect(all["src1+101"].save_time).toBeDefined();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("FavoriteManager toggle→isFavorited 本地往返且零 fetch", async () => {
    const toggled = await FavoriteManager.toggle("src1", "101", {
      cover: "c",
      title: "庆余年",
      source_name: "源A",
      total_episodes: 36,
      search_title: "庆余年",
      year: "2024",
    });
    expect(toggled).toBe(true);
    expect(await FavoriteManager.isFavorited("src1", "101")).toBe(true);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("SearchHistoryManager add→get 本地往返且零 fetch", async () => {
    await SearchHistoryManager.add("庆余年");
    const history = await SearchHistoryManager.get();
    expect(history).toContain("庆余年");
    expect(global.fetch).not.toHaveBeenCalled();
  });
});
