import React, { useState, useEffect, useRef, useImperativeHandle, forwardRef, useCallback } from "react";
import { TextInput, StyleSheet } from "react-native";
import { ThemedText } from "@/components/ThemedText";
import { ThemedView } from "@/components/ThemedView";
import { LoginCredentialsManager } from "@/services/storage";
import { useSettingsFocus } from "@/hooks/useSettingsFocus";
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

/** 设置页账号区：API 地址下方配置用户名/密码，保存即登录；支持远程输入填充 */
export const AccountSection = forwardRef<AccountSectionRef, AccountSectionProps>(
  ({ username, password, setUsername, setPassword, onFocus, onBlur }, ref) => {
    const usernameRef = useRef<TextInput>(null);
    const passwordRef = useRef<TextInput>(null);
    const [focusedField, setFocusedField] = useState<"username" | "password" | null>(null);

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

    const focusRegistry = useSettingsFocus();
    const focusUsername = useCallback(() => usernameRef.current?.focus(), []);
    const focusPassword = useCallback(() => passwordRef.current?.focus(), []);

    // 注册到设置页焦点链（用户名 → 密码，按视觉顺序）
    useEffect(() => {
      focusRegistry.register({ key: FOCUS_KEY_USERNAME, focus: focusUsername });
      focusRegistry.register({ key: FOCUS_KEY_PASSWORD, focus: focusPassword });
      return () => {
        focusRegistry.unregister(FOCUS_KEY_USERNAME);
        focusRegistry.unregister(FOCUS_KEY_PASSWORD);
      };
    }, [focusRegistry, focusUsername, focusPassword]);

    const inputStyle = (focused: boolean) => [styles.input, focused && styles.inputFocused];

    return (
      <ThemedView style={styles.section}>
        <ThemedText style={styles.sectionTitle}>账号</ThemedText>
        <ThemedText style={styles.subtitle}>
          配合上方 API 地址使用，保存后自动登录（可用手机远程输入填充）
        </ThemedText>
        <TextInput
          ref={usernameRef}
          focusable
          style={inputStyle(focusedField === "username")}
          value={username}
          onChangeText={setUsername}
          placeholder="用户名"
          placeholderTextColor="#888"
          autoCapitalize="none"
          autoCorrect={false}
          onFocus={() => {
            setFocusedField("username");
            onFocus?.();
          }}
          onBlur={() => {
            setFocusedField(null);
            onBlur?.();
          }}
        />
        <TextInput
          ref={passwordRef}
          focusable
          style={inputStyle(focusedField === "password")}
          value={password}
          onChangeText={setPassword}
          placeholder="密码"
          placeholderTextColor="#888"
          secureTextEntry
          autoCapitalize="none"
          autoCorrect={false}
          onFocus={() => {
            setFocusedField("password");
            onFocus?.();
          }}
          onBlur={() => {
            setFocusedField(null);
            onBlur?.();
          }}
        />
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
  inputFocused: {
    borderColor: Colors.dark.primary,
    shadowColor: Colors.dark.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.8,
    shadowRadius: 10,
    elevation: 5,
  },
});
