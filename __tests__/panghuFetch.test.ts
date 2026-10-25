jest.mock("@react-native-async-storage/async-storage", () =>
  require("@react-native-async-storage/async-storage/jest/async-storage-mock")
);

import {
  getAuthToken,
  setAuthToken,
  clearAuthToken,
  setServerFlags,
} from "../services/authToken";
import { panghuFetch, isPrivateAccess, setPrivateAccess } from "../services/api";

const jsonResponse = (body: any, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });

describe("panghuFetch", () => {
  beforeEach(async () => {
    await clearAuthToken();
    await setServerFlags({ privateAccess: false, requireWebLogin: false });
    setPrivateAccess(false);
  });

  it("baseURL 为空抛 API_URL_NOT_SET", async () => {
    await expect(panghuFetch("", "/api/login", {})).rejects.toThrow("API_URL_NOT_SET");
  });

  it("code:0 返回 data", async () => {
    global.fetch = jest.fn().mockResolvedValue(jsonResponse({ code: 0, data: { token: "t" }, msg: "ok" }));
    const data = await panghuFetch("http://s", "/api/login", {});
    expect(data).toEqual({ token: "t" });
  });

  it("HTTP 200 但 code:-1 抛 Error 含 msg", async () => {
    global.fetch = jest.fn().mockResolvedValue(jsonResponse({ code: -1, data: null, msg: "密码错误" }));
    await expect(panghuFetch("http://s", "/api/login", {})).rejects.toThrow("密码错误");
  });

  it("带 token 时请求头含 Authorization: Bearer", async () => {
    await setAuthToken("jwt-xyz");
    const fetchMock = jest.fn().mockResolvedValue(jsonResponse({ code: 0, data: {}, msg: "" }));
    global.fetch = fetchMock;
    await panghuFetch("http://s", "/api/sources", {});
    const init = fetchMock.mock.calls[0][1];
    expect((init.headers as any).Authorization).toBe("Bearer jwt-xyz");
  });

  it("响应头 X-Auth-Token 存在时更新本地 token", async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue(jsonResponse({ code: 0, data: {}, msg: "" }, 200, { "X-Auth-Token": "jwt-new" }));
    await panghuFetch("http://s", "/api/index", {});
    expect(await getAuthToken()).toBe("jwt-new");
  });

  it("HTTP 401 且无 restorer 抛 UNAUTHORIZED", async () => {
    global.fetch = jest.fn().mockResolvedValue(jsonResponse({ code: 0, msg: "请重新登录" }, 401));
    await expect(panghuFetch("http://s", "/api/index", {})).rejects.toThrow("UNAUTHORIZED");
  });

  it("非 200 非 401 抛 HTTP error", async () => {
    global.fetch = jest.fn().mockResolvedValue(jsonResponse({}, 403));
    await expect(panghuFetch("http://s", "/api/index", {})).rejects.toThrow("403");
  });

  it("isPrivateAccess 同步镜像 setPrivateAccess", () => {
    expect(isPrivateAccess()).toBe(false);
    setPrivateAccess(true);
    expect(isPrivateAccess()).toBe(true);
  });
});
