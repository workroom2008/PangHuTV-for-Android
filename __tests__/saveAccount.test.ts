jest.mock("@react-native-async-storage/async-storage", () =>
  require("@react-native-async-storage/async-storage/jest/async-storage-mock")
);

jest.mock("../services/api", () => ({
  api: {
    login: jest.fn(),
  },
  setSessionRestorer: jest.fn(),
}));

jest.mock("../services/storage", () => ({
  LoginCredentialsManager: {
    save: jest.fn(),
    get: jest.fn().mockResolvedValue(null),
    clear: jest.fn(),
  },
  SettingsManager: {
    get: jest.fn().mockResolvedValue({
      apiBaseUrl: "",
      remoteInputEnabled: false,
      videoSource: { enabledAll: true, sources: {} },
      m3uUrl: "",
    }),
    save: jest.fn(),
    reset: jest.fn(),
  },
  PlayRecordManager: { getAll: jest.fn().mockResolvedValue({}) },
}));

import { useSettingsStore } from "../stores/settingsStore";
import { api } from "../services/api";
import { LoginCredentialsManager } from "../services/storage";

describe("saveAccountAndLogin（设置页保存即登录）", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("用户名密码非空：存凭据并调用 api.login", async () => {
    (api.login as jest.Mock).mockResolvedValue({ ok: true });

    const ok = await useSettingsStore.getState().saveAccountAndLogin("admin", "pw");

    expect(ok).toBe(true);
    expect(LoginCredentialsManager.save).toHaveBeenCalledWith({
      username: "admin",
      password: "pw",
    });
    expect(api.login).toHaveBeenCalledWith("admin", "pw");
  });

  it("登录失败返回 false 且凭据已保存（下次可静默重登）", async () => {
    (api.login as jest.Mock).mockRejectedValue(new Error("密码错误"));

    const ok = await useSettingsStore.getState().saveAccountAndLogin("admin", "bad");

    expect(ok).toBe(false);
    expect(LoginCredentialsManager.save).toHaveBeenCalled();
  });

  it("用户名为空：跳过保存与登录，返回 false", async () => {
    const ok = await useSettingsStore.getState().saveAccountAndLogin("", "pw");

    expect(ok).toBe(false);
    expect(LoginCredentialsManager.save).not.toHaveBeenCalled();
    expect(api.login).not.toHaveBeenCalled();
  });
});
