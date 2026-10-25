import React, { useState, useRef, useEffect } from "react";
import { View, TextInput, StyleSheet, Alert, Keyboard, TouchableOpacity, FlatList } from "react-native";
import { ThemedView } from "@/components/ThemedView";
import { ThemedText } from "@/components/ThemedText";
import VideoCard from "@/components/VideoCard";
import VideoLoadingAnimation from "@/components/VideoLoadingAnimation";
import { api, SearchResult, SearchSourceTab } from "@/services/api";
import { Search, QrCode } from "lucide-react-native";
import { StyledButton } from "@/components/StyledButton";
import { useRemoteControlStore } from "@/stores/remoteControlStore";
import { RemoteControlModal } from "@/components/RemoteControlModal";
import { useSettingsStore } from "@/stores/settingsStore";
import { useRouter } from "expo-router";
import { Colors } from "@/constants/Colors";
import CustomScrollView from "@/components/CustomScrollView";
import { useResponsiveLayout } from "@/hooks/useResponsiveLayout";
import { getCommonResponsiveStyles } from "@/utils/ResponsiveStyles";
import ResponsiveNavigation from "@/components/navigation/ResponsiveNavigation";
import ResponsiveHeader from "@/components/navigation/ResponsiveHeader";
import { DeviceUtils } from "@/utils/DeviceUtils";
import Logger from '@/utils/Logger';

const logger = Logger.withTag('SearchScreen');

export default function SearchScreen() {
  const [keyword, setKeyword] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const textInputRef = useRef<TextInput>(null);
  const [isInputFocused, setIsInputFocused] = useState(false);
  const { showModal: showRemoteModal, lastMessage, targetPage, clearMessage } = useRemoteControlStore();
  const { remoteInputEnabled } = useSettingsStore();
  const router = useRouter();

  // 响应式布局配置
  const responsiveConfig = useResponsiveLayout();
  const commonStyles = getCommonResponsiveStyles(responsiveConfig);
  const { deviceType, spacing } = responsiveConfig;

  useEffect(() => {
    if (lastMessage && (targetPage === 'search' || !targetPage)) {
      logger.debug("Received remote input:", lastMessage);
      const realMessage = lastMessage.split("_")[0];
      setKeyword(realMessage);
      handleSearch(realMessage);
      clearMessage(); // Clear the message after processing
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lastMessage, targetPage]);

  // useEffect(() => {
  //   // Focus the text input when the screen loads
  //   const timer = setTimeout(() => {
  //     textInputRef.current?.focus();
  //   }, 200);
  //   return () => clearTimeout(timer);
  // }, []);

  // 源选择：直接来自 /api/searchFilm 的 sources 字段（带各源命中数），无需额外请求
  const [sourceTabs, setSourceTabs] = useState<SearchSourceTab[]>([]);
  const [selectedSource, setSelectedSource] = useState("");
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);
  const [total, setTotal] = useState(0);

  const PAGE_SIZE = 50; // 服务端硬上限，见 index_handler.go

  const runSearch = async (
    term: string,
    sourceKey: string,
    pageNo: number,
    mode: "replace" | "append"
  ) => {
    try {
      const res = sourceKey
        ? await api.searchBySource(term, sourceKey, pageNo, PAGE_SIZE)
        : await api.searchByKeyword(term, pageNo, PAGE_SIZE);

      if (res.sources?.length) setSourceTabs(res.sources);
      setTotal(res.total ?? 0);
      setHasMore(!!res.hasMore);

      setResults((prev) => {
        if (mode === "replace") return res.list;
        const seen = new Set(prev.map((r) => `${r.source}_${r.id}`));
        return [...prev, ...res.list.filter((r) => !seen.has(`${r.source}_${r.id}`))];
      });

      if (mode === "replace" && res.list.length === 0) {
        setError("没有找到相关内容");
      } else {
        setError(null);
      }
    } catch (err) {
      logger.info("Search failed:", err);
      setError("搜索失败，请稍后重试。");
    } finally {
      setLoading(false);
    }
  };

  const handleSearch = async (searchText?: string) => {
    const term = typeof searchText === "string" ? searchText : keyword;
    if (!term.trim()) {
      Keyboard.dismiss();
      return;
    }
    Keyboard.dismiss();
    setLoading(true);
    setError(null);
    setPage(1);
    await runSearch(term, selectedSource, 1, "replace");
  };

  // 选源：已有结果就立刻按新源重搜，不用再按一次搜索
  const handleSelectSource = async (sourceKey: string) => {
    if (sourceKey === selectedSource) return;
    setSelectedSource(sourceKey);
    const term = keyword.trim();
    if (!term) return;
    setLoading(true);
    setError(null);
    setPage(1);
    await runSearch(term, sourceKey, 1, "replace");
  };

  // 加载更多（聚合搜索分页累加）
  const handleLoadMore = async () => {
    if (loading || !hasMore) return;
    const term = keyword.trim();
    if (!term) return;
    setLoading(true);
    const next = page + 1;
    setPage(next);
    await runSearch(term, selectedSource, next, "append");
  };

  const onSearchPress = () => handleSearch();

  // 热门搜索词（胖虎 /api/hotKeywords，失败静默为空）
  const [hotKeywords, setHotKeywords] = useState<string[]>([]);
  useEffect(() => {
    let mounted = true;
    api.getHotKeywords(10).then((words) => {
      if (mounted) setHotKeywords(words);
    }).catch(() => {});
    return () => {
      mounted = false;
    };
  }, []);

  const handleHotKeywordPress = (word: string) => {
    setKeyword(word);
    handleSearch(word);
  };

  const handleQrPress = () => {
    if (!remoteInputEnabled) {
      Alert.alert("远程输入未启用", "请先在设置页面中启用远程输入功能", [
        { text: "取消", style: "cancel" },
        { text: "去设置", onPress: () => router.push("/settings") },
      ]);
      return;
    }
    showRemoteModal('search');
  };

  const renderItem = ({ item }: { item: SearchResult; index: number }) => (
    <VideoCard
      id={item.id.toString()}
      source={item.source}
      title={item.title}
      poster={item.poster}
      year={item.year}
      sourceName={item.source_name}
      api={api}
    />
  );

  // 动态样式
  const dynamicStyles = createResponsiveStyles(deviceType, spacing);

  const renderSearchContent = () => (
    <>
      <View style={dynamicStyles.searchContainer}>
        <TouchableOpacity
          activeOpacity={1}
          style={[
            dynamicStyles.inputContainer,
            {
              borderColor: isInputFocused ? Colors.dark.primary : "transparent",
            },
          ]}
          onPress={() => textInputRef.current?.focus()}
        >
          <TextInput
            ref={textInputRef}
            style={dynamicStyles.input}
            placeholder="搜索电影、剧集..."
            placeholderTextColor="#888"
            value={keyword}
            onChangeText={setKeyword}
            onSubmitEditing={onSearchPress}
            onFocus={() => setIsInputFocused(true)}
            onBlur={() => setIsInputFocused(false)}
            returnKeyType="search"
          />
        </TouchableOpacity>
        <StyledButton style={dynamicStyles.searchButton} onPress={onSearchPress}>
          <Search size={deviceType === 'mobile' ? 20 : 24} color="white" />
        </StyledButton>
        {deviceType !== 'mobile' && (
          <StyledButton style={dynamicStyles.qrButton} onPress={handleQrPress}>
            <QrCode size={deviceType === 'tv' ? 24 : 20} color="white" />
          </StyledButton>
        )}
      </View>

      {/* 源选择：标签与命中数都来自搜索响应，选完立即按该源重搜 */}
      {sourceTabs.length > 1 && deviceType !== 'mobile' && (
        <FlatList
          data={sourceTabs}
          renderItem={({ item }) => {
            const isSelected = selectedSource === item.id;
            return (
              <StyledButton
                text={item.count > 0 ? `${item.name}(${item.count})` : item.name}
                onPress={() => handleSelectSource(item.id)}
                isSelected={isSelected}
                style={dynamicStyles.sourceButton}
                textStyle={dynamicStyles.sourceText}
                variant={isSelected ? "primary" : "ghost"}
              />
            );
          }}
          keyExtractor={(item) => item.id || "__all__"}
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={dynamicStyles.sourceListContent}
        />
      )}

      {/* 热词只在"还没有结果"的空态显示：出结果后如果还挂着，会一直挤压网格可视区 */}
      {hotKeywords.length > 0 && results.length === 0 && !loading && (
        <View style={dynamicStyles.hotKeywordsRow}>
          {hotKeywords.map((word) => (
            <TouchableOpacity
              key={word}
              style={dynamicStyles.hotKeywordChip}
              onPress={() => handleHotKeywordPress(word)}
            >
              <ThemedText style={dynamicStyles.hotKeywordText}>{word}</ThemedText>
            </TouchableOpacity>
          ))}
        </View>
      )}

      {loading ? (
        <VideoLoadingAnimation showProgressBar={false} />
      ) : error ? (
        <View style={[commonStyles.center, { flex: 1 }]}>
          <ThemedText style={dynamicStyles.errorText}>{error}</ThemedText>
        </View>
      ) : (
        <>
          {results.length > 0 && (
            <View style={dynamicStyles.resultHeader}>
              <ThemedText style={dynamicStyles.resultCount}>
                {total > results.length ? `已显示 ${results.length} / 共 ${total} 条` : `共 ${results.length} 条`}
              </ThemedText>
              {hasMore && (
                <StyledButton
                  text="加载更多"
                  onPress={handleLoadMore}
                  variant="ghost"
                  style={dynamicStyles.loadMoreButton}
                />
              )}
            </View>
          )}
          <CustomScrollView
            data={results}
            renderItem={renderItem}
            loading={loading}
            error={error}
            emptyMessage="输入关键词开始搜索"
          />
        </>
      )}
      <RemoteControlModal />
    </>
  );

  const content = (
    <ThemedView style={[commonStyles.container, dynamicStyles.container]}>
      {renderSearchContent()}
    </ThemedView>
  );

  // 根据设备类型决定是否包装在响应式导航中
  if (deviceType === 'tv') {
    return content;
  }

  return (
    <ResponsiveNavigation>
      <ResponsiveHeader title="搜索" showBackButton />
      {content}
    </ResponsiveNavigation>
  );
}

const createResponsiveStyles = (deviceType: string, spacing: number) => {
  const isMobile = deviceType === 'mobile';
  const minTouchTarget = DeviceUtils.getMinTouchTargetSize();

  return StyleSheet.create({
    container: {
      flex: 1,
      paddingTop: deviceType === 'tv' ? 50 : 0,
    },
    searchContainer: {
      flexDirection: "row",
      paddingHorizontal: spacing,
      marginBottom: spacing,
      alignItems: "center",
      paddingTop: isMobile ? spacing / 2 : 0,
    },
    sourceListContent: {
      paddingHorizontal: spacing,
      paddingBottom: spacing / 2,
    },
    sourceButton: {
      marginRight: spacing / 2,
      paddingHorizontal: 16,
      paddingVertical: 8,
      borderRadius: 18,
    },
    sourceText: {
      fontSize: isMobile ? 13 : 15,
    },
    resultHeader: {
      flexDirection: "row",
      alignItems: "center",
      justifyContent: "space-between",
      paddingHorizontal: spacing,
      marginBottom: 8,
    },
    resultCount: {
      fontSize: 13,
      color: "#999",
    },
    loadMoreButton: {
      paddingHorizontal: 16,
      paddingVertical: 6,
    },
    inputContainer: {
      flex: 1,
      height: isMobile ? minTouchTarget : 50,
      backgroundColor: "#2c2c2e",
      borderRadius: isMobile ? 8 : 8,
      marginRight: spacing / 2,
      borderWidth: 2,
      borderColor: "transparent",
      justifyContent: "center",
    },
    input: {
      flex: 1,
      paddingHorizontal: spacing,
      color: "white",
      fontSize: isMobile ? 16 : 18,
    },
    searchButton: {
      width: isMobile ? minTouchTarget : 50,
      height: isMobile ? minTouchTarget : 50,
      justifyContent: "center",
      alignItems: "center",
      borderRadius: isMobile ? 8 : 8,
      marginRight: deviceType !== 'mobile' ? spacing / 2 : 0,
    },
    qrButton: {
      width: isMobile ? minTouchTarget : 50,
      height: isMobile ? minTouchTarget : 50,
      justifyContent: "center",
      alignItems: "center",
      borderRadius: isMobile ? 8 : 8,
    },
    errorText: {
      color: "red",
      fontSize: isMobile ? 14 : 16,
      textAlign: "center",
    },
    hotKeywordsRow: {
      flexDirection: "row",
      flexWrap: "wrap",
      paddingHorizontal: spacing,
      marginBottom: spacing / 2,
      gap: spacing / 2,
    },
    hotKeywordChip: {
      paddingHorizontal: spacing,
      paddingVertical: spacing / 3,
      borderRadius: 16,
      backgroundColor: "#2c2c2e",
      borderWidth: 1,
      borderColor: "#555",
    },
    hotKeywordText: {
      color: "#ccc",
      fontSize: isMobile ? 13 : 15,
    },
  });
};
