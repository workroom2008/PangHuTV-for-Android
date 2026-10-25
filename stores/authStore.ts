import { create } from "zustand";
import { api } from "@/services/api";
import { LoginCredentialsManager } from "@/services/storage";
import { getAuthToken, clearAuthToken } from "@/services/authToken";
import Logger from "@/utils/Logger";

const logger = Logger.withTag('AuthStore');

interface AuthState {
  isLoggedIn: boolean;
  isLoginModalVisible: boolean;
  showLoginModal: () => void;
  hideLoginModal: () => void;
  checkLoginStatus: (apiBaseUrl?: string) => Promise<void>;
  // 用已保存的用户名/密码自动重连会话；失败才弹登录框。
  restoreSession: () => Promise<void>;
  logout: () => Promise<void>;
}

// 并发去重：多个请求同时 401 时只触发一次自动登录
let restorePromise: Promise<void> | null = null;

const useAuthStore = create<AuthState>((set, get) => ({
  isLoggedIn: false,
  isLoginModalVisible: false,
  showLoginModal: () => set({ isLoginModalVisible: true }),
  hideLoginModal: () => set({ isLoginModalVisible: false }),
  checkLoginStatus: async (apiBaseUrl?: string) => {
    if (!apiBaseUrl) {
      set({ isLoggedIn: false, isLoginModalVisible: false });
      return;
    }
    try {
      const authToken = await getAuthToken();
      if (!authToken || authToken.trim() === '') {
        // 无 token：优先用已保存凭据自动重登，失败才弹登录框
        await get().restoreSession();
        return;
      }

      // 有 token：经 session/status 校验（服务端在 JWT 过期但会话有效时会发新 token）
      const status = await api.getSessionStatus();
      if (status.authenticated) {
        set({ isLoggedIn: true, isLoginModalVisible: false });
      } else {
        // JWT 有效但 Redis 会话失效：清 token 后走凭据重登/弹登录框，不留死路
        await clearAuthToken();
        await get().restoreSession();
      }
    } catch (error) {
      logger.error("Failed to check login status:", error);
      if (error instanceof Error && error.message === "UNAUTHORIZED") {
        // 会话已过期：用保存的凭据尝试自动重连，失败再弹登录框。
        await get().restoreSession();
      } else {
        set({ isLoggedIn: false });
      }
    }
  },
  restoreSession: async () => {
    // 并发去重：多个 401 同时触发时只执行一次自动登录
    if (!restorePromise) {
      restorePromise = (async () => {
        const creds = await LoginCredentialsManager.get();
        if (!creds || !creds.username) {
          // 无可用凭据，需要用户手动登录。
          set({ isLoggedIn: false, isLoginModalVisible: true });
          return;
        }
        try {
          // 用保存的用户名/密码自动登录，服务端下发新 token
          await api.login(creds.username, creds.password);
          set({ isLoggedIn: true, isLoginModalVisible: false });
        } catch (error) {
          // 自动登录失败，仍需用户手动输入。
          logger.warn("restoreSession auto-login failed, showing login modal.", error);
          await clearAuthToken();
          set({ isLoggedIn: false, isLoginModalVisible: true });
        }
      })().finally(() => {
        restorePromise = null;
      });
    }
    return restorePromise;
  },
  logout: async () => {
    try {
      await api.logout();
      set({ isLoggedIn: false, isLoginModalVisible: true });
    } catch (error) {
      logger.error("Failed to logout:", error);
    }
  },
}));

// 注册会话恢复回调：API 层遇到 401 时自动重登并重试
api.setSessionRestorer(async () => {
  await useAuthStore.getState().restoreSession();
  return useAuthStore.getState().isLoggedIn;
});

export default useAuthStore;
