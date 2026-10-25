import { useCallback, RefObject, useMemo, useRef, useEffect } from 'react';
import { Video, ResizeMode } from 'expo-av';
import Toast from 'react-native-toast-message';
import usePlayerStore from '@/stores/playerStore';

interface UseVideoHandlersProps {
  videoRef: RefObject<Video>;
  currentEpisode: { url: string; title: string } | undefined;
  initialPosition: number;
  introEndTime?: number;
  playbackRate: number;
  handlePlaybackStatusUpdate: (status: any) => void;
  deviceType: string;
  detail?: { poster?: string };
}

export const useVideoHandlers = ({
  videoRef,
  currentEpisode,
  initialPosition,
  introEndTime,
  playbackRate,
  handlePlaybackStatusUpdate,
  deviceType,
  detail,
}: UseVideoHandlersProps) => {
  /** 解码器崩溃原地重试计数：换集/换源时清零，避免无限重试 */
  const decoderRetryCountRef = useRef(0);
  const lastUrlRef = useRef<string>("");

  useEffect(() => {
    if (currentEpisode?.url !== lastUrlRef.current) {
      lastUrlRef.current = currentEpisode?.url ?? "";
      decoderRetryCountRef.current = 0;
    }
  }, [currentEpisode?.url]);

  const onLoad = useCallback(async () => {
    console.info(`[PERF] Video onLoad - video ready to play`);
    
    try {
      // 1. 先设置位置（如果需要）
      const jumpPosition = initialPosition || introEndTime || 0;
      if (jumpPosition > 0) {
        console.info(`[PERF] Setting initial position to ${jumpPosition}ms`);
        await videoRef.current?.setPositionAsync(jumpPosition);
      }
      
      // 2. 显式调用播放以确保自动播放
      console.info(`[AUTOPLAY] Attempting to start playback after onLoad`);
      await videoRef.current?.playAsync();
      console.info(`[AUTOPLAY] Auto-play successful after onLoad`);
      
      usePlayerStore.setState({ isLoading: false });
      console.info(`[PERF] Video loading complete - isLoading set to false`);
    } catch (error) {
      console.warn(`[AUTOPLAY] Failed to auto-play after onLoad:`, error);
      // 即使自动播放失败，也要设置加载完成状态
      usePlayerStore.setState({ isLoading: false });
      // 不显示错误提示，因为自动播放失败是常见且预期的情况
    }
  }, [videoRef, initialPosition, introEndTime]);

  const onLoadStart = useCallback(() => {
    if (!currentEpisode?.url) return;
    
    console.info(`[PERF] Video onLoadStart - starting to load video: ${currentEpisode.url.substring(0, 100)}...`);
    usePlayerStore.setState({ isLoading: true });
  }, [currentEpisode?.url]);

  const onError = useCallback((error: any) => {
    if (!currentEpisode?.url) return;
    
    console.error(`[ERROR] Video playback error:`, error);
    
    // 检测SSL证书错误和其他网络错误
    const errorString = (error as any)?.error?.toString() || error?.toString() || '';
    const isSSLError = errorString.includes('SSLHandshakeException') || 
                      errorString.includes('CertPathValidatorException') ||
                      errorString.includes('Trust anchor for certification path not found');
    const isNetworkError = errorString.includes('HttpDataSourceException') ||
                         errorString.includes('IOException') ||
                         errorString.includes('SocketTimeoutException');

    // 解码器崩溃（老 TV 的 OMX.MS.AVC.Decoder 常见）：
    //   j7.g: Decoder failed / IllegalStateException @ native_dequeueOutputBuffer
    //   Disable failed / IllegalStateException @ native_flush
    // 这种错误换播放源没有用（同一个硬解码器），而原来一律走 handleVideoError
    // -> 切源 -> 重新 init(拉 filmPlayInfo 4s+) -> 又崩溃，表现为
    // "加载 -> 进度条回退 -> 再加载" 死循环（18AV / 四虎 就是这样）。
    // 这里改成：原地 seek 到当前稍前位置重试一次，重置解码器但不重拉列表。
    const isDecoderError =
      errorString.includes('Decoder failed') ||
      errorString.includes('MediaCodec') ||
      errorString.includes('native_dequeueOutputBuffer') ||
      errorString.includes('native_flush');

    if (isDecoderError && decoderRetryCountRef.current < 1) {
      decoderRetryCountRef.current += 1;
      console.warn(`[DECODER_RETRY] 解码器异常，原地重试第 ${decoderRetryCountRef.current} 次`);
      const store = usePlayerStore.getState();
      const pos = (store.status as any)?.positionMillis ?? 0;
      const target = Math.max(0, pos - 1000);
      setTimeout(() => {
        store.videoRef?.current
          ?.playFromPositionAsync?.(target)
          .catch(() => {});
      }, 500);
      return;
    }

    if (isSSLError) {
      console.error(`[SSL_ERROR] SSL certificate validation failed for URL: ${currentEpisode.url}`);
      Toast.show({ 
        type: "error", 
        text1: "SSL证书错误，正在尝试其他播放源...",
        text2: "请稍候"
      });
      usePlayerStore.getState().handleVideoError('ssl', currentEpisode.url);
    } else if (isNetworkError) {
      console.error(`[NETWORK_ERROR] Network connection failed for URL: ${currentEpisode.url}`);
      Toast.show({ 
        type: "error", 
        text1: "网络连接失败，正在尝试其他播放源...",
        text2: "请稍候"
      });
      usePlayerStore.getState().handleVideoError('network', currentEpisode.url);
    } else {
      console.error(`[VIDEO_ERROR] Other video error for URL: ${currentEpisode.url}`);
      Toast.show({ 
        type: "error", 
        text1: "视频播放失败，正在尝试其他播放源...",
        text2: "请稍候"
      });
      usePlayerStore.getState().handleVideoError('other', currentEpisode.url);
    }
  }, [currentEpisode?.url]);

  // 优化的Video组件props
  // 注意：不要把 playbackRate 放进 props.rate。
  // rate 变化会重建 source，老 TV 上等于重开 OMX 解码器，
  // 与 seek 叠加时很容易直接把进程带崩。变速统一走 setRateAsync。
  const initialRateRef = useRef(playbackRate);
  const videoProps = useMemo(() => ({
    source: { uri: currentEpisode?.url || '' },
    posterSource: { uri: detail?.poster ?? "" },
    resizeMode: ResizeMode.CONTAIN,
    rate: initialRateRef.current,
    onPlaybackStatusUpdate: handlePlaybackStatusUpdate,
    onLoad,
    onLoadStart,
    onError,
    useNativeControls: deviceType !== 'tv',
    shouldPlay: true,
  }), [
    currentEpisode?.url,
    detail?.poster,
    handlePlaybackStatusUpdate,
    onLoad,
    onLoadStart,
    onError,
    deviceType,
  ]);

  return {
    onLoad,
    onLoadStart,
    onError,
    videoProps,
  };
};