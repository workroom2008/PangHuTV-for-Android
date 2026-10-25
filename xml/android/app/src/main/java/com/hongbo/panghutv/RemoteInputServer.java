package com.hongbo.panghutv;

import android.util.Log;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.Charset;
import java.util.Collections;
import java.util.Enumeration;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 远程输入 HTTP 服务（原生实现）。
 *
 * 为什么不用 react-native-tcp-socket：
 * 该库在 OEM Android 6 TV 上 accept 出来的 socket 读线程会卡住（连接能建立，
 * 但服务端永远吐不出响应），实测 netstat 显示 ESTABLISHED 却零字节回包。
 * 这里用原生 ServerSocket 直接实现最小 HTTP/1.1，行为可控。
 *
 * 路由：
 *   GET  /            配置页 HTML
 *   POST /config      应用配置
 *   POST /message     发送文本到电视
 *   POST /handshake   手机端已连上（收起引导）
 */
public final class RemoteInputServer {

    private static final String TAG = "RemoteInputServer";
    public static final int PORT = 12346;

    private static ServerSocket serverSocket;
    private static Thread acceptThread;
    private static final AtomicBoolean running = new AtomicBoolean(false);

    private RemoteInputServer() {}

    public interface Handler {
        /** 返回配置页 HTML */
        String onGetPage();

        /** 返回 JSON 字符串 */
        String onConfig(String body);

        /** 返回 JSON 字符串 */
        String onMessage(String body);

        /** 握手 */
        String onHandshake(boolean connected);
    }

    private static volatile Handler handler;

    public static void setHandler(Handler h) {
        handler = h;
    }

    /** 取本机第一个可用局域网 IPv4；找不到返回 null */
    public static String getLanIp() {
        try {
            for (NetworkInterface nif : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!nif.isUp() || nif.isLoopback()) continue;
                String name = nif.getName();
                if (name.startsWith("dummy")) continue;
                for (InetAddress addr : Collections.list(nif.getInetAddresses())) {
                    if (addr.isLoopbackAddress() || addr.isLinkLocalAddress()) continue;
                    String ip = addr.getHostAddress();
                    if (ip == null || ip.indexOf(':') >= 0) continue; // 跳过 IPv6
                    if (ip.startsWith("10.")
                            || ip.startsWith("192.168.")
                            || ip.startsWith("172.16.") || ip.startsWith("172.17.")
                            || ip.startsWith("172.18.") || ip.startsWith("172.19.")
                            || ip.startsWith("172.2") || ip.startsWith("172.30.")
                            || ip.startsWith("172.31.")) {
                        return ip;
                    }
                }
            }
            // 没有私网地址时退回第一个非回环 IPv4
            for (NetworkInterface nif : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!nif.isUp() || nif.isLoopback()) continue;
                for (InetAddress addr : Collections.list(nif.getInetAddresses())) {
                    String ip = addr.getHostAddress();
                    if (ip != null && ip.indexOf(':') < 0 && !addr.isLoopbackAddress()) return ip;
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "getLanIp failed: " + e);
        }
        return null;
    }

    public static synchronized String start() throws IOException {
        if (running.get() && serverSocket != null && !serverSocket.isClosed()) {
            String ip = getLanIp();
            return "http://" + (ip != null ? ip : "127.0.0.1") + ":" + PORT;
        }
        String ip = getLanIp();
        if (ip == null) throw new IOException("无法获取局域网 IP");

        ServerSocket ss = new ServerSocket(PORT, 32, InetAddress.getByName("0.0.0.0"));
        ss.setReuseAddress(true);
        serverSocket = ss;
        running.set(true);

        acceptThread = new Thread(() -> {
            while (running.get() && !ss.isClosed()) {
                Socket client = null;
                try {
                    client = ss.accept();
                    handleClient(client);
                } catch (IOException e) {
                    if (running.get()) Log.w(TAG, "accept/handle failed: " + e);
                } finally {
                    try { if (client != null) client.close(); } catch (IOException ignored) {}
                }
            }
        }, "remote-input-accept");
        acceptThread.setDaemon(true);
        acceptThread.start();

        Log.i(TAG, "listening on " + ip + ":" + PORT);
        return "http://" + ip + ":" + PORT;
    }

    public static synchronized void stop() {
        running.set(false);
        try { if (serverSocket != null) serverSocket.close(); } catch (IOException ignored) {}
        serverSocket = null;
        acceptThread = null;
    }

    public static boolean isRunning() {
        return running.get() && serverSocket != null && !serverSocket.isClosed();
    }

    private static void handleClient(Socket client) throws IOException {
        client.setSoTimeout(8000);

        InputStream rawIn = client.getInputStream();
        ByteArrayOutputStream headBuf = new ByteArrayOutputStream();
        int b;
        int match = 0;
        // 读 header 直到 \r\n\r\n
        while (match < 4 && (b = rawIn.read()) != -1) {
            headBuf.write(b);
            if ((match == 0 || match == 2) && b == '\r') match++;
            else if ((match == 1 || match == 3) && b == '\n') match++;
            else match = (b == '\r') ? 1 : 0;
            if (headBuf.size() > 64 * 1024) break;
        }
        if (headBuf.size() == 0) return;

        String head = new String(headBuf.toByteArray(), Charset.forName("UTF-8"));
        String[] lines = head.split("\r\n");
        String[] requestLine = lines.length > 0 ? lines[0].split(" ") : new String[0];
        String method = requestLine.length > 0 ? requestLine[0].toUpperCase() : "GET";
        String path = requestLine.length > 1 ? requestLine[1] : "/";
        int q = path.indexOf('?');
        if (q >= 0) path = path.substring(0, q);
        if (path.endsWith("/") && path.length() > 1) path = path.substring(0, path.length() - 1);
        if (path.isEmpty()) path = "/";

        int contentLength = 0;
        for (int i = 1; i < lines.length; i++) {
            String line = lines[i];
            int c = line.indexOf(':');
            if (c <= 0) continue;
            if ("content-length".equalsIgnoreCase(line.substring(0, c).trim())) {
                try { contentLength = Integer.parseInt(line.substring(c + 1).trim()); } catch (Exception ignored) {}
            }
        }

        byte[] bodyBytes = new byte[0];
        if (contentLength > 0) {
            byte[] buf = new byte[contentLength];
            int read = 0;
            while (read < contentLength) {
                int n = rawIn.read(buf, read, contentLength - read);
                if (n <= 0) break;
                read += n;
            }
            bodyBytes = buf;
        }
        String body = new String(bodyBytes, Charset.forName("UTF-8"));

        Handler h = handler;
        int status = 200;
        String contentType = "application/json; charset=utf-8";
        String responseBody;

        if (h == null) {
            status = 500;
            responseBody = "{\"status\":\"error\",\"message\":\"服务未初始化\"}";
        } else if ("GET".equals(method) && ("/".equals(path) || "/index.html".equals(path))) {
            contentType = "text/html; charset=utf-8";
            responseBody = h.onGetPage();
        } else if ("POST".equals(method) && "/config".equals(path)) {
            responseBody = h.onConfig(body);
        } else if ("POST".equals(method) && "/message".equals(path)) {
            responseBody = h.onMessage(body);
        } else if ("POST".equals(method) && "/handshake".equals(path)) {
            responseBody = h.onHandshake(true);
        } else {
            status = 404;
            contentType = "text/plain; charset=utf-8";
            responseBody = "Not Found";
        }

        byte[] out = responseBody == null ? new byte[0] : responseBody.getBytes(Charset.forName("UTF-8"));
        StringBuilder sb = new StringBuilder();
        sb.append("HTTP/1.1 ").append(status).append(status == 200 ? " OK" : status == 404 ? " Not Found" : " Error").append("\r\n");
        sb.append("Content-Type: ").append(contentType).append("\r\n");
        sb.append("Content-Length: ").append(out.length).append("\r\n");
        sb.append("Cache-Control: no-store\r\n");
        sb.append("Access-Control-Allow-Origin: *\r\n");
        sb.append("Connection: close\r\n\r\n");
        OutputStream os = client.getOutputStream();
        os.write(sb.toString().getBytes(Charset.forName("UTF-8")));
        os.write(out);
        os.flush();
    }
}
