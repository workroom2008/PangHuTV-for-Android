import AsyncStorage from "@react-native-async-storage/async-storage";
import type { PlayRecord as ApiPlayRecord, Favorite as ApiFavorite } from "./api";
import Logger from '@/utils/Logger';

const logger = Logger.withTag('Storage');

// --- Storage Keys ---
const STORAGE_KEYS = {
  SETTINGS: "mytv_settings",
  PLAYER_SETTINGS: "mytv_player_settings",
  FAVORITES: "mytv_favorites",
  PLAY_RECORDS: "mytv_play_records",
  SEARCH_HISTORY: "mytv_search_history",
  LOGIN_CREDENTIALS: "mytv_login_credentials",
} as const;

// --- Type Definitions (aligned with api.ts) ---
// Re-exporting for consistency, though they are now primarily API types
export type PlayRecord = ApiPlayRecord & {
  introEndTime?: number;
  outroStartTime?: number;
};
export type Favorite = ApiFavorite;

export interface PlayerSettings {
  introEndTime?: number;
  outroStartTime?: number;
  playbackRate?: number;
}

export interface AppSettings {
  apiBaseUrl: string;
  remoteInputEnabled: boolean;
  videoSource: {
    enabledAll: boolean;
    sources: {
      [key: string]: boolean;
    };
  };
  m3uUrl: string;
}

export interface LoginCredentials {
  username: string;
  password: string;
}

// --- Helper ---
const generateKey = (source: string, id: string) => `${source}+${id}`;

// --- PlayerSettingsManager (Uses AsyncStorage) ---
export class PlayerSettingsManager {
  static async getAll(): Promise<Record<string, PlayerSettings>> {
    try {
      const data = await AsyncStorage.getItem(STORAGE_KEYS.PLAYER_SETTINGS);
      return data ? JSON.parse(data) : {};
    } catch (error) {
      logger.info("Failed to get all player settings:", error);
      return {};
    }
  }

  static async get(source: string, id: string): Promise<PlayerSettings | null> {
    const perfStart = performance.now();
    logger.info(`[PERF] PlayerSettingsManager.get START - source: ${source}, id: ${id}`);
    
    const allSettings = await this.getAll();
    const result = allSettings[generateKey(source, id)] || null;
    
    const perfEnd = performance.now();
    logger.info(`[PERF] PlayerSettingsManager.get END - took ${(perfEnd - perfStart).toFixed(2)}ms, found: ${!!result}`);
    
    return result;
  }

  static async save(source: string, id: string, settings: PlayerSettings): Promise<void> {
    const allSettings = await this.getAll();
    const key = generateKey(source, id);
    // Only save if there are actual values to save
    if (settings.introEndTime !== undefined || settings.outroStartTime !== undefined || settings.playbackRate !== undefined) {
      allSettings[key] = { ...allSettings[key], ...settings };
    } else {
      // If all are undefined, remove the key
      delete allSettings[key];
    }
    await AsyncStorage.setItem(STORAGE_KEYS.PLAYER_SETTINGS, JSON.stringify(allSettings));
  }

  static async remove(source: string, id: string): Promise<void> {
    const allSettings = await this.getAll();
    delete allSettings[generateKey(source, id)];
    await AsyncStorage.setItem(STORAGE_KEYS.PLAYER_SETTINGS, JSON.stringify(allSettings));
  }

  static async clearAll(): Promise<void> {
    await AsyncStorage.removeItem(STORAGE_KEYS.PLAYER_SETTINGS);
  }
}

// --- FavoriteManager (胖虎无云端收藏接口，固定本地存储) ---
export class FavoriteManager {
  static async getAll(): Promise<Record<string, Favorite>> {
    try {
      const data = await AsyncStorage.getItem(STORAGE_KEYS.FAVORITES);
      return data ? JSON.parse(data) : {};
    } catch (error) {
      logger.info("Failed to get all local favorites:", error);
      return {};
    }
  }

  static async save(source: string, id: string, item: Favorite): Promise<void> {
    const allFavorites = await this.getAll();
    allFavorites[generateKey(source, id)] = { ...item, save_time: Date.now() };
    await AsyncStorage.setItem(STORAGE_KEYS.FAVORITES, JSON.stringify(allFavorites));
  }

  static async remove(source: string, id: string): Promise<void> {
    const allFavorites = await this.getAll();
    delete allFavorites[generateKey(source, id)];
    await AsyncStorage.setItem(STORAGE_KEYS.FAVORITES, JSON.stringify(allFavorites));
  }

  static async isFavorited(source: string, id: string): Promise<boolean> {
    const allFavorites = await this.getAll();
    return !!allFavorites[generateKey(source, id)];
  }

  static async toggle(source: string, id: string, item: Favorite): Promise<boolean> {
    const isFav = await this.isFavorited(source, id);
    if (isFav) {
      await this.remove(source, id);
      return false;
    } else {
      await this.save(source, id, item);
      return true;
    }
  }

  static async clearAll(): Promise<void> {
    await AsyncStorage.removeItem(STORAGE_KEYS.FAVORITES);
  }
}

// --- PlayRecordManager (胖虎无云端播放记录接口，固定本地存储) ---
export class PlayRecordManager {
  static async getAll(): Promise<Record<string, PlayRecord>> {
    const perfStart = performance.now();
    logger.info(`[PERF] PlayRecordManager.getAll START - local`);

    let records: Record<string, PlayRecord> = {};
    try {
      const data = await AsyncStorage.getItem(STORAGE_KEYS.PLAY_RECORDS);
      records = data ? JSON.parse(data) : {};
    } catch (error) {
      logger.info("Failed to get all local play records:", error);
      return {};
    }

    const localSettings = await PlayerSettingsManager.getAll();
    const mergedRecords: Record<string, PlayRecord> = {};
    for (const key in records) {
      mergedRecords[key] = {
        ...records[key],
        ...localSettings[key],
      };
    }

    const perfEnd = performance.now();
    logger.info(`[PERF] PlayRecordManager.getAll END - took ${(perfEnd - perfStart).toFixed(2)}ms, total records: ${Object.keys(mergedRecords).length}`);

    return mergedRecords;
  }

  static async save(source: string, id: string, record: Omit<PlayRecord, "save_time">): Promise<void> {
    const key = generateKey(source, id);
    const { introEndTime, outroStartTime, ...pureRecord } = record;

    // Player settings are always saved locally
    await PlayerSettingsManager.save(source, id, { introEndTime, outroStartTime });

    const allRecords = await this.getAll();
    const fullRecord = { ...pureRecord, save_time: Date.now() };
    allRecords[key] = { ...allRecords[key], ...fullRecord };
    await AsyncStorage.setItem(STORAGE_KEYS.PLAY_RECORDS, JSON.stringify(allRecords));
  }

  static async get(source: string, id: string): Promise<PlayRecord | null> {
    const perfStart = performance.now();
    const key = generateKey(source, id);
    logger.info(`[PERF] PlayRecordManager.get START - source: ${source}, id: ${id}`);

    const records = await this.getAll();
    const result = records[key] || null;

    const perfEnd = performance.now();
    logger.info(`[PERF] PlayRecordManager.get END - took ${(perfEnd - perfStart).toFixed(2)}ms, found: ${!!result}`);

    return result;
  }

  static async remove(source: string, id: string): Promise<void> {
    const key = generateKey(source, id);
    await PlayerSettingsManager.remove(source, id); // Always remove local settings

    const allRecords = await this.getAll();
    delete allRecords[key];
    await AsyncStorage.setItem(STORAGE_KEYS.PLAY_RECORDS, JSON.stringify(allRecords));
  }

  static async clearAll(): Promise<void> {
    await PlayerSettingsManager.clearAll(); // Always clear local settings
    await AsyncStorage.removeItem(STORAGE_KEYS.PLAY_RECORDS);
  }
}

// --- SearchHistoryManager (固定本地存储) ---
export class SearchHistoryManager {
  static async get(): Promise<string[]> {
    try {
      const data = await AsyncStorage.getItem(STORAGE_KEYS.SEARCH_HISTORY);
      return data ? JSON.parse(data) : [];
    } catch (error) {
      logger.info("Failed to get local search history:", error);
      return [];
    }
  }

  static async add(keyword: string): Promise<void> {
    const trimmed = keyword.trim();
    if (!trimmed) return;

    let history = await this.get();
    history = [trimmed, ...history.filter((k) => k !== trimmed)].slice(0, 20); // Keep latest 20
    await AsyncStorage.setItem(STORAGE_KEYS.SEARCH_HISTORY, JSON.stringify(history));
  }

  static async clear(): Promise<void> {
    await AsyncStorage.removeItem(STORAGE_KEYS.SEARCH_HISTORY);
  }
}

// --- SettingsManager (Uses AsyncStorage) ---
export class SettingsManager {
  static async get(): Promise<AppSettings> {
    const defaultSettings: AppSettings = {
      apiBaseUrl: "",
      remoteInputEnabled: true,
      videoSource: {
        enabledAll: true,
        sources: {},
      },
      m3uUrl: "",
    };
    try {
      const data = await AsyncStorage.getItem(STORAGE_KEYS.SETTINGS);
      return data ? { ...defaultSettings, ...JSON.parse(data) } : defaultSettings;
    } catch (error) {
      logger.info("Failed to get settings:", error);
      return defaultSettings;
    }
  }

  static async save(settings: Partial<AppSettings>): Promise<void> {
    const currentSettings = await this.get();
    const updatedSettings = { ...currentSettings, ...settings };
    await AsyncStorage.setItem(STORAGE_KEYS.SETTINGS, JSON.stringify(updatedSettings));
  }

  static async reset(): Promise<void> {
    await AsyncStorage.removeItem(STORAGE_KEYS.SETTINGS);
  }
}

// --- LoginCredentialsManager (Uses AsyncStorage) ---
export class LoginCredentialsManager {
  static async get(): Promise<LoginCredentials | null> {
    try {
      const data = await AsyncStorage.getItem(STORAGE_KEYS.LOGIN_CREDENTIALS);
      return data ? JSON.parse(data) : null;
    } catch (error) {
      logger.info("Failed to get login credentials:", error);
      return null;
    }
  }

  static async save(credentials: LoginCredentials): Promise<void> {
    try {
      await AsyncStorage.setItem(STORAGE_KEYS.LOGIN_CREDENTIALS, JSON.stringify(credentials));
    } catch (error) {
      logger.error("Failed to save login credentials:", error);
    }
  }

  static async clear(): Promise<void> {
    try {
      await AsyncStorage.removeItem(STORAGE_KEYS.LOGIN_CREDENTIALS);
    } catch (error) {
      logger.error("Failed to clear login credentials:", error);
    }
  }
}
