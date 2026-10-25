import { create } from "zustand";
import { SettingsManager, LoginCredentialsManager } from "@/services/storage";
import { api, SiteBasic } from "@/services/api";
import { clearAuthToken, clearServerFlags } from "@/services/authToken";
import AsyncStorage from "@react-native-async-storage/async-storage";
import Logger from "@/utils/Logger";

const logger = Logger.withTag('SettingsStore');

// 模块级引用：当前正在进行的 fetchServerConfig Promise。
// 供 authStore.checkLoginStatus 直接 await，避免用固定超时轮询导致冷启动误判。
let serverConfigPromise: Promise<void> | null = null;

/**
 * 获取当前正在进行的 fetchServerConfig Promise（若没有则返回 null）。
 * 调用方可 await 它以确保 serverConfig 已就绪，而不是用固定超时轮询。
 */
export function getServerConfigPromise(): Promise<void> | null {
  return serverConfigPromise;
}

interface SettingsState {
  apiBaseUrl: string;
  m3uUrl: string;
  remoteInputEnabled: boolean;
  videoSource: {
    enabledAll: boolean;
    sources: {
      [key: string]: boolean;
    };
  };
  isModalVisible: boolean;
  serverConfig: SiteBasic | null;
  isLoadingServerConfig: boolean;
  loadSettings: () => Promise<void>;
  fetchServerConfig: () => Promise<void>;
  /** 设置页保存账号：非空时存凭据并立即登录（供远程输入一次配好） */
  saveAccountAndLogin: (username: string, password: string) => Promise<boolean>;
  setApiBaseUrl: (url: string) => void;
  setM3uUrl: (url: string) => void;
  setRemoteInputEnabled: (enabled: boolean) => void;
  saveSettings: () => Promise<void>;
  setVideoSource: (config: { enabledAll: boolean; sources: { [key: string]: boolean } }) => void;
  showModal: () => void;
  hideModal: () => void;
}

export const useSettingsStore = create<SettingsState>((set, get) => ({
  apiBaseUrl: "",
  m3uUrl: "",
  liveStreamSources: [],
  remoteInputEnabled: false,
  isModalVisible: false,
  serverConfig: null,
  isLoadingServerConfig: false,
  videoSource: {
    enabledAll: true,
    sources: {},
  },
  loadSettings: async () => {
    const settings = await SettingsManager.get();
    set({
      apiBaseUrl: settings.apiBaseUrl,
      m3uUrl: settings.m3uUrl,
      remoteInputEnabled: settings.remoteInputEnabled || false,
      videoSource: settings.videoSource || {
        enabledAll: true,
        sources: {},
      },
    });
    if (settings.apiBaseUrl) {
      api.setBaseUrl(settings.apiBaseUrl);
      await get().fetchServerConfig();
    }
  },
  fetchServerConfig: () => {
    const p = (async () => {
      set({ isLoadingServerConfig: true });
      try {
        // 胖虎站点基础配置（免登录），内部同步私有化开关
        const siteBasic = await api.getSiteBasic();
        set({ serverConfig: siteBasic });
      } catch (error) {
        set({ serverConfig: null });
        logger.error("Failed to fetch server config:", error);
      } finally {
        set({ isLoadingServerConfig: false });
      }
    })();
    serverConfigPromise = p;
    return p;
  },
  saveAccountAndLogin: async (username, password) => {
    if (!username.trim()) {
      return false;
    }
    await LoginCredentialsManager.save({ username: username.trim(), password });
    try {
      await api.login(username.trim(), password);
      return true;
    } catch (error) {
      logger.warn("saveAccountAndLogin failed:", error);
      return false;
    }
  },
  setApiBaseUrl: (url) => set({ apiBaseUrl: url }),
  setM3uUrl: (url) => set({ m3uUrl: url }),
  setRemoteInputEnabled: (enabled) => set({ remoteInputEnabled: enabled }),
  setVideoSource: (config) => set({ videoSource: config }),
  saveSettings: async () => {
    const { apiBaseUrl, m3uUrl, remoteInputEnabled, videoSource } = get();
    const currentSettings = await SettingsManager.get()
    const currentApiBaseUrl = currentSettings.apiBaseUrl;
    let processedApiBaseUrl = apiBaseUrl.trim();
    if (processedApiBaseUrl.endsWith("/")) {
      processedApiBaseUrl = processedApiBaseUrl.slice(0, -1);
    }

    if (!/^https?:\/\//i.test(processedApiBaseUrl)) {
      const hostPart = processedApiBaseUrl.split("/")[0];
      // Simple check for IP address format.
      const isIpAddress = /^((\d{1,3}\.){3}\d{1,3})(:\d+)?$/.test(hostPart);
      // Check if the domain includes a port.
      const hasPort = /:\d+/.test(hostPart);

      if (isIpAddress || hasPort) {
        processedApiBaseUrl = "http://" + processedApiBaseUrl;
      } else {
        processedApiBaseUrl = "https://" + processedApiBaseUrl;
      }
    }

    await SettingsManager.save({
      apiBaseUrl: processedApiBaseUrl,
      m3uUrl,
      remoteInputEnabled,
      videoSource,
    });
    if ( currentApiBaseUrl !== processedApiBaseUrl) {
      // 换服务器：清空登录态与私有化标记
      await clearAuthToken();
      await clearServerFlags();
    }
    api.setBaseUrl(processedApiBaseUrl);
    // Also update the URL in the state so the input field shows the processed URL
    set({ isModalVisible: false, apiBaseUrl: processedApiBaseUrl });
    await get().fetchServerConfig();
  },
  showModal: () => set({ isModalVisible: true }),
  hideModal: () => set({ isModalVisible: false }),
}));
