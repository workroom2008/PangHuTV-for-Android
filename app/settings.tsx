import React, { useState, useEffect, useRef } from "react";
import { View, StyleSheet, Alert, Platform, ScrollView, useTVEventHandler, Pressable } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { ThemedText } from "@/components/ThemedText";
import { ThemedView } from "@/components/ThemedView";
import { StyledButton } from "@/components/StyledButton";
import { useThemeColor } from "@/hooks/useThemeColor";
import { useSettingsStore } from "@/stores/settingsStore";
import useAuthStore from "@/stores/authStore";
import { useRemoteControlStore } from "@/stores/remoteControlStore";
import { APIConfigSection } from "@/components/settings/APIConfigSection";
import { AccountSection } from "@/components/settings/AccountSection";
import { LiveStreamSection } from "@/components/settings/LiveStreamSection";
import { RemoteInputSection } from "@/components/settings/RemoteInputSection";
import { UpdateSection } from "@/components/settings/UpdateSection";
// import { VideoSourceSection } from "@/components/settings/VideoSourceSection";
import Toast from "react-native-toast-message";
import { useResponsiveLayout } from "@/hooks/useResponsiveLayout";
import { getCommonResponsiveStyles } from "@/utils/ResponsiveStyles";
import ResponsiveNavigation from "@/components/navigation/ResponsiveNavigation";
import ResponsiveHeader from "@/components/navigation/ResponsiveHeader";
import { DeviceUtils } from "@/utils/DeviceUtils";
import { KeyboardAwareScrollView } from 'react-native-keyboard-aware-scroll-view';
import { SettingsFocusContext } from "@/hooks/useSettingsFocus";
import { useSettingsFocusRegistry } from "@/hooks/useSettingsFocusRegistry";
import { useRouter } from "expo-router";

type SectionItem = {
  component: React.ReactElement;
  key: string;
};

/** 过滤掉 false/undefined，帮 TypeScript 推断出真正的数组元素类型 */
function isSectionItem(
  item: false | undefined | SectionItem
): item is SectionItem {
  return !!item;
}

export default function SettingsScreen() {
  const router = useRouter();
  const { loadSettings, saveSettings, saveAccountAndLogin, setApiBaseUrl, setM3uUrl } = useSettingsStore();
  const { lastMessage, targetPage, clearMessage } = useRemoteControlStore();
  const backgroundColor = useThemeColor({}, "background");
  const insets = useSafeAreaInsets();

  // 账号区（API 地址下方）：保存即登录
  const [loginUsername, setLoginUsername] = useState("");
  const [loginPassword, setLoginPassword] = useState("");
  const accountSectionRef = useRef<any>(null);

  // 响应式布局配置
  const responsiveConfig = useResponsiveLayout();
  const commonStyles = getCommonResponsiveStyles(responsiveConfig);
  const { deviceType, spacing } = responsiveConfig;

  const [hasChanges, setHasChanges] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [currentSection, setCurrentSection] = useState<string | null>(null);

  const apiSectionRef = useRef<any>(null);
  const liveStreamSectionRef = useRef<any>(null);
  const saveButtonRef = useRef<any>(null);
  /** 远程输入开关的切换函数（由 RemoteInputSection 注册，供页面级 select 分发调用） */
  const remoteInputToggleRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    loadSettings();
  }, [loadSettings]);

  useEffect(() => {
    // 只处理「明确指向设置页」的文本（targetPage === 'settings'）。
    // 手机端「发送文本到电视」默认进搜索页，不能被抓来改 API 地址/账号。
    if (lastMessage && targetPage === "settings") {
      const realMessage = lastMessage.split("_")[0];
      handleRemoteInput(realMessage);
      clearMessage(); // Clear the message after processing
      markAsChanged();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lastMessage, targetPage]);

  const handleRemoteInput = (message: string) => {
    // Handle remote input based on currently focused section
    if (currentSection === "api" && apiSectionRef.current) {
      // API Config Section
      setApiBaseUrl(message);
    } else if (currentSection === "username" && accountSectionRef.current) {
      accountSectionRef.current.setUsernameValue(message);
    } else if (currentSection === "password" && accountSectionRef.current) {
      accountSectionRef.current.setPasswordValue(message);
    } else if (currentSection === "livestream" && liveStreamSectionRef.current) {
      // Live Stream Section
      setM3uUrl(message);
    }
  };

  const handleSave = async () => {
    setIsLoading(true);
    try {
      await saveSettings();
      // 账号区非空时保存凭据并立即登录（远程输入一次配好服务器+账号）
      if (loginUsername.trim()) {
        const loginOk = await saveAccountAndLogin(loginUsername, loginPassword);
        if (loginOk) {
          await useAuthStore.getState().checkLoginStatus(useSettingsStore.getState().apiBaseUrl);
        }
        Toast.show({
          type: loginOk ? "success" : "error",
          text1: loginOk ? "已登录" : "登录失败，请检查用户名密码",
        });
      }
      setHasChanges(false);
      Toast.show({
        type: "success",
        text1: "保存成功",
      });
    } catch {
      Alert.alert("错误", "保存设置失败");
    } finally {
      setIsLoading(false);
    }
  };

  const markAsChanged = () => {
    setHasChanges(true);
  };

  /** TV：按 OK 保存设置并退出设置页（返回首页） */
  const handleSaveAndExit = async () => {
    if (isLoading) return;
    if (hasChanges) {
      await handleSave();
    }
    if (router.canGoBack()) {
      router.back();
    } else {
      router.replace("/");
    }
  };

  // const sections = [
  //   // 远程输入配置 - 仅在非手机端显示
  //   deviceType !== "mobile" && {
  //     component: (
  //       <RemoteInputSection
  //         onChanged={markAsChanged}
  //         onFocus={() => {
  //           setCurrentFocusIndex(0);
  //           setCurrentSection("remote");
  //         }}
  //       />
  //     ),
  //     key: "remote",
  //   },
  //   {
  //     component: (
  //       <APIConfigSection
  //         ref={apiSectionRef}
  //         onChanged={markAsChanged}
  //         hideDescription={deviceType === "mobile"}
  //         onFocus={() => {
  //           setCurrentFocusIndex(1);
  //           setCurrentSection("api");
  //         }}
  //       />
  //     ),
  //     key: "api",
  //   },
  //   // 直播源配置 - 仅在非手机端显示
  //   deviceType !== "mobile" && {
  //     component: (
  //       <LiveStreamSection
  //         ref={liveStreamSectionRef}
  //         onChanged={markAsChanged}
  //         onFocus={() => {
  //           setCurrentFocusIndex(2);
  //           setCurrentSection("livestream");
  //         }}
  //       />
  //     ),
  //     key: "livestream",
  //   },
  //   // {
  //   //   component: (
  //   //     <VideoSourceSection
  //   //       onChanged={markAsChanged}
  //   //       onFocus={() => {
  //   //         setCurrentFocusIndex(3);
  //   //         setCurrentSection("videoSource");
  //   //       }}
  //   //     />
  //   //   ),
  //   //   key: "videoSource",
  //   // },
  //   Platform.OS === "android" && {
  //     component: <UpdateSection />,
  //     key: "update",
  //   },
  // ].filter(Boolean);
  const rawSections = [
    deviceType !== "mobile" && {
      component: (
        <RemoteInputSection
          onChanged={markAsChanged}
          onFocus={() => {
            setCurrentSection("remote");
          }}
          onRegisterToggle={(fn: () => void) => {
            remoteInputToggleRef.current = fn;
          }}
        />
      ),
      key: "remote",
    },
    {
      component: (
        <APIConfigSection
          ref={apiSectionRef}
          onChanged={markAsChanged}
          hideDescription={deviceType === "mobile"}
          onFocus={() => {
            setCurrentSection("api");
          }}
        />
      ),
      key: "api",
    },
    {
      component: (
        <AccountSection
          ref={accountSectionRef}
          username={loginUsername}
          password={loginPassword}
          setUsername={(v) => {
            setLoginUsername(v);
            markAsChanged();
          }}
          setPassword={(v) => {
            setLoginPassword(v);
            markAsChanged();
          }}
          onFocus={() => setCurrentSection("username")}
          onBlur={() => setCurrentSection(null)}
        />
      ),
      key: "account",
    },
    deviceType !== "mobile" && {
      component: (
        <LiveStreamSection
          ref={liveStreamSectionRef}
          onChanged={markAsChanged}
          onFocus={() => {
            setCurrentSection("livestream");
          }}
        />
      ),
      key: "livestream",
    },
    Platform.OS === "android" && {
      component: <UpdateSection />,
      key: "update",
    },
  ] as const; // 把每个对象都当作字面量保留
  /** 这里得到的 sections 已经是 SectionItem[]（没有 false） */
  const sections: SectionItem[] = rawSections.filter(isSectionItem);


  // TV 遥控器焦点：设置页控件嵌在 ScrollView + 自定义容器里，原生焦点搜索
  // 拿不到可靠的上下相邻关系；且 TextInput 一旦聚焦会挂输入法吃掉方向键。
  // 因此按「视觉顺序」显式驱动 上/下 键：焦点键序列 + 当前下标。
  const focusRegistry = useSettingsFocusRegistry();
  const focusOrder = React.useMemo(() => {
    const keys: string[] = [];
    if (deviceType !== "mobile") keys.push("settings.remoteInput");
    keys.push("settings.api");
    keys.push("settings.account.username");
    keys.push("settings.account.password");
    if (deviceType !== "mobile") keys.push("settings.liveStream");
    keys.push("settings.save");
    return keys;
  }, [deviceType]);

  const focusIndexRef = useRef(0);
  const [focusReady, setFocusReady] = useState(false);

  // 保存按钮注册进焦点链，否则上/下走到底会落到不存在的节点上
  useEffect(() => {
    focusRegistry.value.register({
      key: "settings.save",
      focus: () => saveButtonRef.current?.focus?.(),
    });
    return () => focusRegistry.value.unregister("settings.save");
  }, [focusRegistry]);

  const moveFocus = React.useCallback(
    (delta: number) => {
      const step = delta > 0 ? 1 : -1;
      let next = focusIndexRef.current;
      // 跳过未注册的节点（mobile 下没有 remoteInput/liveStream，或 UpdateSection 未渲染）
      for (let guard = 0; guard < focusOrder.length; guard++) {
        const candidate = next + step;
        if (candidate < 0 || candidate > focusOrder.length - 1) break;
        next = candidate;
        if (focusRegistry.value.focusKey(focusOrder[next])) break;
      }
      focusIndexRef.current = Math.max(0, Math.min(next, focusOrder.length - 1));
      focusRegistry.value.focusKey(focusOrder[focusIndexRef.current]);
    },
    [focusOrder, focusRegistry]
  );

  // 当前聚焦行的"按下"动作。TV 上 OEM 固件常只发 select 不发 press，
  // 由页面统一分发，避免各区块自己抢事件互相覆盖。
  const activateCurrent = React.useCallback(() => {
    const key = focusOrder[focusIndexRef.current];
    if (key === "settings.remoteInput") {
      focusRegistry.value.focusKey(key);
      // 开关切换由 RemoteInputSection 的注册节点处理
      remoteInputToggleRef.current?.();
      return;
    }
    if (key === "settings.save") {
      void handleSaveAndExit();
      return;
    }
    // 输入框：聚焦即唤起键盘，按 OK 等同聚焦
    focusRegistry.value.focusKey(key);
  }, [focusOrder, focusRegistry]);

  const handleTVEvent = React.useCallback(
    (event: any) => {
      if (deviceType !== "tv") return;
      if (event.eventType === "down" || event.eventType === "up") {
        moveFocus(event.eventType === "down" ? 1 : -1);
        return;
      }
      if (event.eventType === "select" || event.eventType === "playPause") {
        activateCurrent();
      }
    },
    [deviceType, moveFocus, activateCurrent]
  );

  useTVEventHandler(deviceType === "tv" ? handleTVEvent : () => {});

  // 进入页面把焦点放到第一项
  useEffect(() => {
    if (deviceType !== "tv" || focusReady) return;
    const timer = setTimeout(() => {
      focusIndexRef.current = 0;
      focusRegistry.value.focusKey(focusOrder[0]);
      setFocusReady(true);
    }, 400);
    return () => clearTimeout(timer);
  }, [deviceType, focusReady, focusRegistry, focusOrder]);

  // 动态样式
  const dynamicStyles = createResponsiveStyles(deviceType, spacing, insets);

  const renderSettingsContent = () => (
    // <KeyboardAvoidingView style={{ flex: 1, backgroundColor }} behavior={Platform.OS === "ios" ? "padding" : "height"}>
    <KeyboardAwareScrollView
      enableOnAndroid={true}
      extraScrollHeight={20}
      keyboardOpeningTime={0}
      keyboardShouldPersistTaps="always"
      scrollEnabled={true}
      style={{ flex: 1, backgroundColor }}
    >

      <ThemedView style={[commonStyles.container, dynamicStyles.container]}>
        {deviceType === "tv" && (
          <View style={dynamicStyles.header}>
            <ThemedText style={dynamicStyles.title}>设置</ThemedText>
          </View>
        )}

        {/* <View style={dynamicStyles.scrollView}>
          <FlatList
            data={sections}
            renderItem={({ item }) => {
              if (item) {
                return item.component;
              }
              return null;
            }}
            keyExtractor={(item) => (item ? item.key : "default")}
            showsVerticalScrollIndicator={false}
            contentContainerStyle={dynamicStyles.listContent}
          />
        </View> */}
        <View style={dynamicStyles.scrollView}>
          {sections.map(item => (
            // 必须把 key 放在最外层的 View 上
            <View key={item.key} style={dynamicStyles.itemWrapper}>
              {item.component}
            </View>
          ))}
        </View>

        <View style={dynamicStyles.footer}>
          <Pressable
            ref={saveButtonRef}
            focusable
            onFocus={() => {
              setCurrentSection("save");
              focusIndexRef.current = focusOrder.indexOf("settings.save");
            }}
            onPress={handleSaveAndExit}
            style={[isLoading && { opacity: 0.5 }]}
          >
            <StyledButton
              text={isLoading ? "保存中..." : "保存并退出"}
              variant="primary"
              style={dynamicStyles.saveButton}
            />
          </Pressable>
        </View>
      </ThemedView>
    </KeyboardAwareScrollView>
    // </KeyboardAvoidingView>
  );

  // 根据设备类型决定是否包装在响应式导航中
  if (deviceType === "tv") {
    return (
      <SettingsFocusContext.Provider value={focusRegistry.value}>
        {renderSettingsContent()}
      </SettingsFocusContext.Provider>
    );
  }

  return (
    <SettingsFocusContext.Provider value={focusRegistry.value}>
      <ResponsiveNavigation>
        <ResponsiveHeader title="设置" showBackButton />
        {renderSettingsContent()}
      </ResponsiveNavigation>
    </SettingsFocusContext.Provider>
  );
}

const createResponsiveStyles = (deviceType: string, spacing: number, insets: any) => {
  const isMobile = deviceType === "mobile";
  const isTablet = deviceType === "tablet";
  const isTV = deviceType === "tv";
  const minTouchTarget = DeviceUtils.getMinTouchTargetSize();

  return StyleSheet.create({
    container: {
      flex: 1,
      padding: spacing,
      paddingTop: isTV ? spacing * 2 : isMobile ? insets.top + spacing : insets.top + spacing * 1.5,
    },
    header: {
      flexDirection: "row",
      justifyContent: "space-between",
      alignItems: "center",
      marginBottom: spacing,
    },
    title: {
      fontSize: isMobile ? 24 : isTablet ? 28 : 32,
      fontWeight: "bold",
      paddingTop: spacing,
      color: "white",
    },
    scrollView: {
      flex: 1,
    },
    listContent: {
      paddingBottom: spacing,
    },
    footer: {
      paddingTop: spacing,
      alignItems: isMobile ? "center" : "flex-end",
    },
    saveButton: {
      minHeight: isMobile ? minTouchTarget : isTablet ? 50 : 50,
      width: isMobile ? "100%" : isTablet ? 140 : 120,
      maxWidth: isMobile ? 280 : undefined,
    },
    disabledButton: {
      opacity: 0.5,
    },
    itemWrapper: {
      marginBottom: spacing,   // 这里的 spacing 来自 useResponsiveLayout()
    },
  });
};
