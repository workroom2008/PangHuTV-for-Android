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

const FOCUS_KEY = "settings.liveStream";

interface LiveStreamSectionProps {
  onChanged: () => void;
  onFocus?: () => void;
  onBlur?: () => void;
  onPress?: () => void;
}

export interface LiveStreamSectionRef {
  setInputValue: (value: string) => void;
}

/**
 * 直播源地址区块。
 * TV 上输入框不参与方向键焦点（详见 APIConfigSection 注释），
 * 由 Pressable 行承载焦点，按 OK 才进入编辑。
 */
export const LiveStreamSection = forwardRef<LiveStreamSectionRef, LiveStreamSectionProps>(
  ({ onChanged, onFocus, onBlur, onPress }, ref) => {
    const { m3uUrl, setM3uUrl, remoteInputEnabled } = useSettingsStore();
    const { serverUrl } = useRemoteControlStore();
    const [isEditing, setIsEditing] = useState(false);
    const [isRowFocused, setIsRowFocused] = useState(false);
    const inputRef = useRef<TextInput>(null);
    const rowRef = useRef<any>(null);
    const animationStyle = useButtonAnimation(isRowFocused || isEditing, 1.01);
    const deviceType = useResponsiveLayout().deviceType;
    const isTV = deviceType === "tv";
    const focusRegistry = useSettingsFocus();

    const handleUrlChange = (url: string) => {
      setM3uUrl(url);
      onChanged();
    };

    useImperativeHandle(ref, () => ({
      setInputValue: (value: string) => {
        setM3uUrl(value);
        onChanged();
      },
    }));

    const handleRowFocus = () => {
      setIsRowFocused(true);
      onFocus?.();
    };

    const handleRowBlur = () => {
      setIsRowFocused(false);
      onBlur?.();
    };

    const handleRowPress = () => {
      setIsEditing(true);
      onPress?.();
      setTimeout(() => inputRef.current?.focus(), 60);
    };

    const exitEditing = useCallback(() => {
      setIsEditing(false);
      setTimeout(() => rowRef.current?.focus?.(), 60);
    }, []);

    const focusSelf = useCallback(() => rowRef.current?.focus?.(), []);

    useEffect(() => {
      focusRegistry.register({ key: FOCUS_KEY, focus: focusSelf });
      return () => focusRegistry.unregister(FOCUS_KEY);
    }, [focusRegistry, focusSelf]);

    return (
      <SettingsSection focusable onFocus={handleRowFocus} onBlur={handleRowBlur}>
        <View style={styles.inputContainer}>
          <View style={styles.titleContainer}>
            <ThemedText style={styles.sectionTitle}>直播源地址</ThemedText>
            {remoteInputEnabled && serverUrl && (
              <ThemedText style={styles.subtitle}>用手机访问 {serverUrl}，可远程输入</ThemedText>
            )}
          </View>
          <Animated.View style={animationStyle}>
            {isTV ? (
              <Pressable
                ref={rowRef}
                focusable
                style={[styles.input, styles.rowPressable, (isRowFocused || isEditing) && styles.inputFocused]}
                onFocus={handleRowFocus}
                onBlur={handleRowBlur}
                onPress={handleRowPress}
              >
                {isEditing ? (
                  <TextInput
                    ref={inputRef}
                    focusable={false}
                    autoFocus
                    style={styles.inlineInput}
                    value={m3uUrl}
                    onChangeText={handleUrlChange}
                    placeholder="输入 M3U 直播源地址"
                    placeholderTextColor="#888"
                    autoCapitalize="none"
                    autoCorrect={false}
                    onBlur={exitEditing}
                    onSubmitEditing={exitEditing}
                  />
                ) : (
                  <ThemedText style={styles.rowValue} numberOfLines={1}>
                    {m3uUrl || "未设置"}
                  </ThemedText>
                )}
              </Pressable>
            ) : (
              <TextInput
                ref={inputRef}
                style={[styles.input, isRowFocused && styles.inputFocused]}
                value={m3uUrl}
                onChangeText={handleUrlChange}
                placeholder="输入 M3U 直播源地址"
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

LiveStreamSection.displayName = "LiveStreamSection";

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
