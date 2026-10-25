import React, { useState, useRef, useImperativeHandle, forwardRef, useCallback, useEffect } from "react";
import { View, TextInput, StyleSheet, Animated, Platform } from "react-native";
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
  /** TV 焦点链：下移目标（Android TV 用 nativeID 定位） */
  nextFocusDown?: number;
  /** 进入页面默认焦点 */
  hasTVPreferredFocus?: boolean;
}

export interface APIConfigSectionRef {
  setInputValue: (value: string) => void;
}

export const APIConfigSection = forwardRef<APIConfigSectionRef, APIConfigSectionProps>(
  ({ onChanged, onFocus, onBlur, onPress, hideDescription = false, nextFocusDown, hasTVPreferredFocus = false }, ref) => {
    const { apiBaseUrl, setApiBaseUrl, remoteInputEnabled } = useSettingsStore();
    const { serverUrl } = useRemoteControlStore();
    const [isInputFocused, setIsInputFocused] = useState(false);
    const [isSectionFocused, setIsSectionFocused] = useState(false);
    const inputRef = useRef<TextInput>(null);
    const inputAnimationStyle = useButtonAnimation(isSectionFocused, 1.01);
    const deviceType = useResponsiveLayout().deviceType;
    const focusRegistry = useSettingsFocus();

    // 注册到设置页焦点链：遥控器上/下键由页面统一驱动，避免原生焦点搜索卡住
    const focusSelf = useCallback(() => {
      inputRef.current?.focus();
    }, []);

    useEffect(() => {
      const node = {
        key: FOCUS_KEY,
        focus: focusSelf,
        blur: () => inputRef.current?.blur(),
      };
      focusRegistry.register(node);
      return () => focusRegistry.unregister(FOCUS_KEY);
    }, [focusRegistry, focusSelf]);

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

    const handleSectionFocus = () => {
      setIsSectionFocused(true);
      onFocus?.();
    };

    const handleSectionBlur = () => {
      setIsSectionFocused(false);
      onBlur?.();
    };

    const handlePress = () => {
      inputRef.current?.focus();
      onPress?.();
    }

    // 遥控器 select 由 Pressable.onPress → handlePress 交给输入框聚焦；
    // 不再用 useTVEventHandler 全局抢 select（会与焦点移动互相覆盖）。

    const [selection, setSelection] = useState<{ start: number; end: number }>({
      start: 0,
      end: 0,
    });
    // 当用户手动移动光标或选中文本时，同步到 state（可选）
    const onSelectionChange = ({
      nativeEvent: { selection },
    }: any) => {
      setSelection(selection);
    };

    return (
      <SettingsSection focusable onFocus={handleSectionFocus} onBlur={handleSectionBlur}>
        <View style={styles.inputContainer}>
          <View style={styles.titleContainer}>
            <ThemedText style={styles.sectionTitle}>API 地址</ThemedText>
            {!hideDescription && remoteInputEnabled && serverUrl && (
              <ThemedText style={styles.subtitle}>用手机访问 {serverUrl}，可远程输入</ThemedText>
            )}
          </View>
          <Animated.View style={inputAnimationStyle}>
            <TextInput
              ref={inputRef}
              focusable
              hasTVPreferredFocus={hasTVPreferredFocus}
              nextFocusDown={nextFocusDown}
              style={[styles.input, isInputFocused && styles.inputFocused]}
              value={apiBaseUrl}
              onChangeText={handleUrlChange}
              placeholder="输入服务器地址"
              placeholderTextColor="#888"
              autoCapitalize="none"
              autoCorrect={false}
              onFocus={() => {
                setIsInputFocused(true);
                handleSectionFocus();
                // 将光标移动到文本末尾
                const end = apiBaseUrl.length;
                setSelection({ start: end, end: end });
                // 有时需要延迟一下，让系统先完成 focus 再设置 selection
                //（在 Android 上更可靠）
                setTimeout(() => {
                  // 对于受控的 selection 已经生效，这里仅作保险
                  inputRef.current?.setNativeProps({ selection: { start: end, end: end } });
                }, 0);
              }}
              selection={selection}
              onSelectionChange={onSelectionChange} // 可选

              onBlur={() => {
                setIsInputFocused(false);
                handleSectionBlur();
              }}
            />
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
  inputFocused: {
    borderColor: Colors.dark.primary,
    shadowColor: Colors.dark.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.8,
    shadowRadius: 10,
    elevation: 5,
  },
});
