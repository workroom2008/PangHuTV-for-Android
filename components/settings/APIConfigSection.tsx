import React, { useState, useRef, useImperativeHandle, forwardRef, useCallback, useEffect } from "react";
import { View, TextInput, StyleSheet, Animated, Pressable } from "react-native";
import { ThemedText } from "@/components/ThemedText";
import { SettingsSection } from "./SettingsSection";
import { useSettingsFocus } from "@/hooks/useSettingsFocus";
import { useSettingsStore } from "@/stores/settingsStore";
import { useRemoteControlStore } from "@/stores/remoteControlStore";
import { useButtonAnimation } from "@/hooks/useAnimation";
import { Colors } from "@/constants/Colors";
import { useResponsiveLayout } from "@/hooks/useResponsiveLayout";

const FOCUS_KEY = "settings.api";

interface APIConfigSectionProps {
  onChanged: () => void;
  onFocus?: () => void;
  onBlur?: () => void;
  onPress?: () => void;
  hideDescription?: boolean;
}

export interface APIConfigSectionRef {
  setInputValue: (value: string) => void;
}

/**
 * API 地址区块。
 *
 * TV 关键点：**输入框不直接参与遥控器焦点**。
 * 老 OEM Android TV 上 TextInput 一旦获得焦点就会挂输入法，
 * 方向键被 PinyinIME 吃掉，导致整页"遥控器不能下移、鼠标却能用"。
 *
 * 做法：用一个 Pressable 行承载焦点（可上下移动），按 OK 才把真实输入框
 * 临时聚焦（setEditable + focus）唤起软键盘/远程输入；失焦后收起。
 */
export const APIConfigSection = forwardRef<APIConfigSectionRef, APIConfigSectionProps>(
  ({ onChanged, onFocus, onBlur, onPress, hideDescription = false }, ref) => {
    const { apiBaseUrl, setApiBaseUrl, remoteInputEnabled } = useSettingsStore();
    const { serverUrl } = useRemoteControlStore();
    const [isEditing, setIsEditing] = useState(false);
    const [isRowFocused, setIsRowFocused] = useState(false);
    const inputRef = useRef<TextInput>(null);
    const rowRef = useRef<any>(null);
    const rowAnimationStyle = useButtonAnimation(isRowFocused || isEditing, 1.01);
    const deviceType = useResponsiveLayout().deviceType;
    const isTV = deviceType === "tv";
    const focusRegistry = useSettingsFocus();

    const handleUrlChange = (url: string) => {
      setApiBaseUrl(url);
      onChanged();
    };

    useImperativeHandle(ref, () => ({
      setInputValue: (value: string) => {
        setApiBaseUrl(value);
        onChanged();
      },
    }));

    const handleRowFocus = useCallback(() => {
      setIsRowFocused(true);
      onFocus?.();
    }, [onFocus]);

    const handleRowBlur = useCallback(() => {
      setIsRowFocused(false);
      onBlur?.();
    }, [onBlur]);

    /** 按 OK：进入编辑态并聚焦输入框 */
    const handleRowPress = useCallback(() => {
      setIsEditing(true);
      onPress?.();
      setTimeout(() => inputRef.current?.focus(), 60);
    }, [onPress]);

    /** 编辑结束（失焦或按下返回）：退出编辑态，焦点还给行 */
    const exitEditing = useCallback(() => {
      setIsEditing(false);
      setTimeout(() => rowRef.current?.focus?.(), 60);
    }, []);

    // 注册到设置页焦点链
    const focusSelf = useCallback(() => {
      rowRef.current?.focus?.();
    }, []);

    useEffect(() => {
      focusRegistry.register({ key: FOCUS_KEY, focus: focusSelf });
      return () => focusRegistry.unregister(FOCUS_KEY);
    }, [focusRegistry, focusSelf]);

    const displayValue = apiBaseUrl || "未设置";

    return (
      <SettingsSection focusable onFocus={handleRowFocus} onBlur={handleRowBlur}>
        <View style={styles.inputContainer}>
          <View style={styles.titleContainer}>
            <ThemedText style={styles.sectionTitle}>API 地址</ThemedText>
            {!hideDescription && remoteInputEnabled && serverUrl && (
              <ThemedText style={styles.subtitle}>用手机访问 {serverUrl}，可远程输入</ThemedText>
            )}
          </View>

          <Animated.View style={rowAnimationStyle}>
            {isTV ? (
              <Pressable
                ref={rowRef}
                focusable
                style={[
                  styles.input,
                  styles.rowPressable,
                  (isRowFocused || isEditing) && styles.inputFocused,
                ]}
                onFocus={handleRowFocus}
                onBlur={handleRowBlur}
                onPress={handleRowPress}
              >
                {isEditing ? (
                  <TextInput
                    ref={inputRef}
                    focusable={false}
                    style={styles.inlineInput}
                    value={apiBaseUrl}
                    onChangeText={handleUrlChange}
                    placeholder="输入服务器地址"
                    placeholderTextColor="#888"
                    autoCapitalize="none"
                    autoCorrect={false}
                    autoFocus
                    onBlur={exitEditing}
                    onSubmitEditing={exitEditing}
                  />
                ) : (
                  <ThemedText style={styles.rowValue} numberOfLines={1}>
                    {displayValue}
                  </ThemedText>
                )}
              </Pressable>
            ) : (
              <TextInput
                ref={inputRef}
                style={[styles.input, isRowFocused && styles.inputFocused]}
                value={apiBaseUrl}
                onChangeText={handleUrlChange}
                placeholder="输入服务器地址"
                placeholderTextColor="#888"
                autoCapitalize="none"
                autoCorrect={false}
                onFocus={handleRowFocus}
                onBlur={handleRowBlur}
              />
            )}
          </Animated.View>
        </View>
      </SettingsSection>
    );
  }
);

APIConfigSection.displayName = "APIConfigSection";

const styles = StyleSheet.create({
  titleContainer: {
    flexDirection: "row",
    alignItems: "center",
    marginBottom: 8,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: "bold",
    marginRight: 12,
  },
  subtitle: {
    fontSize: 12,
    color: "#888",
    fontStyle: "italic",
  },
  inputContainer: {
    marginBottom: 12,
  },
  label: {
    fontSize: 16,
    marginBottom: 8,
    color: "#ccc",
  },
  input: {
    height: 50,
    borderWidth: 2,
    borderRadius: 8,
    paddingHorizontal: 15,
    fontSize: 16,
    backgroundColor: "#3a3a3c",
    color: "white",
    borderColor: "transparent",
  },
  rowPressable: {
    justifyContent: "center",
  },
  rowValue: {
    fontSize: 16,
    color: "white",
  },
  inlineInput: {
    flex: 1,
    fontSize: 16,
    color: "white",
    padding: 0,
  },
  inputFocused: {
    borderColor: Colors.dark.primary,
    shadowColor: Colors.dark.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.8,
    shadowRadius: 10,
    elevation: 5,
  },
});
