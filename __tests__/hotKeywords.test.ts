jest.mock("@react-native-async-storage/async-storage", () =>
  require("@react-native-async-storage/async-storage/jest/async-storage-mock")
);

import { api } from "../services/api";

const jsonResponse = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

describe("getHotKeywords", () => {
  beforeEach(() => {
    api.setBaseUrl("http://s");
  });

  it("正常返回热词数组", async () => {
    global.fetch = jest.fn().mockResolvedValue(
      jsonResponse({ code: 0, data: ["庆余年", "三体"], msg: "ok" })
    );
    const words = await api.getHotKeywords();
    expect(words).toEqual(["庆余年", "三体"]);
    expect((global.fetch as jest.Mock).mock.calls[0][0]).toContain("/api/hotKeywords");
  });

  it("网络失败静默返回空数组", async () => {
    global.fetch = jest.fn().mockRejectedValue(new Error("Network request failed"));
    const words = await api.getHotKeywords();
    expect(words).toEqual([]);
  });
});
