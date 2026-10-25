jest.mock("@react-native-async-storage/async-storage", () =>
  require("@react-native-async-storage/async-storage/jest/async-storage-mock")
);

jest.mock("../services/api", () => ({
  api: {
    login: jest.fn(),
    logout: jest.fn(),
    getSessionStatus: jest.fn(),
    getSiteBasic: jest.fn(),
    setSessionRestorer: jest.fn(),
  },
  setSessionRestorer: jest.fn(),
  panghuFetch: jest.fn(),
  isPrivateAccess: jest.fn(() => false),
  setPrivateAccess: jest.fn(),
}));

jest.mock("../services/storage", () => ({
  LoginCredentialsManager: {
    get: jest.fn(),
    save: jest.fn(),
    clear: jest.fn(),
  },
}));

import useAuthStore from "../stores/authStore";
import { api } from "../services/api";
import { LoginCredentialsManager } from "../services/storage";
import { setAuthToken, clearAuthToken } from "../services/authToken";

const mockedApi = api as jest.Mocked<typeof api>;
const mockedCreds = LoginCredentialsManager as jest.Mocked<
  typeof LoginCredentialsManager
>;

describe("authStore（胖虎登录链路）", () => {
  beforeEach(async () => {
    jest.clearAllMocks();
    await clearAuthToken();
    useAuthStore.setState({
      isLoggedIn: false,
      isLoginModalVisible: false,
    });
  });

  it("restoreSession：有已存凭据且 login 成功 → isLoggedIn=true 且不弹登录框", async () => {
    mockedCreds.get.mockResolvedValue({ username: "admin", password: "pw" });
    (mockedApi.login as jest.Mock).mockResolvedValue({ ok: true });

    await useAuthStore.getState().restoreSession();

    expect(mockedApi.login).toHaveBeenCalledWith("admin", "pw");
    const state = useAuthStore.getState();
    expect(state.isLoggedIn).toBe(true);
    expect(state.isLoginModalVisible).toBe(false);
  });

  it("checkLoginStatus：token 存在但 session/status 返回 authenticated:false → isLoggedIn=false", async () => {
    await setAuthToken("expired-jwt");
    (mockedApi.getSessionStatus as jest.Mock).mockResolvedValue({
      authenticated: false,
      licenseEnforced: true,
      licensed: true,
      requireWebLogin: false,
    });

    await useAuthStore.getState().checkLoginStatus("http://s");

    const state = useAuthStore.getState();
    expect(state.isLoggedIn).toBe(false);
    expect(mockedApi.getSessionStatus).toHaveBeenCalled();
  });

  it("checkLoginStatus：无 token 且无凭据 → 弹登录框", async () => {
    mockedCreds.get.mockResolvedValue(null);

    await useAuthStore.getState().checkLoginStatus("http://s");

    const state = useAuthStore.getState();
    expect(state.isLoggedIn).toBe(false);
    expect(state.isLoginModalVisible).toBe(true);
  });
});
