import React, { useCallback, useMemo, useRef, useState } from "react";
import { SettingsFocusContext, FocusNode } from "@/hooks/useSettingsFocus";

/**
 * 设置页焦点注册表实现。
 *
 * 用 ref 保存节点顺序，避免每次注册触发重渲染；
 * 顺序按注册先后（区块渲染顺序即视觉顺序）。
 */
export function useSettingsFocusRegistry() {
  const nodesRef = useRef<FocusNode[]>([]);
  const [, forceRender] = useState(0);

  const register = useCallback((node: FocusNode) => {
    const list = nodesRef.current;
    const idx = list.findIndex((n) => n.key === node.key);
    if (idx >= 0) {
      list[idx] = node;
    } else {
      list.push(node);
    }
    forceRender((v) => v + 1);
  }, []);

  const unregister = useCallback((key: string) => {
    nodesRef.current = nodesRef.current.filter((n) => n.key !== key);
    forceRender((v) => v + 1);
  }, []);

  const focusAt = useCallback((index: number) => {
    const list = nodesRef.current;
    if (list.length === 0) return false;
    const target = list[Math.max(0, Math.min(index, list.length - 1))];
    if (!target) return false;
    target.focus();
    return true;
  }, []);

  const indexOf = useCallback((key?: string) => {
    if (!key) return -1;
    return nodesRef.current.findIndex((n) => n.key === key);
  }, []);

  const value = useMemo(
    () => ({
      register,
      unregister,
      focusNext: (currentKey?: string) => {
        const i = indexOf(currentKey);
        if (i < 0) return focusAt(0);
        return focusAt(i + 1);
      },
      focusPrev: (currentKey?: string) => {
        const i = indexOf(currentKey);
        if (i < 0) return focusAt(0);
        return focusAt(i - 1);
      },
      focusFirst: () => focusAt(0),
    }),
    [register, unregister, focusAt, indexOf]
  );

  return { value, nodesRef };
}
