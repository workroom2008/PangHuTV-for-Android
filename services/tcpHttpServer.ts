import TcpSocket from 'react-native-tcp-socket';
import NetInfo from '@react-native-community/netinfo';
import { NativeModules, Platform } from 'react-native';
import Logger from '@/utils/Logger';

const logger = Logger.withTag('TCPHttpServer');

const PORT = 12346;

/** 原生远程输入服务（Android，RemoteInputModule） */
const NativeRemoteInput: any = (NativeModules as any)?.RemoteInput ?? null;

interface HttpRequest {
  method: string;
  url: string;
  headers: { [key: string]: string };
  body: string;
}

interface HttpResponse {
  statusCode: number;
  headers: { [key: string]: string };
  body: string;
}

type RequestHandler = (request: HttpRequest) => HttpResponse | Promise<HttpResponse>;

class TCPHttpServer {
  private server: TcpSocket.Server | null = null;
  private isRunning = false;
  private requestHandler: RequestHandler | null = null;
  private nativeUrl: string | null = null;

  constructor() {
    this.server = null;
  }

  private parseHttpRequest(data: string): HttpRequest | null {
    try {
      const lines = data.split('\r\n');
      const requestLine = lines[0].split(' ');
      
      if (requestLine.length < 3) {
        return null;
      }

      const method = requestLine[0];
      const url = requestLine[1];
      const headers: { [key: string]: string } = {};
      
      let bodyStartIndex = -1;
      for (let i = 1; i < lines.length; i++) {
        const line = lines[i];
        if (line === '') {
          bodyStartIndex = i + 1;
          break;
        }
        const colonIndex = line.indexOf(':');
        if (colonIndex > 0) {
          const key = line.substring(0, colonIndex).trim().toLowerCase();
          const value = line.substring(colonIndex + 1).trim();
          headers[key] = value;
        }
      }

      const body = bodyStartIndex > 0 ? lines.slice(bodyStartIndex).join('\r\n') : '';

      return { method, url, headers, body };
    } catch (error) {
      logger.info('[TCPHttpServer] Error parsing HTTP request:', error);
      return null;
    }
  }

  private formatHttpResponse(response: HttpResponse): Buffer {
    const statusTexts: { [key: number]: string } = {
      200: 'OK',
      400: 'Bad Request',
      404: 'Not Found',
      500: 'Internal Server Error'
    };

    const statusText = statusTexts[response.statusCode] || 'Unknown';
    // 统一按 UTF-8 字节编码：中文/emoji 的字节数与字符数不同，
    // 之前用字符数当 Content-Length 会让浏览器少读几个字节，JSON 被截断，
    // 前端就报 "Failed to execute 'json' on 'Response': Unexpected end of JSON input"。
    const bodyBytes = new TextEncoder().encode(response.body ?? '');
    const headers: { [key: string]: string } = {
      ...response.headers,
      'Content-Type': response.headers?.['Content-Type'] ?? 'text/plain; charset=utf-8',
      'Content-Length': String(bodyBytes.length),
      'Connection': 'close',
    };

    let head = `HTTP/1.1 ${response.statusCode} ${statusText}\r\n`;
    for (const [key, value] of Object.entries(headers)) {
      head += `${key}: ${value}\r\n`;
    }
    head += '\r\n';

    const headBytes = new TextEncoder().encode(head);
    const out = new Uint8Array(headBytes.length + bodyBytes.length);
    out.set(headBytes, 0);
    out.set(bodyBytes, headBytes.length);
    return Buffer.from(out.buffer, out.byteOffset, out.byteLength);
  }

  public setRequestHandler(handler: RequestHandler) {
    this.requestHandler = handler;
  }

  private isPrivateIPv4(ip: string): boolean {
    const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(String(ip).trim());
    if (!m) return false;
    const a = Number(m[1]);
    const b = Number(m[2]);
    if (a === 0 || a === 127 || a >= 224) return false;
    if (a === 10) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    // 部分路由器给 26.x / 100.64 这类运营商段，也允许（只要不是公网常规段）
    return false;
  }

  private ipPriority(ip: string): number {
    if (ip.startsWith('192.168.')) return 0;
    if (ip.startsWith('10.')) return 1;
    if (ip.startsWith('172.')) return 2;
    return 3;
  }

  /**
   * 多手段解析局域网 IPv4。
   *
   * 原实现只读 NetInfo.details.ipAddress，电视走以太网、或 details 里只有
   * ipv4/ipAddresses、或接口名非 wlan0 时拿到 null/错值，直接把
   * http://null:12346（或不可达 IP）放进二维码，手机扫码必然打不开。
   */
  private async resolveLanIp(): Promise<string | null> {
    const candidates: string[] = [];

    const collect = (v: unknown) => {
      if (typeof v === 'string' && this.isPrivateIPv4(v)) candidates.push(v.trim());
    };

    for (let attempt = 0; attempt < 6; attempt++) {
      try {
        const netState = await NetInfo.fetch();
        const d: any = netState.details ?? {};
        collect(d.ipAddress);
        collect(d.ipv4);
        if (Array.isArray(d.ipAddresses)) d.ipAddresses.forEach(collect);
        if (Array.isArray(d.details)) d.details.forEach((x: any) => collect(x?.ipAddress));
        collect(d?.subnet && d?.ipAddress);
      } catch (e) {
        logger.info('[TCPHttpServer] NetInfo.fetch failed:', e);
      }
      if (candidates.length) break;
      await new Promise((r) => setTimeout(r, 1000));
    }

    const uniq = Array.from(new Set(candidates));
    if (uniq.length === 0) return null;
    uniq.sort((a, b) => this.ipPriority(a) - this.ipPriority(b));
    logger.debug('[TCPHttpServer] resolved LAN IP candidates:', uniq, '->', uniq[0]);
    return uniq[0];
  }

  public async start(): Promise<string> {
    // Android：走原生 HTTP server。
    // react-native-tcp-socket 在 OEM Android 6 TV 上 accept 后读线程卡死
    // （连接 ESTABLISHED 但服务端零响应，手机/浏览器永远打不开），原生实现绕开该缺陷。
    if (Platform.OS === 'android' && NativeRemoteInput) {
      const url = await this.startNative();
      this.isRunning = true;
      return url;
    }

    // 冷启动时网络栈可能未就绪，NetInfo 拿不到 IP：多手段探测并重试
    const ipAddress = await this.resolveLanIp();

    if (!ipAddress) {
      throw new Error('无法获取局域网 IP，请确认电视已连 WiFi 或网线；可在电视系统设置里查看本机 IP。');
    }

    if (this.isRunning) {
      logger.debug('[TCPHttpServer] Server is already running.');
      return `http://${ipAddress}:${PORT}`;
    }

    return new Promise((resolve, reject) => {
      try {
        this.server = TcpSocket.createServer((socket: TcpSocket.Socket) => {
          logger.debug('[TCPHttpServer] Client connected');

          // 按字节累计：中文 UTF-8 是多字节，按字符串拼接再用字符数判断会算错长度
          const chunks: Uint8Array[] = [];
          let received = 0;
          let headerEnd = -1;
          let bodyNeed = 0;
          let handled = false;

          const allBytes = (): Uint8Array => {
            const out = new Uint8Array(received);
            let offset = 0;
            for (const c of chunks) {
              out.set(c, offset);
              offset += c.length;
            }
            return out;
          };

          const tryHandle = async () => {
            if (handled) return;

            const bytes = allBytes();
            const decoder = new TextDecoder();

            if (headerEnd < 0) {
              // 找 \r\n\r\n（字节级）
              for (let i = 0; i + 3 < bytes.length; i++) {
                if (bytes[i] === 13 && bytes[i + 1] === 10 && bytes[i + 2] === 13 && bytes[i + 3] === 10) {
                  headerEnd = i + 4;
                  break;
                }
              }
              if (headerEnd < 0) return;
              const headText = decoder.decode(bytes.subarray(0, headerEnd));
              const m = /content-length:\s*(\d+)/i.exec(headText);
              bodyNeed = m ? parseInt(m[1], 10) : 0;
            }

            // 请求体没收全就先等下一个 data 包（大 JSON / 中文配置会分片到达）
            if (bytes.length - headerEnd < bodyNeed) return;

            handled = true;

            try {
              const raw = decoder.decode(bytes.subarray(0, headerEnd + bodyNeed));
              const request = this.parseHttpRequest(raw);
              if (request && this.requestHandler) {
                const response = await this.requestHandler(request);
                socket.write(this.formatHttpResponse(response));
              } else {
                socket.write(
                  this.formatHttpResponse({
                    statusCode: 400,
                    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
                    body: 'Bad Request'
                  })
                );
              }
            } catch (error) {
              logger.info('[TCPHttpServer] Error handling request:', error);
              socket.write(
                this.formatHttpResponse({
                  statusCode: 500,
                  headers: { 'Content-Type': 'application/json; charset=utf-8' },
                  body: JSON.stringify({ status: 'error', message: 'Internal Server Error' })
                })
              );
            }

            socket.end();
          };

          socket.on('data', (data: string | Buffer) => {
            const chunk =
              typeof data === 'string' ? new TextEncoder().encode(data) : new Uint8Array(data);
            chunks.push(chunk);
            received += chunk.length;
            void tryHandle();
          });

          socket.on('error', (error: Error) => {
            logger.info('[TCPHttpServer] Socket error:', error);
          });

          socket.on('close', () => {
            logger.debug('[TCPHttpServer] Client disconnected');
          });
        });

        this.server.listen({ port: PORT, host: '0.0.0.0' }, () => {
          logger.debug(`[TCPHttpServer] Server listening on ${ipAddress}:${PORT}`);
          this.isRunning = true;
          resolve(`http://${ipAddress}:${PORT}`);
        });

        this.server.on('error', (error: Error) => {
          logger.info('[TCPHttpServer] Server error:', error);
          this.isRunning = false;
          reject(error);
        });

      } catch (error) {
        logger.info('[TCPHttpServer] Failed to start server:', error);
        reject(error);
      }
    });
  }

  /**
   * Android 原生 HTTP server。
   * JS 只负责：把当前配置渲染成页面 HTML 塞给原生，以及接收原生转发来的 POST 事件。
   */
  private async startNative(): Promise<string> {
    const res = await NativeRemoteInput.start();
    const url: string = res?.url ?? `http://127.0.0.1:${PORT}`;
    this.nativeUrl = url;

    // 页面 HTML 由 service 层提供（remoteControlService 注册 handler 后才有内容）
    if (this.requestHandler) {
      const page = await this.requestHandler({
        method: 'GET',
        url: '/',
        headers: {},
        body: '',
      });
      NativeRemoteInput.setPage?.(page?.body ?? '');
    }

    this.isRunning = true;
    logger.debug('[TCPHttpServer] Native server listening at', url);
    return url;
  }

  public stop() {
    if (Platform.OS === 'android' && NativeRemoteInput && this.isRunning) {
      NativeRemoteInput.stop?.().catch?.(() => {});
      this.isRunning = false;
      logger.debug('[TCPHttpServer] Native server stopped');
      return;
    }
    if (this.server && this.isRunning) {
      this.server.close();
      this.server = null;
      this.isRunning = false;
      logger.debug('[TCPHttpServer] Server stopped');
    }
  }

  public getIsRunning(): boolean {
    return this.isRunning;
  }
}

export default TCPHttpServer;