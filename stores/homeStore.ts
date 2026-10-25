import { create } from "zustand";
import { api, SearchResult, PlayRecord } from "@/services/api";
import { PlayRecordManager } from "@/services/storage";
import useAuthStore from "./authStore";
import { useSettingsStore } from "./settingsStore";
import AsyncStorage from "@react-native-async-storage/async-storage";

export type RowItem = (SearchResult | PlayRecord) & {
  id: string;
  source: string;
  title: string;
  poster: string;
  progress?: number;
  play_time?: number;
  lastPlayed?: number;
  episodeIndex?: number;
  sourceName?: string;
  totalEpisodes?: number;
  year?: string;
  rate?: string;
};

export interface Category {
  title: string;
  kind: "record" | "daily" | "pid";
  pid?: number;
  // 保留可选字段：index.tsx 的 tag chips 行为兼容（胖虎分类下恒为空）
  tag?: string;
  tags?: string[];
}

const initialCategories: Category[] = [
  { title: "最近播放", kind: "record" },
  { title: "每日更新", kind: "daily" },
];

const PAGE_SIZE = 20;

interface HomeState {
  categories: Category[];
  selectedCategory: Category;
  /** 采集源列表与当前选中源（"" = 全部源） */
  sources: { id: string; name: string }[];
  selectedSource: string;
  contentData: RowItem[];
  loading: boolean;
  loadingMore: boolean;
  pageStart: number;
  hasMore: boolean;
  error: string | null;
  navLoaded: boolean;
  /** 冷启动恢复已选源完成（门控首次数据加载，避免先用全源查一遍再重来） */
  sourceReady: boolean;
  fetchInitialData: () => Promise<void>;
  loadMoreData: () => Promise<void>;
  selectCategory: (category: Category) => void;
  selectSource: (sourceId: string) => Promise<void>;
  initSelectedSource: () => Promise<void>;
  refreshPlayRecords: () => Promise<void>;
  clearError: () => void;
}

const SELECTED_SOURCE_KEY = "mytv_selected_source";

// 首页加载在途去重键：selectCategory/换源与首页 effect 会重复触发同一次加载
let initialFetchKey: string | null = null;

const useHomeStore = create<HomeState>((set, get) => ({
  categories: initialCategories,
  selectedCategory: initialCategories[0],
  sources: [],
  selectedSource: "",
  contentData: [],
  loading: true,
  loadingMore: false,
  pageStart: 0,
  hasMore: true,
  error: null,
  navLoaded: false,
  sourceReady: false,

  initSelectedSource: async () => {
    if (get().sourceReady) return;
    const saved = await AsyncStorage.getItem(SELECTED_SOURCE_KEY);
    if (saved) {
      // 有已选源：按换源流程重建（navCategory 按源拉取）
      set({ selectedSource: saved });
      await get().selectSource(saved);
      set({ sourceReady: true });
    } else {
      set({ sourceReady: true });
    }
  },

  selectSource: async (sourceId: string) => {
    if (get().selectedSource === sourceId) return;
    await AsyncStorage.setItem(SELECTED_SOURCE_KEY, sourceId);
    // 换源：分类体系整体重建，选中回落到"每日更新"
    set({
      selectedSource: sourceId,
      navLoaded: false,
      categories: initialCategories,
      selectedCategory: initialCategories[1],
      contentData: [],
      pageStart: 0,
      hasMore: true,
      error: null,
    });
    await get().fetchInitialData();
    set({ sourceReady: true });
  },

  fetchInitialData: async () => {
    const { apiBaseUrl } = useSettingsStore.getState();
    const { selectedSource, selectedCategory } = get();
    if (!selectedCategory) return;

    // 首页 effect 与换源/刷新会同时触发加载：同源同分类在途时只跑一次
    const fetchKey = [
      selectedSource,
      selectedCategory.kind,
      selectedCategory.pid ?? "",
      selectedCategory.tag ?? "",
    ].join("|");
    if (initialFetchKey === fetchKey) return;
    initialFetchKey = fetchKey;

    try {
      // 只有"最近播放"依赖登录态；分类/换源不再每次校验（登录态由 _layout 统一维护）
      if (selectedCategory.kind === "record") {
        await useAuthStore.getState().checkLoginStatus(apiBaseUrl);
      }

      // 源列表（一次拉取缓存到 store）
      if (get().sources.length === 0) {
        try {
          const sites = await api.getApiSources();
          set({ sources: sites.map((s) => ({ id: s.key, name: s.name })) });
        } catch {
          // 源列表失败不阻塞首页
        }
      }

      // 首次加载（或换源后）注入胖虎导航大类
      if (!get().navLoaded) {
        try {
          const navs = await api.getNavCategories(selectedSource || undefined);
          const pidCats: Category[] = navs.map((n) => ({ title: n.name, kind: "pid", pid: n.pid }));
          set({ categories: [...initialCategories, ...pidCats], navLoaded: true });
        } catch (e) {
          // 导航大类拉取失败不阻塞首页，仍可用 最近播放/每日更新
          set({ navLoaded: true });
        }
      }

      set({ loading: true, contentData: [], pageStart: 0, hasMore: true, error: null });
      await get().loadMoreData();
    } finally {
      if (initialFetchKey === fetchKey) {
        initialFetchKey = null;
      }
    }
  },

  loadMoreData: async () => {
    const { selectedCategory, selectedSource, pageStart, loadingMore, hasMore } = get();
    if (loadingMore || !hasMore) return;

    if (pageStart > 0) {
      set({ loadingMore: true });
    }

    try {
      if (selectedCategory.kind === "record") {
        const { isLoggedIn } = useAuthStore.getState();
        if (!isLoggedIn) {
          set({ contentData: [], hasMore: false });
          return;
        }
        const records = await PlayRecordManager.getAll();
        const rowItems = Object.entries(records)
          .map(([key, record]) => {
            const [source, id] = key.split("+");
            return {
              ...record,
              id,
              source,
              progress: record.play_time / record.total_time,
              poster: record.cover,
              sourceName: record.source_name,
              episodeIndex: record.index,
              totalEpisodes: record.total_episodes,
              lastPlayed: record.save_time,
              play_time: record.play_time,
            };
          })
          .sort((a, b) => (b.lastPlayed || 0) - (a.lastPlayed || 0));

        set({ contentData: rowItems, hasMore: false });
      } else if (selectedCategory.kind === "daily") {
        // pageStart 按固定页幅推进（非 rows.length）：尾页非满页时游标不漂移
        const current = Math.floor(pageStart / PAGE_SIZE) + 1;
        const rows = await api.getDailyUpdates(0, current, PAGE_SIZE, selectedSource || undefined);
        set((state) => ({
          contentData: current === 1 ? rows : [...state.contentData, ...rows],
          pageStart: pageStart + PAGE_SIZE,
          hasMore: rows.length === PAGE_SIZE,
        }));
      } else if (selectedCategory.kind === "pid" && selectedCategory.pid != null) {
        const current = Math.floor(pageStart / PAGE_SIZE) + 1;
        const rows = await api.getClassifyPage(selectedCategory.pid, {
          current,
          source: selectedSource || undefined,
        });
        set((state) => ({
          contentData: current === 1 ? rows : [...state.contentData, ...rows],
          pageStart: pageStart + PAGE_SIZE,
          hasMore: rows.length === PAGE_SIZE,
        }));
      } else {
        set({ hasMore: false });
      }
    } catch (err: any) {
      let errorMessage = "加载失败，请重试";

      if (err.message === "API_URL_NOT_SET") {
        errorMessage = "请点击右上角设置按钮，配置您的服务器地址";
      } else if (err.message === "UNAUTHORIZED") {
        // 会话超时：API 层已尝试自动重登并重试，仍失败说明重登也没成功，
        // 此时才提示用户重新登录（登录框由 restoreSession 弹出）。
        errorMessage = "认证失败，请重新登录";
      } else if (err.message.includes("Network")) {
        errorMessage = "网络连接失败，请检查网络连接";
      } else if (err.message.includes("timeout")) {
        errorMessage = "请求超时，请检查网络或服务器状态";
      } else if (err.message.includes("404")) {
        errorMessage = "服务器API路径不正确，请检查服务器配置";
      } else if (err.message.includes("500")) {
        errorMessage = "服务器内部错误，请联系管理员";
      } else if (err.message.includes("403")) {
        errorMessage = "访问被拒绝，请检查权限设置";
      }

      set({ error: errorMessage });
    } finally {
      set({ loading: false, loadingMore: false });
    }
  },

  selectCategory: (category: Category) => {
    const currentCategory = get().selectedCategory;

    if (currentCategory.title !== category.title || currentCategory.kind !== category.kind || currentCategory.tag !== category.tag) {
      set({
        selectedCategory: category,
        contentData: [],
        pageStart: 0,
        hasMore: true,
        error: null,
      });
      // 不在这里加载：首页 effect 监听 selectedCategory 统一触发，避免重复请求
    }
  },

  refreshPlayRecords: async () => {
    const { apiBaseUrl } = useSettingsStore.getState();
    // 设置尚未加载完成（apiBaseUrl 为空）时无法判断登录态，直接跳过，
    // 避免冷启动首帧（子组件 focus 早于 loadSettings 完成）误删"最近播放"分类。
    if (!apiBaseUrl) return;
    await useAuthStore.getState().checkLoginStatus(apiBaseUrl);
    const { isLoggedIn } = useAuthStore.getState();
    if (!isLoggedIn) {
      set((state) => {
        const recordCategoryExists = state.categories.some((c) => c.kind === "record");
        if (recordCategoryExists) {
          const newCategories = state.categories.filter((c) => c.kind !== "record");
          if (state.selectedCategory.kind === "record") {
            get().selectCategory(newCategories[0] || null);
          }
          return { categories: newCategories };
        }
        return {};
      });
      return;
    }
    const records = await PlayRecordManager.getAll();
    const hasRecords = Object.keys(records).length > 0;
    let categoriesChanged = false;
    set((state) => {
      const recordCategoryExists = state.categories.some((c) => c.kind === "record");
      if (hasRecords && !recordCategoryExists) {
        categoriesChanged = true;
        return { categories: [initialCategories[0], ...state.categories] };
      }
      if (!hasRecords && recordCategoryExists) {
        categoriesChanged = true;
        const newCategories = state.categories.filter((c) => c.kind !== "record");
        if (state.selectedCategory.kind === "record") {
          get().selectCategory(newCategories[0] || null);
        }
        return { categories: newCategories };
      }
      return {};
    });

    // 分类栏没变化时不再重拉内容：每次聚焦都 fetchInitialData 会把首页网格清空，
    // 表现为"返回首页白屏很久"；只有当前停在"最近播放"或分类栏刚增删才需要刷新。
    if (!categoriesChanged && get().selectedCategory.kind !== "record") {
      return;
    }
    await get().fetchInitialData();
  },

  clearError: () => {
    set({ error: null });
  },
}));

export default useHomeStore;
