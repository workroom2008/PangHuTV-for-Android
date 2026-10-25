import AsyncStorage from "@react-native-async-storage/async-storage";

const AUTH_TOKEN_KEY = "mytv_auth_token";
const SERVER_FLAGS_KEY = "mytv_server_flags";

export interface ServerFlags {
  privateAccess: boolean;
  requireWebLogin: boolean;
}

export async function getAuthToken(): Promise<string | null> {
  return AsyncStorage.getItem(AUTH_TOKEN_KEY);
}

export async function setAuthToken(token: string): Promise<void> {
  await AsyncStorage.setItem(AUTH_TOKEN_KEY, token);
}

export async function clearAuthToken(): Promise<void> {
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
