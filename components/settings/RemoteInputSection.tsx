import React, { useCallback, useEffect, useRef } from "react";
import { View, Switch, StyleSheet, Pressable, Animated, Platform, TouchableOpacity, TVEventHandler } from "react-native";
import QRCode from "react-native-qrcode-svg";
import { ThemedText } from "@/components/ThemedText";
import { SettingsSection } from "./SettingsSection";
import { useSettingsStore } from "@/stores/settingsStore";
import { useRemoteControlStore } from "@/stores/remoteControlStore";
import { useSettingsFocus } from "@/hooks/useSettingsFocus";
import { useButtonAnimation } from "@/hooks/useAnimation";
import { Colors } from "@/constants/Colors";
import { useResponsiveLayout } from "@/hooks/useResponsiveLayout";

const FOCUS_KEY = "settings.remoteInput";

interface RemoteInputSectionProps {
  onChanged: () => void;
  onFocus?: () => void;
  onBlur?: () => void;
  onPress?: () => void;
  /** 把"切换开关"交给页面级 select 分发，避免各区块自己抢 TV 事件 */
  onRegisterToggle?: (fn: () => void) => void;
}

export const RemoteInputSection: React.FC<RemoteInputSectionProps> = ({
  onChanged,
  onFocus,
  onBlur,
  onPress,
  onRegisterToggle,
}) => {
  const { remoteInputEnabled, setRemoteInputEnabled } = useSettingsStore();
  const { isServerRunning, serverUrl, error } = useRemoteControlStore();
  const [isFocused, setIsFocused] = React.useState(false);
  const animationStyle = useButtonAnimation(isFocused, 1.2);
  const deviceType = useResponsiveLayout().deviceType;
  const pressableRef = useRef<any>(null);
  const focusRegistry = useSettingsFocus();

  const handleToggle = useCallback(
    (enabled: boolean) => {
      setRemoteInputEnabled(enabled);
      onChanged();
    },
    [setRemoteInputEnabled, onChanged]
  );

  const handleSectionFocus = () => {
    setIsFocused(true);
    onFocus?.();
  };

  const handleSectionBlur = () => {
    setIsFocused(false);
    onBlur?.();
  };

  const handlePress = useCallback(() => {
    handleToggle(!remoteInputEnabled);
  }, [handleToggle, remoteInputEnabled]);

  // 把切换动作登记给设置页：TV 上由页面级 select 事件统一调用
  useEffect(() => {
    onRegisterToggle?.(handlePress);
  }, [onRegisterToggle, handlePress]);

  const focusSelf = useCallback(() => {
    pressableRef.current?.focus?.();
    // 焦点链进入本行即视为聚焦（原生 focus 事件在 OEM TV 上不一定回调）
    setIsFocused(true);
    onFocus?.();
  }, [onFocus]);

  // 注册到设置页焦点链（第一项）
  useEffect(() => {
    focusRegistry.register({ key: FOCUS_KEY, focus: focusSelf });
    return () => focusRegistry.unregister(FOCUS_KEY);
  }, [focusRegistry, focusSelf]);

  // TV遥控器事件处理
  // 遥控器交给原生焦点系统：方向键在可聚焦控件间移动，select 由 Pressable.onPress 处理。
  // 这里不再用 useTVEventHandler 抢事件（会和焦点移动互相覆盖，导致设置页下移卡住）。

  return (
    <SettingsSection focusable onFocus={handleSectionFocus} onBlur={handleSectionBlur}>
      <Pressable
        ref={pressableRef}
        focusable
        hasTVPreferredFocus={false}
        style={[styles.settingItem, isFocused && styles.settingItemFocused]}
        onFocus={handleSectionFocus}
        onBlur={handleSectionBlur}
        onPress={handlePress}
      >
        <View style={styles.settingInfo}>
          <ThemedText style={styles.settingName}>启用远程输入</ThemedText>
        </View>
        <Animated.View style={animationStyle}>
          { Platform.OS === 'ios' && Platform.isTV ? (
            <View style={styles.statusLabel}>
              <ThemedText style={styles.statusValue}>{remoteInputEnabled ? '已启用' : '已禁用'}</ThemedText>
            </View>
          ) : (
            <Switch
              value={remoteInputEnabled}
              onValueChange={() => { }} // 禁用Switch的直接交互，交给外层 Pressable
              trackColor={{ false: "#767577", true: Colors.dark.primary }}
              thumbColor={remoteInputEnabled ? "#ffffff" : "#f4f3f4"}
              pointerEvents="none"
            />
          )
          }
        </Animated.View>
      </Pressable>

      {remoteInputEnabled && (
        <View style={styles.statusContainer}>
          <View style={styles.qrRow}>
            {isServerRunning && serverUrl ? (
              <View style={styles.qrBox}>
                <QRCode value={serverUrl} size={128} color="#000000" backgroundColor="#FFFFFF" />
              </View>
            ) : (
              <View style={[styles.qrBox, styles.qrPlaceholder]}>
                <ThemedText style={styles.qrPlaceholderText}>等待服务启动…</ThemedText>
              </View>
            )}
            <View style={styles.qrInfo}>
              <ThemedText style={styles.qrTitle}>扫码远程配置</ThemedText>
              <ThemedText style={styles.qrTip}>
                手机扫码打开配置页，可填写服务器地址、用户名、密码、直播源，保存后电视立即生效
              </ThemedText>
              {serverUrl && (
                <>
                  <ThemedText style={styles.qrUrl}>{serverUrl}</ThemedText>
                  <ThemedText style={styles.qrTip}>
                    手机打不开时：确认手机与电视在同一 WiFi（非访客网络、未开 AP 隔离），
                    或手机浏览器直接输入上面这个地址。
                  </ThemedText>
                </>
              )}
            </View>
          </View>

          <View style={styles.statusItem}>
            <ThemedText style={styles.statusLabel}>服务状态：</ThemedText>
            <ThemedText style={[styles.statusValue, { color: isServerRunning ? Colors.dark.primary : "#FF6B6B" }]}>
              {isServerRunning ? "运行中" : "已停止"}
            </ThemedText>
          </View>

          {error && (
            <View style={styles.statusItem}>
              <ThemedText style={styles.statusLabel}>错误：</ThemedText>
              <ThemedText style={[styles.statusValue, { color: "#FF6B6B" }]}>{error}</ThemedText>
            </View>
          )}
        </View>
      )}
    </SettingsSection>
  );
};

const styles = StyleSheet.create({
  settingItem: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    paddingVertical: 12,
    paddingHorizontal: 8,
    borderRadius: 8,
    borderWidth: 2,
    borderColor: "transparent",
  },
  settingItemFocused: {
    borderColor: Colors.dark.primary,
    backgroundColor: "#007AFF22",
  },
  settingInfo: {
    flex: 1,
  },
  settingName: {
    fontSize: 16,
    fontWeight: "bold",
    marginBottom: 4,
  },
  settingDescription: {
    fontSize: 14,
    color: "#888",
  },
  statusContainer: {
    marginTop: 16,
    padding: 16,
    backgroundColor: "#2a2a2c",
    borderRadius: 8,
  },
  qrRow: {
    flexDirection: "row",
    alignItems: "center",
    marginBottom: 16,
  },
  qrBox: {
    padding: 10,
    backgroundColor: "#FFFFFF",
    borderRadius: 10,
    marginRight: 16,
  },
  qrPlaceholder: {
    width: 128,
    height: 128,
    backgroundColor: "#3a3a3c",
    alignItems: "center",
    justifyContent: "center",
  },
  qrPlaceholderText: {
    fontSize: 12,
    color: "#888",
    textAlign: "center",
  },
  qrInfo: {
    flex: 1,
  },
  qrTitle: {
    fontSize: 16,
    fontWeight: "bold",
    marginBottom: 6,
  },
  qrTip: {
    fontSize: 12,
    color: "#999",
    lineHeight: 18,
    marginBottom: 6,
  },
  qrUrl: {
    fontSize: 12,
    color: Colors.dark.primary,
  },
  statusItem: {
    flexDirection: "row",
    marginBottom: 8,
  },
  statusLabel: {
    fontSize: 14,
    color: "#ccc",
    minWidth: 80,
  },
  statusValue: {
    fontSize: 14,
    flex: 1,
  },
  actionButtons: {
    flexDirection: "row",
    gap: 12,
    marginTop: 12,
  },
  actionButton: {
    flex: 1,
  },
});
