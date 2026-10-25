import React, { useState, useCallback } from "react";
import { StyleSheet, View, Platform, StyleProp, ViewStyle } from "react-native";
import { ThemedView } from "@/components/ThemedView";
import { Colors } from "@/constants/Colors";
import { useResponsiveLayout } from "@/hooks/useResponsiveLayout";

interface SettingsSectionProps {
  children: React.ReactNode;
  onFocus?: () => void;
  onBlur?: () => void;
  onPress?: () => void;
  /** 是否显示高亮（由内部控件 onFocus/onBlur 驱动） */
  focusable?: boolean;
  style?: StyleProp<ViewStyle>;
}

/**
 * 设置页区块容器。
 *
 * TV 焦点策略（react-native-tvos / OEM Android 6 实测）：
 * 容器自己**不再**作为焦点节点。原因：
 * - 容器 Pressable 可聚焦时，焦点停在容器上，方向键下移会原地不动
 *   （表现为"设置里遥控器不能下移"）；
 * - 容器与内部 TextInput 同时可聚焦，两层焦点互相覆盖，还会丢焦点框。
 *
 * 现在焦点完全由内部控件承担：TextInput / Pressable 行各自可聚焦，
 * 纵向排列天然形成 上↑下↓ 顺序。
 */
export const SettingsSection: React.FC<SettingsSectionProps> = ({
  children,
  onFocus,
  onBlur,
  focusable = false,
  style,
}) => {
  const [isFocused, setIsFocused] = useState(false);
  const { deviceType } = useResponsiveLayout();
  const isTV = deviceType === "tv" || Platform.isTV;

  const handleFocus = useCallback(() => {
    setIsFocused(true);
    onFocus?.();
  }, [onFocus]);

  const handleBlur = useCallback(() => {
    setIsFocused(false);
    onBlur?.();
  }, [onBlur]);

  return (
    <ThemedView
      style={[styles.section, focusable && isFocused && styles.sectionFocused, style]}
    >
      <View style={styles.sectionInner}>{children}</View>
    </ThemedView>
  );
};

/** 供区块内的可聚焦控件使用：统一挂焦点高亮回调 */
export function useSectionFocusHandlers(onFocus?: () => void, onBlur?: () => void) {
  const handleFocus = useCallback(() => onFocus?.(), [onFocus]);
  const handleBlur = useCallback(() => onBlur?.(), [onBlur]);
  return { handleFocus, handleBlur };
}

const styles = StyleSheet.create({
  section: {
    padding: 20,
    marginBottom: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#333",
  },
  sectionFocused: {
    borderColor: Colors.dark.primary,
    backgroundColor: "#007AFF10",
  },
  sectionInner: {
    width: "100%",
  },
});
