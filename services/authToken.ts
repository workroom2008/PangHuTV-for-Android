import AsyncStorage from "@react-native-async-storage/async-storage";

const AUTH_TOKEN_KEY = "mytv_auth_token";
const SERVER_FLAGS_KEY = "mytv_server_flags";

export interface ServerFlags {
  privateAccess: boolean;
  requireWebLogin: boolean;
}

// 同步镜像：URL 构造（海报/播放地址追加 token）需要同步取 token
let cachedToken: string | null = null;

export async function getAuthToken(): Promise<string | null> {
  const t = await AsyncStorage.getItem(AUTH_TOKEN_KEY);
  cachedToken = t;
  return t;
}

export function getCachedAuthToken(): string | null {
  return cachedToken;
}

export async function setAuthToken(token: string): Promise<void> {
  cachedToken = token;
  await AsyncStorage.setItem(AUTH_TOKEN_KEY, token);
}

export async function clearAuthToken(): Promise<void> {
  cachedToken = null;
  await AsyncStorage.removeItem(AUTH_TOKEN_KEY);
}

export async function getServerFlags(): Promise<ServerFlags> {
  const raw = await AsyncStorage.getItem(SERVER_FLAGS_KEY);
  if (!raw) {
    return { privateAccess: false, requireWebLogin: false };
  }
  try {
    const parsed = JSON.parse(raw);
    return {
      privateAccess: !!parsed.privateAccess,
      requireWebLogin: !!parsed.requireWebLogin,
    };
  } catch {
    return { privateAccess: false, requireWebLogin: false };
  }
}

export async function setServerFlags(flags: ServerFlags): Promise<void> {
  await AsyncStorage.setItem(SERVER_FLAGS_KEY, JSON.stringify(flags));
}

export async function clearServerFlags(): Promise<void> {
  await AsyncStorage.removeItem(SERVER_FLAGS_KEY);
}
