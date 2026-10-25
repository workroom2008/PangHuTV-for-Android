import { create } from 'zustand';
import { remoteControlService, RemoteConfigPayload } from '@/services/remoteControlService';
import { useSettingsStore } from '@/stores/settingsStore';
import { LoginCredentialsManager } from '@/services/storage';
import Logger from '@/utils/Logger';

const logger = Logger.withTag('RemoteControlStore');

interface RemoteControlState {
  isServerRunning: boolean;
  serverUrl: string | null;
  error: string | null;
  startServer: () => Promise<void>;
  stopServer: () => void;
  isModalVisible: boolean;
  showModal: (targetPage?: string) => void;
  hideModal: () => void;
  lastMessage: string | null;
  targetPage: string | null;
  setMessage: (message: string, targetPage?: string) => void;
  clearMessage: () => void;
}

export const useRemoteControlStore = create<RemoteControlState>((set, get) => ({
  isServerRunning: false,
  serverUrl: null,
  error: null,
  isModalVisible: false,
  lastMessage: null,
  targetPage: null,

  startServer: async () => {
    if (get().isServerRunning) {
      return;
    }
    remoteControlService.init({
      onMessage: (message: string) => {
        logger.debug('Received message:', message);
        const currentState = get();
        // 手机端「发送文本」固定给搜索页用；targetPage 为空时默认 search，
        // 否则搜索页判断 targetPage === 'search' 永远不成立，文本收不到。
        set({
          lastMessage: `${message}_${Date.now()}`,
          targetPage: currentState.targetPage ?? 'search',
        });
      },
      onHandshake: () => {
        logger.debug('Handshake successful');
        set({ isModalVisible: false })
      },
      getConfig: async () => {
        const s = useSettingsStore.getState();
        const creds = await LoginCredentialsManager.get();
        return {
          apiBaseUrl: s.apiBaseUrl,
          m3uUrl: s.m3uUrl,
          username: creds?.username ?? '',
          password: creds?.password ?? '',
        };
      },
      applyConfig: async (config: RemoteConfigPayload) => {
        try {
          const s = useSettingsStore.getState();
          if (config.apiBaseUrl) s.setApiBaseUrl(config.apiBaseUrl);
          if (config.m3uUrl !== undefined) s.setM3uUrl(config.m3uUrl);
          await s.saveSettings();

          let loginMsg = '';
          if (config.username) {
            const ok = await s.saveAccountAndLogin(config.username, config.password ?? '');
            loginMsg = ok ? '，已登录' : '，登录失败请检查账号';
          }
          return { status: 'ok' as const, message: `设置已保存${loginMsg}` };
        } catch (error) {
          logger.error('applyConfig failed:', error);
          return { status: 'error' as const, message: '保存失败，请重试' };
        }
      },
    });
    try {
      const url = await remoteControlService.startServer();
      logger.info('Server started, URL:', url);
      set({ isServerRunning: true, serverUrl: url, error: null });
    } catch (e) {
      // 展示真实失败原因（IP 未就绪/端口占用等），不再笼统提示
      const reason = e instanceof Error ? e.message : String(e);
      const errorMessage = `启动失败：${reason}（电视请连网线或同一 WiFi 后重试；仍失败可到电视系统设置查看本机 IP，手机浏览器访问 http://电视IP:12346）`;
      logger.error('Failed to start server:', errorMessage);
      set({ error: errorMessage });
    }
  },

  stopServer: () => {
    if (get().isServerRunning) {
      remoteControlService.stopServer();
      set({ isServerRunning: false, serverUrl: null });
    }
  },

  showModal: (targetPage?: string) => set({ isModalVisible: true, targetPage }),
  hideModal: () => set({ isModalVisible: false, targetPage: null }),

  setMessage: (message: string, targetPage?: string) => {
    set({ lastMessage: `${message}_${Date.now()}`, targetPage });
  },

  clearMessage: () => {
    set({ lastMessage: null, targetPage: null });
  },
}));