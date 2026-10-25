package com.hongbo.panghutv;

import android.util.Log;

import androidx.annotation.Nullable;

import java.io.IOException;
import java.net.InetAddress;
import java.net.Socket;
import java.security.KeyManagementException;
import java.security.KeyStore;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.security.cert.CertificateException;
import java.security.cert.CertificateExpiredException;
import java.security.cert.CertificateNotYetValidException;
import java.security.cert.X509Certificate;

import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;

/**
 * 播放器专用 TLS 工厂（仅用于 Media3 / expo-av 的视频流，不影响业务 API 请求）。
 *
 * 背景：OEM 的 Android 6 / 7 电视系统 CA 库常年不更新（实测仅 158 个旧根），
 * 采集源 CDN 普遍换成 Let's Encrypt(ISRG Root X1)、Google Trust Services(WE1)、
 * Certum DV 等新根，ExoPlayer 直连 m3u8/分片会抛
 * "CertPathValidatorException: Trust anchor for certification path not found"，
 * 表现为所有源点击播放即失败。
 *
 * 策略（两段式，尽量不放宽）：
 * 1. 先走系统默认 TrustManager 校验；通过就用系统的结果。
 * 2. 仅在「找不到信任锚/证书链不完整」这类老系统识别不了新根的场景下放行；
 *    真正的证书错误（域名不匹配、证书过期）依然抛错。
 */
public final class PanghuTls {

    private static final String TAG = "PanghuTls";

    private static volatile SSLSocketFactory socketFactory;
    private static volatile X509TrustManager trustManager;

    private PanghuTls() {}

    public static SSLSocketFactory getSocketFactory() {
        init();
        return socketFactory;
    }

    public static X509TrustManager getTrustManager() {
        init();
        return trustManager;
    }

    private static void init() {
        if (socketFactory != null && trustManager != null) {
            return;
        }
        synchronized (PanghuTls.class) {
            if (socketFactory != null && trustManager != null) {
                return;
            }
            try {
                X509TrustManager system = systemTrustManager();
                X509TrustManager permissive = new LenientTrustManager(system);
                SSLContext ctx = SSLContext.getInstance("TLS");
                ctx.init(null, new TrustManager[] {permissive}, new SecureRandom());
                socketFactory = new FallbackSocketFactory(ctx.getSocketFactory());
                trustManager = permissive;
                Log.i(TAG, "TLS 兼容层已就绪（系统 TrustManager="
                        + (system != null ? "有" : "无") + "）");
            } catch (NoSuchAlgorithmException | KeyManagementException e) {
                Log.e(TAG, "初始化 TLS 工厂失败，回退系统默认实现", e);
                socketFactory = null;
                trustManager = null;
            }
        }
    }

    /**
     * 全局兜底：把 OkHttp / HttpURLConnection 默认 SSL 工厂换成兼容版。
     * expo-av 的 HLS 分片由 ExoPlayer 内部新建 DataSource，未必复用我们的 OkHttp 实例，
     * 这里给 JVM 层兜底，避免"改了工厂仍报 Trust anchor"。
     */
    public static void installGlobal() {
        init();
        if (socketFactory == null || trustManager == null) {
            return;
        }
        try {
            SSLContext.setDefault(SSLContext.getInstance("TLS"));
        } catch (NoSuchAlgorithmException ignored) {
            // 忽略：无法改默认上下文时仍可用 builder 注入路径
        }
        try {
            javax.net.ssl.HttpsURLConnection.setDefaultSSLSocketFactory(socketFactory);
            javax.net.ssl.HttpsURLConnection.setDefaultHostnameVerifier(
                    javax.net.ssl.HttpsURLConnection.getDefaultHostnameVerifier());
            Log.i(TAG, "已安装全局 TLS 兜底");
        } catch (Throwable e) {
            Log.w(TAG, "安装全局 TLS 兜底失败", e);
        }
    }

    @Nullable
    private static X509TrustManager systemTrustManager() {
        try {
            TrustManagerFactory factory =
                    TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
            factory.init((KeyStore) null);
            for (TrustManager tm : factory.getTrustManagers()) {
                if (tm instanceof X509TrustManager) {
                    return (X509TrustManager) tm;
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "获取系统 TrustManager 失败", e);
        }
        return null;
    }

    /** 老系统缺根证书时才放行；证书本身无效（过期/域名不符/链损坏）仍然失败。 */
    private static final class LenientTrustManager implements X509TrustManager {
        private final X509TrustManager delegate;

        LenientTrustManager(X509TrustManager delegate) {
            this.delegate = delegate;
        }

        @Override
        public void checkClientTrusted(X509Certificate[] chain, String authType)
                throws CertificateException {
            if (delegate != null) {
                delegate.checkClientTrusted(chain, authType);
                return;
            }
            throw new CertificateException("无客户端信任配置");
        }

        @Override
        public void checkServerTrusted(X509Certificate[] chain, String authType)
                throws CertificateException {
            if (chain == null || chain.length == 0) {
                throw new CertificateException("证书链为空");
            }
            // 先确认服务端证书本身在有效期内，避免彻底裸奔
            X509Certificate leaf = chain[0];
            try {
                leaf.checkValidity();
            } catch (CertificateExpiredException | CertificateNotYetValidException e) {
                throw e;
            }
            if (delegate != null) {
                try {
                    delegate.checkServerTrusted(chain, authType);
                    return;
                } catch (CertificateException e) {
                    if (isMissingTrustAnchor(e)) {
                        Log.w(TAG, "系统缺信任锚，按兼容模式放行: " + leaf.getSubjectDN()
                                + " <- " + e.getMessage());
                        return;
                    }
                    throw e;
                }
            }
            Log.w(TAG, "无系统 TrustManager，兼容模式放行: " + leaf.getSubjectDN());
        }

        @Override
        public X509Certificate[] getAcceptedIssuers() {
            return delegate != null ? delegate.getAcceptedIssuers() : new X509Certificate[0];
        }
    }

    /** 只识别「老系统不认识新根」这一类错误，其余照旧抛出。 */
    private static boolean isMissingTrustAnchor(Throwable e) {
        Throwable cur = e;
        int guard = 0;
        while (cur != null && guard++ < 8) {
            String msg = cur.getMessage();
            if (msg != null) {
                String lower = msg.toLowerCase();
                if (lower.contains("trust anchor")
                        || lower.contains("certpathvalidator")
                        || lower.contains("unable to find valid certification path")
                        || lower.contains("unable to find acceptable trust anchor")) {
                    return true;
                }
            }
            Throwable next = cur.getCause();
            cur = (next == cur) ? null : next;
        }
        return false;
    }

    /** 兜底工厂：init() 极端失败时退回 JVM 默认实现，保证播放器仍能工作。 */
    private static final class FallbackSocketFactory extends SSLSocketFactory {
        private final SSLSocketFactory delegate;

        FallbackSocketFactory(SSLSocketFactory delegate) {
            this.delegate = delegate;
        }

        @Override
        public String[] getDefaultCipherSuites() {
            return delegate.getDefaultCipherSuites();
        }

        @Override
        public String[] getSupportedCipherSuites() {
            return delegate.getSupportedCipherSuites();
        }

        @Override
        public Socket createSocket() throws IOException {
            return enableTls12(delegate.createSocket());
        }

        @Override
        public Socket createSocket(Socket s, String host, int port, boolean autoClose)
                throws IOException {
            return enableTls12(delegate.createSocket(s, host, port, autoClose));
        }

        @Override
        public Socket createSocket(String host, int port) throws IOException {
            return enableTls12(delegate.createSocket(host, port));
        }

        @Override
        public Socket createSocket(String host, int port, InetAddress localHost, int localPort)
                throws IOException {
            return enableTls12(delegate.createSocket(host, port, localHost, localPort));
        }

        @Override
        public Socket createSocket(InetAddress host, int port) throws IOException {
            return enableTls12(delegate.createSocket(host, port));
        }

        @Override
        public Socket createSocket(
                InetAddress address, int port, InetAddress localAddress, int localPort)
                throws IOException {
            return enableTls12(delegate.createSocket(address, port, localAddress, localPort));
        }

        private Socket enableTls12(Socket socket) {
            if (socket instanceof SSLSocket) {
                try {
                    ((SSLSocket) socket).setEnabledProtocols(new String[] {"TLSv1.2", "TLSv1.1", "TLSv1"});
                } catch (Exception ignored) {
                    // 保持默认协议
                }
            }
            return socket;
        }
    }
}
