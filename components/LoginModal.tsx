import React, { useState, useRef, useEffect } from "react";
import { View, TextInput, StyleSheet, ActivityIndicator, Alert, Keyboard, InteractionManager, Pressable, BackHandler } from "react-native";
import { usePathname } from "expo-router";
import Toast from "react-native-toast-message";
import useAuthStore from "@/stores/authStore";
import { useSettingsStore } from "@/stores/settingsStore";
import useHomeStore from "@/stores/homeStore";
import { api } from "@/services/api";
import { LoginCredentialsManager } from "@/services/storage";
import { ThemedView } from "./ThemedView";
import { ThemedText } from "./ThemedText";
import { StyledButton } from "./StyledButton";
import { Colors } from "@/constants/Colors";

/**
 * 登录遮罩层（不用 RN Modal：OEM Android 6 TV 上 Modal 内样式丢失且不可聚焦）。
 * 绝对定位全屏遮罩 + 居中卡片，参与普通渲染树，遥控焦点正常。
 */
const LoginModal = () => {
  const { isLoginModalVisible, hideLoginModal, checkLoginStatus } = useAuthStore();
  const { apiBaseUrl } = useSettingsStore();
  const { refreshPlayRecords } = useHomeStore();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const usernameInputRef = useRef<TextInput>(null);
  const passwordInputRef = useRef<TextInput>(null);
  const pathname = usePathname();
  const isSettingsPage = pathname.includes("settings");

  const visible = isLoginModalVisible && !isSettingsPage;

  // Load saved credentials when visible
  useEffect(() => {
    if (visible) {
      Keyboard.dismiss();
      const loadCredentials = async () => {
        const savedCredentials = await LoginCredentialsManager.get();
        if (savedCredentials) {
          setUsername(savedCredentials.username);
          setPassword(savedCredentials.password);
        }
      };
      loadCredentials();

      // 渲染稳定后聚焦用户名框
      const focusTimeout = setTimeout(() => {
        usernameInputRef.current?.focus();
      }, 300);
      return () => clearTimeout(focusTimeout);
    }
  }, [visible]);

  // 遮罩期间拦截返回键（防止底层页面被误触）
  useEffect(() => {
    if (!visible) return;
    const handler = BackHandler.addEventListener("hardwareBackPress", () => true);
    return () => handler.remove();
  }, [visible]);

  const handleLogin = async () => {
    if (!username || !password) {
      Toast.show({ type: "error", text1: "请输入用户名和密码" });
      return;
    }
    setIsLoading(true);
    try {
      await api.login(username, password);
      await checkLoginStatus(apiBaseUrl);
      await refreshPlayRecords();

      // Save credentials on successful login
      await LoginCredentialsManager.save({ username, password });

      Toast.show({ type: "success", text1: "登录成功" });

      const hideAndAlert = () => {
        Keyboard.dismiss();
        setTimeout(() => {
          Alert.alert(
            "免责声明",
            "本应用仅提供影视信息搜索服务，所有内容均来自第三方网站。本站不存储任何视频资源，不对任何内容的准确性、合法性、完整性负责。",
            [{ text: "确定" }]
          );
        }, 100);
      };
      InteractionManager.runAfterInteractions(hideAndAlert);
    } catch (error) {
      Toast.show({
        type: "error",
        text1: "登录失败",
        text2: error instanceof Error ? error.message : "用户名或密码错误",
      });
    } finally {
      setIsLoading(false);
    }
  };

  const handleUsernameSubmit = () => {
    passwordInputRef.current?.focus();
  };

  if (!visible) return null;

  return (
    <Pressable style={styles.overlay} onPress={(e) => e.stopPropagation()}>
      <ThemedView style={styles.container}>
        <ThemedText style={styles.title}>需要登录</ThemedText>
        <ThemedText style={styles.subtitle}>服务器需要验证您的身份</ThemedText>
        <TextInput
          ref={usernameInputRef}
          style={styles.input}
          placeholder="请输入用户名"
          placeholderTextColor="#888"
          value={username}
          onChangeText={setUsername}
          returnKeyType="next"
          onSubmitEditing={handleUsernameSubmit}
          blurOnSubmit={false}
          autoFocus
          allowFontScaling={false}
          textAlignVertical="center"
          underlineColorAndroid="transparent"
        />
        <TextInput
          ref={passwordInputRef}
          style={styles.input}
          placeholder="请输入密码"
          placeholderTextColor="#888"
          secureTextEntry
          value={password}
          onChangeText={setPassword}
          returnKeyType="go"
          onSubmitEditing={handleLogin}
          allowFontScaling={false}
          textAlignVertical="center"
          underlineColorAndroid="transparent"
        />
        <StyledButton
          text={isLoading ? "" : "登录"}
          onPress={handleLogin}
          disabled={isLoading}
          style={styles.button}
          hasTVPreferredFocus={false}
        >
          {isLoading && <ActivityIndicator color="#fff" />}
        </StyledButton>
      </ThemedView>
    </Pressable>
  );
};

const styles = StyleSheet.create({
  overlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: "rgba(0, 0, 0, 0.75)",
    justifyContent: "center",
    alignItems: "center",
    zIndex: 999,
    elevation: 999,
  },
  container: {
    width: 460,
    padding: 28,
    borderRadius: 14,
    alignItems: "stretch",
    borderWidth: 1,
    borderColor: "#333",
  },
  title: {
    fontSize: 24,
    fontWeight: "bold",
    marginBottom: 8,
    textAlign: "center",
    color: "#fff",
  },
  subtitle: {
    fontSize: 15,
    color: "#999",
    marginBottom: 22,
    textAlign: "center",
  },
  input: {
    width: "100%",
    height: 56,
    backgroundColor: "#26262a",
    borderRadius: 8,
    paddingHorizontal: 16,
    color: "#fff",
    fontSize: 18,
    marginBottom: 18,
    borderWidth: 2,
    borderColor: "transparent",
  },
  button: {
    width: "100%",
    height: 52,
    backgroundColor: Colors.dark.primary,
  },
});

export default LoginModal;
