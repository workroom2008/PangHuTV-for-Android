jest.mock("@react-native-async-storage/async-storage", () =>
  require("@react-native-async-storage/async-storage/jest/async-storage-mock")
);

import useDetailStore from "../stores/detailStore";
import { FavoriteManager, PlayRecordManager } from "../services/storage";
import AsyncStorage from "@react-native-async-storage/async-storage";

// 存入本地（收藏/播放记录）的封面必须是未拼 token 的原始路径，
// 否则 token 轮换后海报永久 401 白图
const DETAIL = {
  id: "101",
  title: "庆余年",
  poster: "http://s/api/cover?url=p.jpg&source=src1&token=jwt-old",
  rawPoster: "/api/cover?url=p.jpg&source=src1",
  episodes: ["http://s/api/hls.m3u8?url=1"],
  source: "src1",
  source_name: "线路A",
  year: "2024",
} as any;

describe("收藏/播放记录封面存原始路径（I3）", () => {
  beforeEach(async () => {
    await AsyncStorage.multiRemove(["mytv_favorites", "mytv_play_records"]);
    useDetailStore.setState({ detail: DETAIL, q: "庆余年" } as any);
  });

  it("toggleFavorite 存 rawPoster 而非带 token 的 poster", async () => {
    await useDetailStore.getState().toggleFavorite();

    const favorites = await FavoriteManager.getAll();
    expect(favorites["src1+101"].cover).toBe("/api/cover?url=p.jpg&source=src1");
  });

  it("播放记录存原始封面路径", async () => {
    await PlayRecordManager.save(DETAIL.source, DETAIL.id, {
      title: DETAIL.title,
      cover: DETAIL.rawPoster || DETAIL.poster,
      index: 1,
      total_episodes: 1,
      play_time: 10,
      total_time: 100,
      year: "2024",
      source_name: "线路A",
    } as any);

    const records = await PlayRecordManager.getAll();
    expect(records["src1+101"].cover).toBe("/api/cover?url=p.jpg&source=src1");
  });
});
