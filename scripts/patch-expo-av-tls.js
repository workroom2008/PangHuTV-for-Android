#!/usr/bin/env node
/**
 * expo-av 播放器 TLS 兼容补丁（Android 6/7 OEM 电视）。
 *
 * 问题：expo-av 的 SharedCookiesDataSourceFactory 用默认 OkHttpClient 拉 m3u8/分片，
 * 老系统 CA 库不认识 Let's Encrypt ISRG Root X1 / Google Trust Services WE1 等新根，
 * 直连 CDN 必然 SSLHandshakeException，表现为「115/极品/MissAV/51吃瓜 等源全部播放失败」。
 *
 * 做法：把 expo-av 的 SharedCookiesDataSourceFactory 改为优先使用应用侧
 * com.hongbo.panghutv.PanghuTls 提供的 SSLSocketFactory（反射调用，node_modules 不感知宿主）。
 *
 * 该脚本幂等；在 postinstall 中执行，`yarn install` / `yarn prebuild` 后仍生效。
 */
const fs = require("fs");
const path = require("path");

const TARGET = path.join(
  __dirname,
  "..",
  "node_modules",
  "expo-av",
  "android",
  "src",
  "main",
  "java",
  "expo",
  "modules",
  "av",
  "player",
  "datasource",
  "SharedCookiesDataSourceFactory.java"
);

const MARKER = "// PANGHU_TLS_PATCH";

const PATCHED = `package expo.modules.av.player.datasource;

import android.content.Context;
import android.util.Log;

import com.google.android.exoplayer2.upstream.DataSource;
import com.google.android.exoplayer2.upstream.DefaultDataSourceFactory;
import com.google.android.exoplayer2.upstream.TransferListener;

import java.security.KeyStore;
import java.util.Map;

import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;

import expo.modules.av.ForwardingCookieHandler;
import okhttp3.JavaNetCookieJar;
import okhttp3.OkHttpClient;

public class SharedCookiesDataSourceFactory implements DataSource.Factory {
  // PANGHU_TLS_PATCH: 优先使用宿主 App 提供的兼容 TLS（老 Android 缺新根证书）
  private static final String TAG = "PanghuAvDataSource";
  private final DataSource.Factory mDataSourceFactory;

  public SharedCookiesDataSourceFactory(Context reactApplicationContext, String userAgent, Map<String, Object> requestHeaders, TransferListener transferListener) {
    OkHttpClient.Builder builder = new OkHttpClient.Builder();
    builder.cookieJar(new JavaNetCookieJar(new ForwardingCookieHandler()));
    applyPanghuTls(builder);
    OkHttpClient client = builder.build();
    mDataSourceFactory = new DefaultDataSourceFactory(reactApplicationContext, transferListener, new CustomHeadersOkHttpDataSourceFactory(client, userAgent, requestHeaders));
  }

  /** 反射加载宿主 App 的 TLS 工厂；不存在时静默保持系统默认。 */
  private static void applyPanghuTls(OkHttpClient.Builder builder) {
    try {
      Class<?> clazz = Class.forName("com.hongbo.panghutv.PanghuTls");
      SSLSocketFactory socketFactory = (SSLSocketFactory) clazz.getMethod("getSocketFactory").invoke(null);
      X509TrustManager trustManager = (X509TrustManager) clazz.getMethod("getTrustManager").invoke(null);
      if (socketFactory != null && trustManager != null) {
        builder.sslSocketFactory(socketFactory, trustManager);
        builder.retryOnConnectionFailure(true);
        android.util.Log.i(TAG, "已启用 PanghuTls 兼容信任链");
      } else {
        android.util.Log.w(TAG, "PanghuTls 返回空实现，沿用系统默认");
      }
    } catch (Throwable t) {
      android.util.Log.w(TAG, "启用 PanghuTls 失败，沿用系统默认", t);
    }
  }

  @Override
  public DataSource createDataSource() {
    return mDataSourceFactory.createDataSource();
  }
}
`;

function main() {
  patchExpoAv();
  applyNativeOverrides();
}

/** 1) expo-av 数据源注入 PanghuTls */
function patchExpoAv() {
  let current;
  try {
    current = fs.readFileSync(TARGET, "utf8");
  } catch (e) {
    console.log(`[patch-expo-av-tls] 跳过：未找到 ${TARGET}`);
    return;
  }
  if (current.includes(MARKER)) {
    console.log("[patch-expo-av-tls] expo-av 已打过补丁，跳过");
    return;
  }
  fs.writeFileSync(TARGET, PATCHED, "utf8");
  console.log("[patch-expo-av-tls] 已为 expo-av 注入 PanghuTls 数据源");
}

/**
 * 2) android/ 被 .gitignore 忽略，prebuild --clean 会重建。
 *    这里把受版本控制的 xml/android 覆盖回去，并在 build.gradle 补 exoplayer 依赖。
 */
function applyNativeOverrides() {
  const projectRoot = path.join(__dirname, "..");
  const srcRoot = path.join(projectRoot, "xml", "android");
  const dstRoot = path.join(projectRoot, "android");

  if (!fs.existsSync(dstRoot)) {
    console.log("[patch-expo-av-tls] android/ 尚未生成，跳过原生覆盖（prebuild 后会再执行）");
    return;
  }

  copyRecursive(srcRoot, dstRoot);

  // res/xml/network_security_config.xml（xml/res 下的资源单独映射到 src/main/res）
  const resSrc = path.join(projectRoot, "xml", "res");
  const resDst = path.join(dstRoot, "app", "src", "main", "res");
  if (fs.existsSync(resSrc)) {
    copyRecursive(resSrc, resDst);
    console.log("[patch-expo-av-tls] 已同步 xml/res → app/src/main/res");
  }

  // build.gradle 依赖：expo-av 需要 exoplayer extension-okhttp 才能挂自定义 TLS
  const gradlePath = path.join(dstRoot, "app", "build.gradle");
  if (fs.existsSync(gradlePath)) {
    let gradle = fs.readFileSync(gradlePath, "utf8");
    if (!gradle.includes("extension-okhttp")) {
      gradle = gradle.replace(
        /if \(hermesEnabled\.toBoolean\(\)\) \{/,
        `// 与 expo-av 一致的 ExoPlayer + OkHttp 扩展（PanghuTls 兼容老系统证书库）\n` +
          `    implementation("com.google.android.exoplayer:exoplayer-core:2.18.1")\n` +
          `    implementation("com.google.android.exoplayer:exoplayer-hls:2.18.1")\n` +
          `    implementation("com.google.android.exoplayer:extension-okhttp:2.18.1")\n\n` +
          `    if (hermesEnabled.toBoolean()) {`
      );
      fs.writeFileSync(gradlePath, gradle, "utf8");
      console.log("[patch-expo-av-tls] 已补 exoplayer 依赖到 app/build.gradle");
    }
  }

  // manifest：补 networkSecurityConfig
  const manifestPath = path.join(dstRoot, "app", "src", "main", "AndroidManifest.xml");
  if (fs.existsSync(manifestPath)) {
    let manifest = fs.readFileSync(manifestPath, "utf8");
    if (!manifest.includes("networkSecurityConfig")) {
      manifest = manifest.replace(
        /android:usesCleartextTraffic="true"/,
        `android:usesCleartextTraffic="true" android:networkSecurityConfig="@xml/network_security_config"`
      );
      fs.writeFileSync(manifestPath, manifest, "utf8");
      console.log("[patch-expo-av-tls] 已补 networkSecurityConfig 到 AndroidManifest");
    }
  }
}

function copyRecursive(src, dst) {
  if (!fs.existsSync(src)) return;
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    if (!fs.existsSync(dst)) fs.mkdirSync(dst, { recursive: true });
    for (const entry of fs.readdirSync(src)) {
      copyRecursive(path.join(src, entry), path.join(dst, entry));
    }
  } else {
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(src, dst);
  }
}

main();
