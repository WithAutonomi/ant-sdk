import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { RestClient } from "./rest-client.js";
import { BadRequestError } from "./errors.js";
import type { DataPutResult, ManifestEntryInfo } from "./index.js";

// ---------------------------------------------------------------------------
// sha256 fields (antd 0.17.0 or later) over a mocked REST daemon.
// ---------------------------------------------------------------------------

const SHA = "ab".repeat(32);
const ADDR = "11".repeat(32);
const CA = "cc".repeat(32);
const DM = "9301abcd";
const HEADER_B64 = "wUFOVAE=";

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    statusText: status === 200 ? "OK" : "Error",
    headers: { "Content-Type": "application/json" },
  });
}

type Captured = { path: string; body: Record<string, unknown> | undefined };

/** Stub fetch with one canned response and record every request body. */
function stubFetch(status: number, body: unknown): Captured[] {
  const calls: Captured[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
      calls.push({
        path: url.pathname,
        body: typeof init?.body === "string" ? JSON.parse(init.body) : undefined,
      });
      return Promise.resolve(jsonResponse(status, body));
    }),
  );
  return calls;
}

/** Each upload call, with the response body the daemon sends minus sha256. */
const uploads: Array<{
  name: string;
  body: Record<string, unknown>;
  call: (c: RestClient) => Promise<{ sha256?: string | null }>;
}> = [
  {
    name: "dataPut (POST /v1/data)",
    body: { data_map: "dm", chunks_stored: 1, payment_mode_used: "single" },
    call: (c) => c.dataPut(Buffer.from("x")),
  },
  {
    name: "dataPutPublic (POST /v1/data/public)",
    body: { address: ADDR, chunks_stored: 1, payment_mode_used: "single" },
    call: (c) => c.dataPutPublic(Buffer.from("x")),
  },
  {
    name: "filePut (POST /v1/files)",
    body: {
      data_map: "dm",
      storage_cost_atto: "1",
      gas_cost_wei: "2",
      chunks_stored: 1,
      payment_mode_used: "single",
    },
    call: (c) => c.filePut("/tmp/f"),
  },
  {
    name: "filePutPublic (POST /v1/files/public)",
    body: {
      address: ADDR,
      storage_cost_atto: "1",
      gas_cost_wei: "2",
      chunks_stored: 1,
      payment_mode_used: "single",
    },
    call: (c) => c.filePutPublic("/tmp/f"),
  },
  {
    name: "finalizeUpload (POST /v1/upload/finalize)",
    body: { chunks_stored: 1 },
    call: (c) => c.finalizeUpload("u1", { q: "t" }),
  },
  {
    name: "finalizeMerkleUpload (POST /v1/upload/finalize)",
    body: { chunks_stored: 1 },
    call: (c) => c.finalizeMerkleUpload("u1", "pool"),
  },
];

describe("sha256", () => {
  it("is optional on the result types, so hand-built objects still compile", () => {
    const put: DataPutResult = { dataMap: "dm", chunksStored: 1, paymentModeUsed: "single" };
    const info: ManifestEntryInfo = {
      effectiveName: "a",
      path: null,
      size: null,
      kind: "public",
      contentAddress: CA,
      dataMap: null,
      exactSize: null,
      error: null,
    };
    expect(put.sha256).toBeUndefined();
    expect(info.sha256).toBeUndefined();
  });

  let client: RestClient;

  beforeEach(() => {
    client = new RestClient({ baseUrl: "http://localhost:8082" });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  describe("upload results", () => {
    for (const u of uploads) {
      describe(u.name, () => {
        it("reads sha256 when present, exactly as sent", async () => {
          stubFetch(200, { ...u.body, sha256: SHA });
          expect((await u.call(client)).sha256).toBe(SHA);
        });

        it("reads none when the key is absent (antd before 0.17.0)", async () => {
          stubFetch(200, u.body);
          expect((await u.call(client)).sha256).toBeNull();
        });

        it("reads none for an empty string or null", async () => {
          stubFetch(200, { ...u.body, sha256: "" });
          expect((await u.call(client)).sha256).toBeNull();
          stubFetch(200, { ...u.body, sha256: null });
          expect((await u.call(client)).sha256).toBeNull();
        });
      });
    }
  });

  describe("buildManifest() entry input", () => {
    const builtJson = { manifest: HEADER_B64, link: null, entries: [] };

    it("sends sha256 on an entry that sets it, exactly as given, and omits it otherwise", async () => {
      const calls = stubFetch(200, builtJson);
      await client.buildManifest([
        { path: "a.txt", dataMap: DM, sha256: "ABCDEF" },
        { path: "b.txt", address: ADDR },
        { path: "c.txt", address: ADDR, sha256: "" },
        { path: "d.txt", address: ADDR, sha256: undefined },
      ]);
      expect(calls).toHaveLength(1);
      expect(calls[0].body).toEqual({
        entries: [
          { path: "a.txt", data_map: DM, sha256: "ABCDEF" },
          { path: "b.txt", address: ADDR },
          { path: "c.txt", address: ADDR },
          { path: "d.txt", address: ADDR },
        ],
        embed_roots: true,
      });
      const entries = calls[0].body!.entries as Record<string, unknown>[];
      expect("sha256" in entries[1]).toBe(false);
      expect("sha256" in entries[2]).toBe(false);
      expect("sha256" in entries[3]).toBe(false);
    });

    it("passes a malformed sha256 through unchecked (the daemon validates)", async () => {
      const calls = stubFetch(200, builtJson);
      await client.buildManifest([{ address: ADDR, sha256: "zz" }]);
      expect(calls[0].body!.entries).toEqual([{ address: ADDR, sha256: "zz" }]);
    });

    it("maps the daemon's 400 for a bad sha256 to BadRequestError and keeps its message", async () => {
      const msg = "Bad request: 1 invalid entries: entries[0]: invalid hex sha256: Invalid character 'z' at position 0";
      stubFetch(400, { error: msg, code: "BAD_REQUEST" });
      const err = await client
        .buildManifest([{ address: ADDR, sha256: "zz" }])
        .then(
          () => {
            throw new Error("expected a rejection");
          },
          (e: unknown) => e,
        );
      expect(err).toBeInstanceOf(BadRequestError);
      expect((err as BadRequestError).statusCode).toBe(400);
      expect((err as Error).message).toBe(msg);
    });
  });

  describe("ManifestEntryInfo", () => {
    const entry = (extra: Record<string, unknown>) => ({
      effective_name: "a.txt",
      path: "a.txt",
      kind: "public",
      content_address: CA,
      ...extra,
    });

    it("reads sha256 from a build response and a decode response", async () => {
      stubFetch(200, { manifest: HEADER_B64, link: null, entries: [entry({ sha256: SHA })] });
      const built = await client.buildManifest([{ path: "a.txt", address: CA, sha256: SHA }]);
      expect(built.entries[0].sha256).toBe(SHA);

      stubFetch(200, { source: "manifest", entries: [entry({ sha256: SHA })] });
      const decoded = await client.decodeManifestLink("ant://manifest/wUFOVAE");
      expect(decoded.entries[0].sha256).toBe(SHA);
    });

    it("reads none when sha256 is absent, empty or null", async () => {
      stubFetch(200, {
        manifest: HEADER_B64,
        link: null,
        entries: [entry({}), entry({ sha256: "" }), entry({ sha256: null })],
      });
      const built = await client.buildManifest([{ path: "a.txt", address: CA }]);
      expect(built.entries.map((e) => e.sha256)).toEqual([null, null, null]);

      stubFetch(200, { source: "manifest", entries: [entry({}), entry({ sha256: "" })] });
      const decoded = await client.decodeManifest(Buffer.from([0xc1, 0x41, 0x4e, 0x54, 0x01]));
      expect(decoded.entries.map((e) => e.sha256)).toEqual([null, null]);
    });
  });
});
