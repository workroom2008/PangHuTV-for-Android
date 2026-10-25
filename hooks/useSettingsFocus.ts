import { createContext, useContext } from "react";

/**
 * 设置页 TV 焦点注册表。
 *
 * 背景（OEM Android 6 电视实测）：
 * - 页面主体在 KeyboardAwareScrollView / ScrollView 里，控件又嵌在自定义容器内，
 *   原生焦点搜索拿不到可靠的上下相邻关系，方向键下移会"卡在 API 地址输入框"；
 * - 多个 TextInput 上下紧邻时，原生搜索更倾向留在当前节点。
 *
 * 方案：各区块把自己的"可聚焦控件"按视觉顺序注册进来，
 * 页面级用 useTVEventHandler 按下标显式 focus 下一个/上一个，保证一定能下移。
 */
export type FocusNode = {
  /** 稳定标识，用于排序与去重 */
  key: string;
  /** 执行聚焦 */
  focus: () => void;
  /** 失焦（可选，用于收起键盘/高亮） */
  blur?: () => void;
};

type Registry = {
  register: (node: FocusNode) => void;
  unregister: (key: string) => void;
  /** 按稳定 key 聚焦（页面按视觉顺序显式驱动时使用） */
  focusKey: (key: string) => boolean;
  focusNext: (currentKey?: string) => boolean;
  focusPrev: (currentKey?: string) => boolean;
  focusFirst: () => boolean;
};

const noopRegistry: Registry = {
  register: () => {},
  unregister: () => {},
  focusKey: () => false,
  focusNext: () => false,
  focusPrev: () => false,
  focusFirst: () => false,
};

export const SettingsFocusContext = createContext<Registry>(noopRegistry);

export const useSettingsFocus = () => useContext(SettingsFocusContext);
