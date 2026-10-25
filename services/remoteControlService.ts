import TCPHttpServer from "./tcpHttpServer";
import { NativeEventEmitter, NativeModules, Platform } from "react-native";
import Logger from '@/utils/Logger';

const logger = Logger.withTag('RemoteControl');

export interface RemoteConfigPayload {
  apiBaseUrl?: string;
  username?: string;
  password?: string;
  m3uUrl?: string;
}

const escapeHtml = (s: string) =>
  String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

const getRemotePageHTML = (current: RemoteConfigPayload) => {
  const currentJson = JSON.stringify(current).replace(/</g, "\\u003c");
  return `
  <!DOCTYPE html>
  <html>
  <head>
    <title>胖虎TV 远程配置</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh; margin: 0; background-color: #121212; color: white; padding: 16px; box-sizing: border-box; }
      h3 { color: #eee; margin: 0 0 4px; }
      .tip { color: #999; font-size: 13px; margin-bottom: 18px; text-align: center; }
      #container { display: flex; flex-direction: column; width: 100%; max-width: 400px; }
      label { font-size: 13px; color: #bbb; margin: 10px 0 4px; }
      input { width: 100%; padding: 12px; font-size: 16px; border-radius: 8px; border: 1px solid #333; background-color: #2a2a2a; color: white; box-sizing: border-box; }
      button { width: 100%; padding: 14px; margin-top: 20px; font-size: 17px; font-weight: bold; border: none; border-radius: 8px; background-color: #FA8C16; color: white; cursor: pointer; }
      button:active { background-color: #d97706; }
      #result { margin-top: 14px; font-size: 14px; text-align: center; min-height: 20px; }
      #result.ok { color: #4ade80; }
      #result.err { color: #f87171; }
      .search-box { margin-top: 28px; padding-top: 18px; border-top: 1px solid #333; }
      .search-row { display: flex; gap: 8px; }
      .search-row input { flex: 1; }
      .search-row button { width: auto; padding: 12px 18px; margin-top: 0; background-color: #007AFF; }
    </style>
  </head>
  <body>
    <div id="container">
      <h3>胖虎TV 远程配置</h3>
      <div class="tip">填写后点「保存到电视」，电视端立即生效</div>
      <label>服务器地址（API）</label>
      <input id="apiBaseUrl" placeholder="http://192.168.1.250:3008" />
      <label>用户名</label>
      <input id="username" placeholder="用户名" />
      <label>密码</label>
      <input id="password" type="password" placeholder="密码" />
      <label>直播源 m3u 地址（可选）</label>
      <input id="m3uUrl" placeholder="http://.../live.m3u" />
      <button id="saveBtn" onclick="save()">保存到电视</button>
      <div id="result"></div>
      <div class="search-box">
        <label>发送文本到电视（搜索页使用）</label>
        <div class="search-row">
          <input id="text" placeholder="搜索关键词..." />
          <button onclick="send()">发送</button>
        </div>
      </div>
    </div>
    <script>
      const CURRENT = ${currentJson};
      window.addEventListener('DOMContentLoaded', () => {
        for (const k of ['apiBaseUrl', 'username', 'password', 'm3uUrl']) {
          if (CURRENT[k]) document.getElementById(k).value = CURRENT[k];
        }
        fetch('/handshake', { method: 'POST' }).catch(() => {});
      });
      function show(cls, msg) {
        const el = document.getElementById('result');
        el.className = cls; el.textContent = msg;
      }
      async function save() {
        const btn = document.getElementById('saveBtn');
        btn.disabled = true;
        try {
          const body = {
            apiBaseUrl: document.getElementById('apiBaseUrl').value.trim(),
            username: document.getElementById('username').value.trim(),
            password: document.getElementById('password').value,
            m3uUrl: document.getElementById('m3uUrl').value.trim(),
          };
          if (!body.apiBaseUrl) { show('err', '服务器地址不能为空'); return; }
          show('', '正在保存…');
          const res = await fetch('/config', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
          });
          // 电视端是自建 TCP 服务，偶发空响应/被截断：先取文本再解析，避免 res.json() 直接抛
          const text = await res.text();
          let data = null;
          if (text) { try { data = JSON.parse(text); } catch (e) { data = null; } }
          if (data && data.status === 'ok') show('ok', data.message || '已保存并生效');
          else if (data) show('err', data.message || '保存失败');
          else if (res.status === 200) show('ok', '已保存并生效（电视端无回执，请到电视上确认服务器地址）');
          else show('err', '电视端返回异常（HTTP ' + res.status + '），请确认电视与手机在同一网络后重试');
        } catch (e) { show('err', '发送失败：' + e + '（请确认电视端远程输入已开启）'); }
        finally { btn.disabled = false; }
      }
      async function send() {
        const input = document.getElementById('text');
        const value = input.value;
        if (value) {
          await fetch('/message', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ message: value }),
          }).catch(() => {});
          input.value = '';
        }
      }
    </script>
  </body>
  </html>
  `;
};

interface RemoteControlActions {
  onMessage: (message: string) => void;
  onHandshake: () => void;
  /** 返回电视端当前配置（供表单回显） */
  getConfig: () => RemoteConfigPayload | Promise<RemoteConfigPayload>;
  /** 应用手机端提交的配置，返回 { status, message } */
  applyConfig: (config: RemoteConfigPayload) => Promise<{ status: "ok" | "error"; message: string }>;
}

class RemoteControlService {
  private httpServer: TCPHttpServer;
  private onMessage: (message: string) => void = () => {};
  private onHandshake: () => void = () => {};
  private getConfig: () => RemoteConfigPayload | Promise<RemoteConfigPayload> = () => ({});
  private applyConfig: RemoteControlActions["applyConfig"] = async () => ({
    status: "error",
    message: "未注册配置处理",
  });

  constructor() {
    this.httpServer = new TCPHttpServer();
    this.setupRequestHandler();
    this.setupNativeBridge();
  }

  /**
   * Android 原生 HTTP server 桥接。
   * 原生侧只负责收包，业务仍在 JS：用同一套 requestHandler 处理并回写页面。
   */
  private setupNativeBridge() {
    const native: any = (NativeModules as any)?.RemoteInput;
    if (!native || Platform.OS !== "android") return;

    const emitter = new NativeEventEmitter(native);
    emitter.addListener("onConfig", async (evt: { payload: string }) => {
      try {
        const body = evt?.payload || "{}";
        const result = await this.applyConfig(JSON.parse(body) || {});
        logger.info("[RemoteControl] native /config ->", result);
      } catch (e) {
        logger.info("[RemoteControl] native /config failed:", e);
      }
    });

    emitter.addListener("onHandshake", () => {
      this.onHandshake();
    });

    // 手机端「发送文本到电视」→ 原生 postMessage → 这里转给业务层（搜索页）
    emitter.addListener("RemoteInputText", (evt: { text?: string }) => {
      const text = evt?.text ?? "";
      logger.debug("[RemoteControl] native text:", text);
      if (text) this.onMessage(text);
    });
  }

  /** 手机端提交配置后，设置页/原生页面需要同步最新值 */
  public async pushPage() {
    await this.refreshPage();
  }

  /** 页面 HTML 变化时同步给原生 server */
  public async refreshPage() {
    const native: any = (NativeModules as any)?.RemoteInput;
    if (!native || Platform.OS !== "android") return;
    try {
      native.setPage?.(getRemotePageHTML(await this.getConfig()));
    } catch (e) {
      logger.info("[RemoteControl] refreshPage failed:", e);
    }
  }

  private setupRequestHandler() {
    this.httpServer.setRequestHandler(async (request) => {
      logger.debug("[RemoteControl] Received request:", request.method, request.url);

      // 浏览器可能带查询串或结尾斜杠，路由按路径比较
      const path = (request.url || "/").split("?")[0].replace(/\/+$/, "") || "/";
      const method = (request.method || "GET").toUpperCase();

      try {
        if (method === "GET" && (path === "/" || path === "/index.html")) {
          return {
            statusCode: 200,
            headers: { "Content-Type": "text/html; charset=utf-8" },
            body: getRemotePageHTML(await this.getConfig()),
          };
        } else if (method === "POST" && path === "/config") {
          try {
            const parsedBody = JSON.parse(request.body || "{}");
            const result = await this.applyConfig(parsedBody || {});
            return {
              statusCode: 200,
              headers: { "Content-Type": "application/json; charset=utf-8" },
              body: JSON.stringify(result),
            };
          } catch (parseError) {
            logger.info("[RemoteControl] Failed to parse config body:", parseError);
            return {
              statusCode: 200,
              headers: { "Content-Type": "application/json; charset=utf-8" },
              body: JSON.stringify({ status: "error", message: "配置内容解析失败，请重试" }),
            };
          }
        } else if (method === "POST" && path === "/message") {
          try {
            const parsedBody = JSON.parse(request.body || "{}");
            const message = parsedBody.message;
            if (message) {
              this.onMessage(message);
            }
            return {
              statusCode: 200,
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ status: "ok" }),
            };
          } catch (parseError) {
            logger.info("[RemoteControl] Failed to parse message body:", parseError);
            return {
              statusCode: 200,
              headers: { "Content-Type": "application/json; charset=utf-8" },
              body: JSON.stringify({ status: "error", message: "消息解析失败" }),
            };
          }
        } else if (method === "POST" && path === "/handshake") {
          this.onHandshake();
          return {
            statusCode: 200,
            headers: { "Content-Type": "application/json; charset=utf-8" },
            body: JSON.stringify({ status: "ok" }),
          };
        } else {
          return {
            statusCode: 404,
            headers: { "Content-Type": "text/plain; charset=utf-8" },
            body: "Not Found",
          };
        }
      } catch (error) {
        logger.info("[RemoteControl] Request handler error:", error);
        return {
          statusCode: 200,
          headers: { "Content-Type": "application/json; charset=utf-8" },
          body: JSON.stringify({ status: "error", message: "电视端处理异常，请重试" }),
        };
      }
    });
  }

  public init(actions: RemoteControlActions) {
    this.onMessage = actions.onMessage;
    this.onHandshake = actions.onHandshake;
    this.getConfig = actions.getConfig;
    this.applyConfig = actions.applyConfig;
  }

  public async startServer(): Promise<string> {
    logger.debug("[RemoteControl] Attempting to start server...");

    try {
      const url = await this.httpServer.start();
      logger.debug(`[RemoteControl] Server started successfully at: ${url}`);
      return url;
    } catch (error) {
      logger.info("[RemoteControl] Failed to start server:", error);
      throw new Error(error instanceof Error ? error.message : "Failed to start server");
    }
  }

  public stopServer() {
    logger.debug("[RemoteControl] Stopping server...");
    this.httpServer.stop();
  }

  public isRunning(): boolean {
    return this.httpServer.getIsRunning();
  }
}

export const remoteControlService = new RemoteControlService();
