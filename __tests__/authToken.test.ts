jest.mock("@react-native-async-storage/async-storage", () =>
  require("@react-native-async-storage/async-storage/jest/async-storage-mock")
);

import {
  getAuthToken,
  setAuthToken,
  clearAuthToken,
  getServerFlags,
  setServerFlags,
} from "../services/authToken";

describe("authToken", () => {
  beforeEach(async () => {
    await clearAuthToken();
    await setServerFlags({ privateAccess: false, requireWebLogin: false });
  });

  it("set → get → clear 往返", async () => {
    expect(await getAuthToken()).toBeNull();
    await setAuthToken("jwt-abc");
    expect(await getAuthToken()).toBe("jwt-abc");
    await clearAuthToken();
    expect(await getAuthToken()).toBeNull();
  });

  it("serverFlags 往返", async () => {
    await setServerFlags({ privateAccess: true, requireWebLogin: false });
    expect(await getServerFlags()).toEqual({
      privateAccess: true,
      requireWebLogin: false,
    });
  });
});
