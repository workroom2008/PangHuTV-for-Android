import React, { useState, useEffect, useRef, useImperativeHandle, forwardRef, useCallback } from "react";
import { TextInput, StyleSheet, Pressable, View } from "react-native";
import { ThemedText } from "@/components/ThemedText";
import { ThemedView } from "@/components/ThemedView";
import { LoginCredentialsManager } from "@/services/storage";
import { useSettingsFocus } from "@/hooks/useSettingsFocus";
import { useResponsiveLayout } from "@/hooks/useResponsiveLayout";
import { Colors } from "@/constants/Colors";

const FOCUS_KEY_USERNAME = "settings.account.username";
const FOCUS_KEY_PASSWORD = "settings.account.password";

export interface AccountSectionRef {
  setUsernameValue: (value: string) => void;
  setPasswordValue: (value: string) => void;
}

interface AccountSectionProps {
  username: string;
  password: string;
  setUsername: (v: string) => void;
  setPassword: (v: string) => void;
  onFocus?: () => void;
  onBlur?: () => void;
}

/**
 * 设置页账号区。
 *
 * TV 上用户名/密码不直接参与遥控器焦点（TextInput 抢焦点会挂输入法，
 * 方向键被 IME 吃掉）。改为 Pressable 行承载焦点，按 OK 才进入编辑。
 */
export const AccountSection = forwardRef<AccountSectionRef, AccountSectionProps>(
  ({ username, password, setUsername, setPassword, onFocus, onBlur }, ref) => {
    const usernameRef = useRef<TextInput>(null);
    const passwordRef = useRef<TextInput>(null);
    const usernameRowRef = useRef<any>(null);
    const passwordRowRef = useRef<any>(null);
    const [focusedField, setFocusedField] = useState<"username" | "password" | null>(null);
    const [editing, setEditing] = useState<"username" | "password" | null>(null);
    const deviceType = useResponsiveLayout().deviceType;
    const isTV = deviceType === "tv";
    const focusRegistry = useSettingsFocus();

    // 首次挂载用已存凭据回填（父级 state 为空时）
    const filledRef = useRef(false);
    useEffect(() => {
      let mounted = true;
      LoginCredentialsManager.get().then((creds) => {
        if (mounted && !filledRef.current && creds?.username) {
          filledRef.current = true;
          if (!username) setUsername(creds.username);
          if (!password) setPassword(creds.password);
        }
      });
      return () => {
        mounted = false;
      };
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    useImperativeHandle(ref, () => ({
      setUsernameValue: setUsername,
      setPasswordValue: setPassword,
    }));

    const focusUsername = useCallback(() => usernameRowRef.current?.focus?.(), []);
    const focusPassword = useCallback(() => passwordRowRef.current?.focus?.(), []);

    // 注册到设置页焦点链（用户名 → 密码）
    useEffect(() => {
      focusRegistry.register({ key: FOCUS_KEY_USERNAME, focus: focusUsername });
      focusRegistry.register({ key: FOCUS_KEY_PASSWORD, focus: focusPassword });
      return () => {
        focusRegistry.unregister(FOCUS_KEY_USERNAME);
        focusRegistry.unregister(FOCUS_KEY_PASSWORD);
      };
    }, [focusRegistry, focusUsername, focusPassword]);

    const startEdit = (field: "username" | "password") => {
      setEditing(field);
      setTimeout(() => {
        (field === "username" ? usernameRef : passwordRef).current?.focus();
      }, 60);
    };

    const endEdit = (field: "username" | "password") => {
      setEditing(null);
      setTimeout(() => {
        (field === "username" ? usernameRowRef : passwordRowRef).current?.focus?.();
      }, 60);
    };

    const rowStyles = (focused: boolean) => [styles.input, styles.rowPressable, focused && styles.inputFocused];

    return (
      <ThemedView style={styles.section}>
        <ThemedText style={styles.sectionTitle}>账号</ThemedText>
        <ThemedText style={styles.subtitle}>
          配合上方 API 地址使用，保存后自动登录（可用手机远程输入填充）
        </ThemedText>

        {isTV ? (
          <>
            <Pressable
              ref={usernameRowRef}
              focusable
              style={rowStyles(focusedField === "username")}
              onFocus={() => { setFocusedField("username"); onFocus?.(); }}
              onBlur={() => { setFocusedField(null); onBlur?.(); }}
              onPress={() => startEdit("username")}
            >
              {editing === "username" ? (
                <TextInput
                  ref={usernameRef}
                  focusable={false}
                  autoFocus
                  style={styles.inlineInput}
                  value={username}
                  onChangeText={setUsername}
                  placeholder="用户名"
                  placeholderTextColor="#888"
                  autoCapitalize="none"
                  autoCorrect={false}
                  onBlur={() => endEdit("username")}
                  onSubmitEditing={() => endEdit("username")}
                />
              ) : (
                <View style={styles.rowInner}>
                  <ThemedText style={styles.rowLabel}>用户名</ThemedText>
                  <ThemedText style={styles.rowValue} numberOfLines={1}>
                    {username || "未设置"}
                  </ThemedText>
                </View>
              )}
            </Pressable>

            <Pressable
              ref={passwordRowRef}
              focusable
              style={rowStyles(focusedField === "password")}
              onFocus={() => { setFocusedField("password"); onFocus?.(); }}
              onBlur={() => { setFocusedField(null); onBlur?.(); }}
              onPress={() => startEdit("password")}
            >
              {editing === "password" ? (
                <TextInput
                  ref={passwordRef}
                  focusable={false}
                  autoFocus
                  style={styles.inlineInput}
                  value={password}
                  onChangeText={setPassword}
                  placeholder="密码"
                  placeholderTextColor="#888"
                  secureTextEntry
                  autoCapitalize="none"
                  autoCorrect={false}
                  onBlur={() => endEdit("password")}
                  onSubmitEditing={() => endEdit("password")}
                />
              ) : (
                <View style={styles.rowInner}>
                  <ThemedText style={styles.rowLabel}>密码</ThemedText>
                  <ThemedText style={styles.rowValue} numberOfLines={1}>
                    {password ? "••••••••" : "未设置"}
                  </ThemedText>
                </View>
              )}
            </Pressable>
          </>
        ) : (
          <>
            <TextInput
              ref={usernameRef}
              style={styles.input}
              value={username}
              onChangeText={setUsername}
              placeholder="用户名"
              placeholderTextColor="#888"
              autoCapitalize="none"
              autoCorrect={false}
              onFocus={() => { setFocusedField("username"); onFocus?.(); }}
              onBlur={() => { setFocusedField(null); onBlur?.(); }}
            />
            <TextInput
              ref={passwordRef}
              style={styles.input}
              value={password}
              onChangeText={setPassword}
              placeholder="密码"
              placeholderTextColor="#888"
              secureTextEntry
              autoCapitalize="none"
              autoCorrect={false}
              onFocus={() => { setFocusedField("password"); onFocus?.(); }}
              onBlur={() => { setFocusedField(null); onBlur?.(); }}
            />
          </>
        )}
      </ThemedView>
    );
  }
);

AccountSection.displayName = "AccountSection";

const styles = StyleSheet.create({
  section: {
    marginHorizontal: 16,
    marginVertical: 8,
    padding: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#333",
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: "bold",
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 12,
    color: "#888",
    fontStyle: "italic",
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
    marginBottom: 12,
  },
  rowPressable: {
    justifyContent: "center",
  },
  rowInner: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
  },
  rowLabel: {
    fontSize: 14,
    color: "#999",
  },
  rowValue: {
    fontSize: 16,
    color: "white",
    flexShrink: 1,
    marginLeft: 12,
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
