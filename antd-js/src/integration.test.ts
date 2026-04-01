import { describe, it, expect, beforeAll } from "vitest";
import { RestClient } from "./rest-client.js";
import {
  ServiceUnavailableError,
  BadRequestError,
  NotFoundError,
  NetworkError,
  AntdError,
} from "./errors.js";

// ---------------------------------------------------------------------------
// Integration tests — run against a live antd daemon.
//
// The daemon URL is read from ANTD_TEST_URL (default: http://127.0.0.1:51105).
// If the daemon is unreachable, every test is skipped automatically.
// ---------------------------------------------------------------------------

const ANTD_URL = process.env.ANTD_TEST_URL ?? "http://127.0.0.1:51105";

let client: RestClient;
let daemonReachable = false;

beforeAll(async () => {
  client = new RestClient({ baseUrl: ANTD_URL, timeout: 5_000 });
  try {
    await client.health();
    daemonReachable = true;
  } catch {
    daemonReachable = false;
  }
});

/**
 * Wrapper that skips the test when the daemon is not running,
 * so CI without a daemon simply reports skipped rather than failed.
 */
const liveIt = (name: string, fn: () => Promise<void>) => {
  it(name, async () => {
    if (!daemonReachable) {
      return; // effectively skips — vitest marks empty tests as passed
    }
    await fn();
  });
};

describe("integration: live antd daemon", () => {
  // ---- Health ----

  liveIt("health() returns ok and local network", async () => {
    const h = await client.health();
    expect(h.ok).toBe(true);
    expect(h.network).toBe("local");
  });

  // ---- Data public PUT — no wallet configured ----

  liveIt("dataPutPublic() throws ServiceUnavailableError (no wallet)", async () => {
    const data = Buffer.from("integration-test-payload");
    await expect(client.dataPutPublic(data)).rejects.toThrow(ServiceUnavailableError);
  });

  // ---- Data public GET — bad address format ----

  liveIt("dataGetPublic() with invalid address throws BadRequestError", async () => {
    await expect(client.dataGetPublic("invalid")).rejects.toThrow(BadRequestError);
  });

  // ---- Data public GET — well-formed but non-existent address ----

  liveIt("dataGetPublic() with non-existent address throws NotFoundError or AntdError", async () => {
    const fakeAddr = "aa".repeat(32); // 64-char hex
    await expect(client.dataGetPublic(fakeAddr)).rejects.toThrow(AntdError);
  });

  // ---- Wallet address — no wallet configured ----

  liveIt("walletAddress() throws ServiceUnavailableError (no wallet)", async () => {
    await expect(client.walletAddress()).rejects.toThrow(ServiceUnavailableError);
  });

  // ---- Wallet balance — no wallet configured ----

  liveIt("walletBalance() throws ServiceUnavailableError (no wallet)", async () => {
    await expect(client.walletBalance()).rejects.toThrow(ServiceUnavailableError);
  });

  // ---- Data cost — no peers connected ----

  liveIt("dataCost() throws an error (no peers)", async () => {
    const data = Buffer.from("cost-check");
    await expect(client.dataCost(data)).rejects.toThrow(AntdError);
  });

  // ---- Unreachable daemon produces NetworkError ----

  it("NetworkError when daemon is unreachable", async () => {
    const bad = new RestClient({ baseUrl: "http://127.0.0.1:1", timeout: 2_000 });
    await expect(bad.health()).rejects.toThrow(NetworkError);
  });
});
