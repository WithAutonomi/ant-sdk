import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { healthStatusFromJson, RestClient } from "./rest-client.js";
import { PaymentMode, isMetaFrame, isProgressFrame } from "./models.js";
import type { DownloadFrame } from "./models.js";
import {
  NotFoundError,
  BadRequestError,
  PaymentError,
  NetworkError,
  InternalError,
  TooLargeError,
  ServiceUnavailableError,
  AlreadyExistsError,
} from "./errors.js";

// ---------------------------------------------------------------------------
// Mock fetch helper
// ---------------------------------------------------------------------------

/** Build a minimal Response-like object that satisfies the fetch contract. */
function jsonResponse(status: number, body: unknown): Response {
  const bodyStr = JSON.stringify(body);
  return new Response(bodyStr, {
    status,
    statusText: status === 200 ? "OK" : "Error",
    headers: { "Content-Type": "application/json" },
  });
}

/** Build a raw-bytes streaming Response (octet-stream) for the *Stream methods. */
function streamResponse(status: number, body: string): Response {
  const bytes = new TextEncoder().encode(body);
  return new Response(bytes, {
    status,
    statusText: status === 200 ? "OK" : "Error",
    headers: {
      "Content-Type": "application/octet-stream",
      "Content-Length": String(bytes.byteLength),
    },
  });
}

/** Build an NDJSON streaming Response from already-serialized JSON lines. */
function ndjsonResponse(status: number, lines: string[]): Response {
  const body = lines.map((l) => l + "\n").join("");
  const bytes = new TextEncoder().encode(body);
  return new Response(bytes, {
    status,
    statusText: status === 200 ? "OK" : "Error",
    headers: { "Content-Type": "application/x-ndjson" },
  });
}

/** Drain a ReadableStream<Uint8Array> into a single concatenated string. */
async function drainStream(stream: ReadableStream<Uint8Array>): Promise<string> {
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (value) chunks.push(value);
  }
  const total = chunks.reduce((n, c) => n + c.byteLength, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) {
    out.set(c, off);
    off += c.byteLength;
  }
  return new TextDecoder().decode(out);
}

type Route = {
  method: string;
  match: (path: string) => boolean;
  respond: (url: URL) => Response;
};

const b64 = (s: string) => Buffer.from(s).toString("base64");

/**
 * Route table for the mock fetch. Each entry checks the HTTP method and URL
 * path then returns a canned Response.
 */
const routes: Route[] = [
  // Health
  {
    method: "GET",
    match: (p) => p === "/health",
    respond: () => jsonResponse(200, {
      status: "ok",
      network: "local",
      version: "0.4.0",
      evm_network: "local",
      uptime_seconds: 42,
      build_commit: "abcdef123456",
      payment_token_address: "0xtoken",
      payment_vault_address: "0xvault",
    }),
  },

  // Data public PUT
  {
    method: "POST",
    match: (p) => p === "/v1/data/public",
    respond: () =>
      jsonResponse(200, {
        address: "0xabc",
        chunks_stored: 3,
        payment_mode_used: "single",
      }),
  },

  // Data public STREAM (GET /v1/data/public/{addr}/stream) — must precede the
  // buffered public-get route below, which also matches the /stream path.
  {
    method: "GET",
    match: (p) => /^\/v1\/data\/public\/.+\/stream$/.test(p),
    respond: () => streamResponse(200, "streamed public"),
  },

  // Data public GET
  {
    method: "GET",
    match: (p) => p.startsWith("/v1/data/public/"),
    respond: () => jsonResponse(200, { data: b64("hello world") }),
  },

  // Data private PUT (new convention: POST /v1/data)
  {
    method: "POST",
    match: (p) => p === "/v1/data",
    respond: () =>
      jsonResponse(200, {
        data_map: "0xdm",
        chunks_stored: 2,
        payment_mode_used: "merkle",
      }),
  },

  // Data private GET (POST /v1/data/get with data_map in body)
  {
    method: "POST",
    match: (p) => p === "/v1/data/get",
    respond: () => jsonResponse(200, { data: b64("secret data") }),
  },

  // Data private STREAM (POST /v1/data/stream with data_map in body)
  {
    method: "POST",
    match: (p) => p === "/v1/data/stream",
    respond: () => streamResponse(200, "streamed secret"),
  },

  // Data cost
  {
    method: "POST",
    match: (p) => p === "/v1/data/cost",
    respond: () =>
      jsonResponse(200, {
        cost: "50",
        file_size: 4,
        chunk_count: 3,
        estimated_gas_cost_wei: "150000000000000",
        payment_mode: "single",
      }),
  },

  // Chunks PUT
  {
    method: "POST",
    match: (p) => p === "/v1/chunks",
    respond: () => jsonResponse(200, { cost: "10", address: "0xchunk" }),
  },

  // Chunks GET
  {
    method: "GET",
    match: (p) => p.startsWith("/v1/chunks/"),
    respond: () => jsonResponse(200, { data: b64("chunk bytes") }),
  },

  // File put public (renamed: was /v1/files/upload/public)
  {
    method: "POST",
    match: (p) => p === "/v1/files/public",
    respond: () =>
      jsonResponse(200, {
        address: "0xfile",
        storage_cost_atto: "1000",
        gas_cost_wei: "42",
        chunks_stored: 3,
        payment_mode_used: "auto",
      }),
  },

  // File get public (renamed: was /v1/files/download/public)
  {
    method: "POST",
    match: (p) => p === "/v1/files/public/get",
    respond: () => jsonResponse(200, {}),
  },

  // File put private (NEW)
  {
    method: "POST",
    match: (p) => p === "/v1/files",
    respond: () =>
      jsonResponse(200, {
        data_map: "0xfdm",
        storage_cost_atto: "900",
        gas_cost_wei: "42",
        chunks_stored: 2,
        payment_mode_used: "merkle",
      }),
  },

  // File get private (NEW)
  {
    method: "POST",
    match: (p) => p === "/v1/files/get",
    respond: () => jsonResponse(200, {}),
  },

  // File cost
  {
    method: "POST",
    match: (p) => p === "/v1/files/cost",
    respond: () =>
      jsonResponse(200, {
        cost: "1000",
        file_size: 4096,
        chunk_count: 3,
        estimated_gas_cost_wei: "150000000000000",
        payment_mode: "auto",
      }),
  },

  // Wallet address
  {
    method: "GET",
    match: (p) => p === "/v1/wallet/address",
    respond: () => jsonResponse(200, { address: "0xwallet" }),
  },

  // Wallet balance
  {
    method: "GET",
    match: (p) => p === "/v1/wallet/balance",
    respond: () => jsonResponse(200, { balance: "1000", gas_balance: "500" }),
  },

  // Wallet approve
  {
    method: "POST",
    match: (p) => p === "/v1/wallet/approve",
    respond: () => jsonResponse(200, { approved: true }),
  },

  // Prepare upload (file)
  {
    method: "POST",
    match: (p) => p === "/v1/upload/prepare",
    respond: () =>
      jsonResponse(200, {
        upload_id: "uid-1",
        payments: [
          { quote_hash: "0xq1", rewards_address: "0xr1", amount: "300" },
        ],
        total_amount: "300",
        payment_vault_address: "0xdp",
        payment_token_address: "0xpt",
        rpc_url: "http://rpc.local",
        total_chunks: 3,
        already_stored_count: 1,
      }),
  },

  // Prepare data upload
  {
    method: "POST",
    match: (p) => p === "/v1/data/prepare",
    respond: () =>
      jsonResponse(200, {
        upload_id: "uid-2",
        payments: [
          { quote_hash: "0xq2", rewards_address: "0xr2", amount: "150" },
        ],
        total_amount: "150",
        payment_vault_address: "0xdp2",
        payment_token_address: "0xpt2",
        rpc_url: "http://rpc2.local",
      }),
  },

  // Finalize upload
  {
    method: "POST",
    match: (p) => p === "/v1/upload/finalize",
    respond: () => jsonResponse(200, { address: "0xfinal", chunks_stored: 5 }),
  },
];

/** The mock fetch implementation that routes based on URL path and method. */
function mockFetch(input: string | URL | Request, init?: RequestInit): Promise<Response> {
  const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
  const method = (init?.method ?? "GET").toUpperCase();

  for (const route of routes) {
    if (route.method === method && route.match(url.pathname)) {
      return Promise.resolve(route.respond(url));
    }
  }

  // Unmatched routes return 404
  return Promise.resolve(jsonResponse(404, { error: "not found" }));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("RestClient", () => {
  let client: RestClient;

  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn(mockFetch));
    client = new RestClient({ baseUrl: "http://localhost:8082" });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  // ---- Health ----

  describe("health()", () => {
    it("returns ok, network, and all 6 diagnostic fields", async () => {
      const result = await client.health();
      expect(result).toEqual({
        ok: true,
        network: "local",
        version: "0.4.0",
        evmNetwork: "local",
        uptimeSeconds: 42,
        buildCommit: "abcdef123456",
        paymentTokenAddress: "0xtoken",
        paymentVaultAddress: "0xvault",
      });
    });

    it("defaults diagnostic fields to empty when talking to a pre-0.4.0 daemon", () => {
      const status = healthStatusFromJson({ status: "ok", network: "default" });
      expect(status.ok).toBe(true);
      expect(status.network).toBe("default");
      expect(status.version).toBe("");
      expect(status.evmNetwork).toBe("");
      expect(status.uptimeSeconds).toBe(0);
      expect(status.buildCommit).toBe("");
      expect(status.paymentTokenAddress).toBe("");
      expect(status.paymentVaultAddress).toBe("");
    });
  });

  // ---- PaymentMode ----

  describe("PaymentMode", () => {
    it("exposes the wire-format string literals the daemon accepts", () => {
      expect(PaymentMode.Auto).toBe("auto");
      expect(PaymentMode.Merkle).toBe("merkle");
      expect(PaymentMode.Single).toBe("single");
    });
  });

  // ---- Data public ----

  describe("dataPutPublic()", () => {
    it("returns DataPutPublicResult with address + chunksStored + paymentModeUsed", async () => {
      const data = Buffer.from("test data");
      const result = await client.dataPutPublic(data);
      expect(result).toEqual({
        address: "0xabc",
        chunksStored: 3,
        paymentModeUsed: "single",
      });
    });

    it("sends base64-encoded data + default payment_mode='auto'", async () => {
      const data = Buffer.from("test data");
      await client.dataPutPublic(data);

      const fetchFn = vi.mocked(fetch);
      const [, init] = fetchFn.mock.calls[0];
      const body = JSON.parse(init!.body as string);
      expect(body.data).toBe(data.toString("base64"));
      expect(body.payment_mode).toBe("auto");
    });

    it("forwards explicit paymentMode option", async () => {
      const data = Buffer.from("test data");
      await client.dataPutPublic(data, { paymentMode: PaymentMode.Merkle });

      const fetchFn = vi.mocked(fetch);
      const [, init] = fetchFn.mock.calls[0];
      const body = JSON.parse(init!.body as string);
      expect(body.payment_mode).toBe("merkle");
    });
  });

  describe("dataGetPublic()", () => {
    it("returns decoded Buffer", async () => {
      const result = await client.dataGetPublic("0xabc");
      expect(result.toString()).toBe("hello world");
    });

    it("fetches the correct URL path", async () => {
      await client.dataGetPublic("0xabc");

      const fetchFn = vi.mocked(fetch);
      const [url] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/v1/data/public/0xabc");
    });
  });

  // ---- Data private ----

  describe("dataPut()", () => {
    it("returns DataPutResult with dataMap + chunksStored + paymentModeUsed", async () => {
      const data = Buffer.from("private data");
      const result = await client.dataPut(data);
      expect(result).toEqual({
        dataMap: "0xdm",
        chunksStored: 2,
        paymentModeUsed: "merkle",
      });
    });

    it("hits POST /v1/data with payment_mode in body", async () => {
      const data = Buffer.from("x");
      await client.dataPut(data, { paymentMode: PaymentMode.Merkle });

      const fetchFn = vi.mocked(fetch);
      const [url, init] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/v1/data");
      const body = JSON.parse(init!.body as string);
      expect(body.payment_mode).toBe("merkle");
      expect(body.data).toBe(data.toString("base64"));
    });
  });

  describe("dataGet()", () => {
    it("POSTs data_map and returns decoded Buffer", async () => {
      const result = await client.dataGet("0xdm");
      expect(result.toString()).toBe("secret data");

      const fetchFn = vi.mocked(fetch);
      const [url, init] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/v1/data/get");
      const body = JSON.parse(init!.body as string);
      expect(body).toEqual({ data_map: "0xdm" });
    });
  });

  // ---- Data streaming ----

  describe("dataStream()", () => {
    it("POSTs data_map to /v1/data/stream and returns a readable byte stream", async () => {
      const stream = await client.dataStream("0xdm");
      const text = await drainStream(stream);
      expect(text).toBe("streamed secret");

      const fetchFn = vi.mocked(fetch);
      const [url, init] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/v1/data/stream");
      expect((init!.method ?? "GET").toUpperCase()).toBe("POST");
      const body = JSON.parse(init!.body as string);
      expect(body).toEqual({ data_map: "0xdm" });
    });

    it("throws the matching AntdError on a non-2xx error envelope", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() => Promise.resolve(jsonResponse(404, { error: "data map not found" }))),
      );
      await expect(client.dataStream("0xmissing")).rejects.toThrow(NotFoundError);
      await expect(client.dataStream("0xmissing")).rejects.toThrow("data map not found");
    });
  });

  describe("dataStreamPublic()", () => {
    it("GETs /v1/data/public/{addr}/stream and returns a readable byte stream", async () => {
      const stream = await client.dataStreamPublic("0xabc");
      const text = await drainStream(stream);
      expect(text).toBe("streamed public");

      const fetchFn = vi.mocked(fetch);
      const [url, init] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/v1/data/public/0xabc/stream");
      expect((init?.method ?? "GET").toUpperCase()).toBe("GET");
    });

    it("throws the matching AntdError on a non-2xx error envelope", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() => Promise.resolve(jsonResponse(400, { error: "invalid address" }))),
      );
      await expect(client.dataStreamPublic("bad")).rejects.toThrow(BadRequestError);
    });
  });

  describe("dataStreamWithProgress()", () => {
    it("opts into NDJSON, reassembles data, and surfaces progress frames", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn((_input: string | URL | Request, _init?: RequestInit) =>
          Promise.resolve(
            ndjsonResponse(200, [
              `{"type":"meta","total_size":6}`,
              `{"type":"progress","phase":"fetching","fetched":1,"total":2}`,
              `{"type":"data","chunk":"${b64("sec")}"}`,
              `{"type":"progress","phase":"fetching","fetched":2,"total":2}`,
              `{"type":"data","chunk":"${b64("ret")}"}`,
            ]),
          ),
        ),
      );

      const frames: DownloadFrame[] = [];
      for await (const frame of client.dataStreamWithProgress("0xdm")) {
        frames.push(frame);
      }

      // The byte-total meta frame is yielded first, before any data/progress.
      expect(isMetaFrame(frames[0])).toBe(true);
      const metas = frames.filter(isMetaFrame).map((f) => f.meta);
      expect(metas).toEqual([6]);

      // Two progress frames + two data frames.
      const progress = frames.filter(isProgressFrame).map((f) => f.progress);
      expect(progress).toEqual([
        { phase: "fetching", fetched: 1, total: 2 },
        { phase: "fetching", fetched: 2, total: 2 },
      ]);

      const data = frames.filter(
        (f): f is { data: Uint8Array } => f.data !== undefined,
      );
      const joined = data.map((f) => new TextDecoder().decode(f.data)).join("");
      expect(joined).toBe("secret");

      // Sent the NDJSON Accept header to POST /v1/data/stream.
      const fetchFn = vi.mocked(fetch);
      const [url, init] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/v1/data/stream");
      expect((init!.method ?? "GET").toUpperCase()).toBe("POST");
      expect((init!.headers as Record<string, string>).Accept).toBe("application/x-ndjson");
      expect(JSON.parse(init!.body as string)).toEqual({ data_map: "0xdm" });
    });

    it("buffers data frames split across network chunk boundaries", async () => {
      const line = `{"type":"data","chunk":"${b64("hello world")}"}\n`;
      const bytes = new TextEncoder().encode(line);
      const mid = Math.floor(bytes.byteLength / 2);
      const stream = new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(bytes.slice(0, mid));
          controller.enqueue(bytes.slice(mid));
          controller.close();
        },
      });
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(
            new Response(stream, {
              status: 200,
              statusText: "OK",
              headers: { "Content-Type": "application/x-ndjson" },
            }),
          ),
        ),
      );

      const frames: DownloadFrame[] = [];
      for await (const frame of client.dataStreamWithProgress("0xdm")) {
        frames.push(frame);
      }
      const data = frames.filter((f): f is { data: Uint8Array } => !isProgressFrame(f));
      expect(data.map((f) => new TextDecoder().decode(f.data)).join("")).toBe("hello world");
    });

    it("throws InternalError on a terminal error frame", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(
            ndjsonResponse(200, [
              `{"type":"data","chunk":"${b64("partial")}"}`,
              `{"type":"error","message":"chunk fetch failed"}`,
            ]),
          ),
        ),
      );

      await expect(async () => {
        for await (const _frame of client.dataStreamWithProgress("0xdm")) {
          // drain until the error frame throws
        }
      }).rejects.toThrow(InternalError);
    });
  });

  describe("dataStreamPublicWithProgress()", () => {
    it("GETs the public stream with the NDJSON Accept header and yields frames", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn((_input: string | URL | Request, _init?: RequestInit) =>
          Promise.resolve(
            ndjsonResponse(200, [
              `{"type":"meta","total_size":3}`,
              `{"type":"progress","phase":"resolving_map","fetched":0,"total":0}`,
              `{"type":"data","chunk":"${b64("pub")}"}`,
            ]),
          ),
        ),
      );

      const frames: DownloadFrame[] = [];
      for await (const frame of client.dataStreamPublicWithProgress("0xabc")) {
        frames.push(frame);
      }
      // Byte-total meta frame is yielded first.
      expect(isMetaFrame(frames[0])).toBe(true);
      expect(frames.filter(isMetaFrame).map((f) => f.meta)).toEqual([3]);

      const data = frames.filter(
        (f): f is { data: Uint8Array } => f.data !== undefined,
      );
      expect(data.map((f) => new TextDecoder().decode(f.data)).join("")).toBe("pub");
      expect(frames.filter(isProgressFrame)).toHaveLength(1);

      const fetchFn = vi.mocked(fetch);
      const [url, init] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/v1/data/public/0xabc/stream");
      expect((init?.method ?? "GET").toUpperCase()).toBe("GET");
      expect((init!.headers as Record<string, string>).Accept).toBe("application/x-ndjson");
    });
  });

  // ---- Data cost ----

  describe("dataCost()", () => {
    it("returns full breakdown and forwards payment_mode", async () => {
      const data = Buffer.from("estimate me");
      const est = await client.dataCost(data, { paymentMode: PaymentMode.Single });
      expect(est.cost).toBe("50");
      expect(est.fileSize).toBe(4);
      expect(est.chunkCount).toBe(3);
      expect(est.estimatedGasCostWei).toBe("150000000000000");
      expect(est.paymentMode).toBe("single");

      const fetchFn = vi.mocked(fetch);
      const [, init] = fetchFn.mock.calls[0];
      const body = JSON.parse(init!.body as string);
      expect(body.payment_mode).toBe("single");
    });

    it("defaults payment_mode to auto when omitted", async () => {
      await client.dataCost(Buffer.from("x"));
      const fetchFn = vi.mocked(fetch);
      const [, init] = fetchFn.mock.calls[0];
      const body = JSON.parse(init!.body as string);
      expect(body.payment_mode).toBe("auto");
    });
  });

  // ---- Chunks ----

  describe("chunkPut()", () => {
    it("returns PutResult", async () => {
      const data = Buffer.from("chunk data");
      const result = await client.chunkPut(data);
      expect(result).toEqual({ cost: "10", address: "0xchunk" });
    });
  });

  describe("chunkGet()", () => {
    it("returns decoded Buffer", async () => {
      const result = await client.chunkGet("0xchunk");
      expect(result.toString()).toBe("chunk bytes");
    });
  });

  // ---- Files public ----

  describe("filePutPublic()", () => {
    it("returns FilePutPublicResult with all five fields", async () => {
      const result = await client.filePutPublic("/tmp/foo.txt");
      expect(result).toEqual({
        address: "0xfile",
        storageCostAtto: "1000",
        gasCostWei: "42",
        chunksStored: 3,
        paymentModeUsed: "auto",
      });
    });

    it("hits POST /v1/files/public with payment_mode in body", async () => {
      await client.filePutPublic("/tmp/foo.txt", { paymentMode: PaymentMode.Single });

      const fetchFn = vi.mocked(fetch);
      const [url, init] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/v1/files/public");
      const body = JSON.parse(init!.body as string);
      expect(body).toEqual({ path: "/tmp/foo.txt", payment_mode: "single" });
    });
  });

  describe("fileGetPublic()", () => {
    it("POSTs address + dest_path to /v1/files/public/get", async () => {
      await client.fileGetPublic("0xfile", "/tmp/out.txt");

      const fetchFn = vi.mocked(fetch);
      const [url, init] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/v1/files/public/get");
      const body = JSON.parse(init!.body as string);
      expect(body).toEqual({ address: "0xfile", dest_path: "/tmp/out.txt" });
    });
  });

  // ---- Files private ----

  describe("filePut()", () => {
    it("returns FilePutResult and hits POST /v1/files with payment_mode", async () => {
      const result = await client.filePut("/tmp/secret.txt", { paymentMode: PaymentMode.Merkle });
      expect(result).toEqual({
        dataMap: "0xfdm",
        storageCostAtto: "900",
        gasCostWei: "42",
        chunksStored: 2,
        paymentModeUsed: "merkle",
      });

      const fetchFn = vi.mocked(fetch);
      const [url, init] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/v1/files");
      const body = JSON.parse(init!.body as string);
      expect(body).toEqual({ path: "/tmp/secret.txt", payment_mode: "merkle" });
    });
  });

  describe("fileGet()", () => {
    it("POSTs data_map + dest_path to /v1/files/get", async () => {
      await client.fileGet("0xfdm", "/tmp/priv-out.txt");

      const fetchFn = vi.mocked(fetch);
      const [url, init] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/v1/files/get");
      const body = JSON.parse(init!.body as string);
      expect(body).toEqual({ data_map: "0xfdm", dest_path: "/tmp/priv-out.txt" });
    });
  });

  // ---- File cost ----

  describe("fileCost()", () => {
    it("returns full breakdown and forwards payment_mode + is_public", async () => {
      const est = await client.fileCost("/tmp/x.bin", true, { paymentMode: PaymentMode.Single });
      expect(est.cost).toBe("1000");
      expect(est.fileSize).toBe(4096);
      expect(est.chunkCount).toBe(3);

      const fetchFn = vi.mocked(fetch);
      const [, init] = fetchFn.mock.calls[0];
      const body = JSON.parse(init!.body as string);
      expect(body).toEqual({ path: "/tmp/x.bin", is_public: true, payment_mode: "single" });
    });
  });

  // ---- Wallet ----

  describe("walletAddress()", () => {
    it("returns wallet address", async () => {
      const result = await client.walletAddress();
      expect(result).toEqual({ address: "0xwallet" });
    });
  });

  describe("walletBalance()", () => {
    it("returns balance and gasBalance", async () => {
      const result = await client.walletBalance();
      expect(result).toEqual({ balance: "1000", gasBalance: "500" });
    });
  });

  describe("walletApprove()", () => {
    it("returns true when approved", async () => {
      const result = await client.walletApprove();
      expect(result).toBe(true);
    });
  });

  // ---- External Signer (Two-Phase Upload) ----

  describe("prepareUpload()", () => {
    it("returns PrepareUploadResult with camelCase fields", async () => {
      const result = await client.prepareUpload("/some/file.txt");
      expect(result).toEqual({
        uploadId: "uid-1",
        payments: [
          { quoteHash: "0xq1", rewardsAddress: "0xr1", amount: "300" },
        ],
        totalAmount: "300",
        paymentVaultAddress: "0xdp",
        paymentTokenAddress: "0xpt",
        rpcUrl: "http://rpc.local",
        paymentType: "wave_batch",
        totalChunks: 3,
        alreadyStoredCount: 1,
      });
    });

    it("defaults paymentType to wave_batch when not in response", async () => {
      const result = await client.prepareUpload("/some/file.txt");
      expect(result.paymentType).toBe("wave_batch");
      expect(result.depth).toBeUndefined();
      expect(result.poolCommitments).toBeUndefined();
      expect(result.merklePaymentTimestamp).toBeUndefined();
      expect(result.paymentVaultAddress).toBeDefined();
    });

    it("parses merkle response fields", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(
            jsonResponse(200, {
              upload_id: "uid-merkle",
              payments: [],
              total_amount: "500",
              payment_vault_address: "0xmerkle",
              payment_token_address: "0xpt",
              rpc_url: "http://rpc.local",
              payment_type: "merkle",
              depth: 3,
              pool_commitments: [
                {
                  pool_hash: "0xpool1",
                  candidates: [
                    { rewards_address: "0xnode1", amount: "200" },
                    { rewards_address: "0xnode2", amount: "300" },
                  ],
                },
              ],
              merkle_payment_timestamp: 1700000000,
            }),
          ),
        ),
      );

      const result = await client.prepareUpload("/some/file.txt");
      expect(result.paymentType).toBe("merkle");
      expect(result.depth).toBe(3);
      expect(result.merklePaymentTimestamp).toBe(1700000000);
      expect(result.paymentVaultAddress).toBe("0xmerkle");
      expect(result.poolCommitments).toEqual([
        {
          poolHash: "0xpool1",
          candidates: [
            { rewardsAddress: "0xnode1", amount: "200" },
            { rewardsAddress: "0xnode2", amount: "300" },
          ],
        },
      ]);
    });
  });

  describe("prepareDataUpload()", () => {
    it("returns PrepareUploadResult for raw data", async () => {
      const result = await client.prepareDataUpload(Buffer.from("upload me"));
      expect(result.uploadId).toBe("uid-2");
      expect(result.totalAmount).toBe("150");
      expect(result.payments).toHaveLength(1);
      expect(result.payments[0].quoteHash).toBe("0xq2");
      expect(result.paymentType).toBe("wave_batch");
      // preflight fields absent in this response default to 0
      expect(result.totalChunks).toBe(0);
      expect(result.alreadyStoredCount).toBe(0);
    });
  });

  describe("finalizeUpload()", () => {
    it("returns FinalizeUploadResult with address, chunksStored, dataMap, dataMapAddress", async () => {
      const result = await client.finalizeUpload("uid-1", { "0xq1": "0xtx1" });
      expect(result).toEqual({
        address: "0xfinal",
        chunksStored: 5,
        dataMap: "",
        dataMapAddress: "",
      });
    });
  });

  describe("finalizeMerkleUpload()", () => {
    it("returns FinalizeUploadResult with address, chunksStored, dataMap, dataMapAddress", async () => {
      const result = await client.finalizeMerkleUpload("uid-merkle", "0xpool1");
      expect(result).toEqual({
        address: "0xfinal",
        chunksStored: 5,
        dataMap: "",
        dataMapAddress: "",
      });
    });

    it("sends correct request body with winner_pool_hash", async () => {
      await client.finalizeMerkleUpload("uid-merkle", "0xpool1");

      const fetchFn = vi.mocked(fetch);
      const [, init] = fetchFn.mock.calls[0];
      const body = JSON.parse(init!.body as string);
      expect(body).toEqual({
        upload_id: "uid-merkle",
        winner_pool_hash: "0xpool1",
        store_data_map: false,
      });
    });

    it("passes store_data_map when true", async () => {
      await client.finalizeMerkleUpload("uid-merkle", "0xpool1", true);

      const fetchFn = vi.mocked(fetch);
      const [, init] = fetchFn.mock.calls[0];
      const body = JSON.parse(init!.body as string);
      expect(body.store_data_map).toBe(true);
    });
  });

  // ---- Public-prepare visibility forwarding ----

  describe("prepareUpload() visibility forwarding", () => {
    it("forwards visibility:'public' to the daemon when provided", async () => {
      await client.prepareUpload("/some/file.txt", { visibility: "public" });

      const fetchFn = vi.mocked(fetch);
      const [, init] = fetchFn.mock.calls[0];
      const body = JSON.parse(init!.body as string);
      expect(body).toEqual({ path: "/some/file.txt", visibility: "public" });
    });

    it("omits visibility entirely when not provided (private-only behaviour)", async () => {
      await client.prepareUpload("/some/file.txt");

      const fetchFn = vi.mocked(fetch);
      const [, init] = fetchFn.mock.calls[0];
      const body = JSON.parse(init!.body as string);
      expect(body).toEqual({ path: "/some/file.txt" });
      expect("visibility" in body).toBe(false);
    });
  });

  describe("prepareUploadPublic()", () => {
    it("sends visibility:'public' and path", async () => {
      let capturedBody: Record<string, unknown> | undefined;
      vi.stubGlobal(
        "fetch",
        vi.fn((_input: string | URL | Request, init?: RequestInit) => {
          capturedBody = JSON.parse(init!.body as string);
          return Promise.resolve(
            jsonResponse(200, {
              upload_id: "up-pub-1",
              payments: [
                { quote_hash: "0xq1", rewards_address: "0xr1", amount: "100" },
              ],
              total_amount: "100",
              payment_vault_address: "0xdp",
              payment_token_address: "0xpt",
              rpc_url: "http://rpc.local",
              payment_type: "wave_batch",
            }),
          );
        }),
      );

      const result = await client.prepareUploadPublic("/tmp/file.txt");
      expect(capturedBody).toEqual({ path: "/tmp/file.txt", visibility: "public" });
      expect(result.uploadId).toBe("up-pub-1");
      expect(result.paymentType).toBe("wave_batch");
    });
  });

  describe("finalizeUpload() data_map_address surfacing", () => {
    it("surfaces dataMapAddress when the daemon returns it (visibility=public path)", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(
            jsonResponse(200, {
              data_map: "deadbeef",
              data_map_address: "cafebabe",
              chunks_stored: 4,
            }),
          ),
        ),
      );

      const result = await client.finalizeUpload("up1", { "0xq1": "0xtx1" });
      expect(result).toEqual({
        address: "",
        chunksStored: 4,
        dataMap: "deadbeef",
        dataMapAddress: "cafebabe",
      });
    });

    it("defaults dataMapAddress to '' on older daemons that omit it", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(
            jsonResponse(200, {
              data_map: "deadbeef",
              chunks_stored: 2,
            }),
          ),
        ),
      );

      const result = await client.finalizeUpload("up1", { "0xq1": "0xtx1" });
      expect(result.dataMapAddress).toBe("");
      expect(result.dataMap).toBe("deadbeef");
      expect(result.chunksStored).toBe(2);
    });
  });

  // ---- Single-chunk external signer ----

  describe("prepareChunkUpload()", () => {
    it("base64-encodes the payload and parses the wave-batch response", async () => {
      let capturedBody: Record<string, unknown> | undefined;
      vi.stubGlobal(
        "fetch",
        vi.fn((_input: string | URL | Request, init?: RequestInit) => {
          capturedBody = JSON.parse(init!.body as string);
          return Promise.resolve(
            jsonResponse(200, {
              address: "aa" + "00".repeat(31),
              already_stored: false,
              upload_id: "chunk-1",
              payment_type: "wave_batch",
              payments: [
                { quote_hash: "qh1", rewards_address: "ra1", amount: "100" },
                { quote_hash: "qh2", rewards_address: "ra2", amount: "100" },
              ],
              total_amount: "200",
              payment_vault_address: "0xvault",
              payment_token_address: "0xtoken",
              rpc_url: "http://localhost:8545",
            }),
          );
        }),
      );

      const result = await client.prepareChunkUpload(Buffer.from("hello"));

      expect(capturedBody!.data).toBe("aGVsbG8=");
      expect(result.alreadyStored).toBe(false);
      expect(result.uploadId).toBe("chunk-1");
      expect(result.paymentType).toBe("wave_batch");
      expect(result.payments).toHaveLength(2);
      expect(result.payments[0]).toEqual({
        quoteHash: "qh1",
        rewardsAddress: "ra1",
        amount: "100",
      });
      expect(result.totalAmount).toBe("200");
      expect(result.paymentVaultAddress).toBe("0xvault");
      expect(result.paymentTokenAddress).toBe("0xtoken");
      expect(result.rpcUrl).toBe("http://localhost:8545");
      expect(result.address).toBe("aa" + "00".repeat(31));
    });

    it("returns alreadyStored=true with empty payment fields when chunk already on-network", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(
            jsonResponse(200, {
              address: "bb" + "11".repeat(31),
              already_stored: true,
            }),
          ),
        ),
      );

      const result = await client.prepareChunkUpload(Buffer.from("already-on-network"));
      expect(result.alreadyStored).toBe(true);
      expect(result.address).toBe("bb" + "11".repeat(31));
      expect(result.uploadId).toBe("");
      expect(result.payments).toEqual([]);
      expect(result.paymentType).toBe("");
      expect(result.totalAmount).toBe("");
      expect(result.paymentVaultAddress).toBe("");
      expect(result.paymentTokenAddress).toBe("");
      expect(result.rpcUrl).toBe("");
    });

    it("accepts a Uint8Array argument (browser-friendly)", async () => {
      let capturedBody: Record<string, unknown> | undefined;
      vi.stubGlobal(
        "fetch",
        vi.fn((_input: string | URL | Request, init?: RequestInit) => {
          capturedBody = JSON.parse(init!.body as string);
          return Promise.resolve(
            jsonResponse(200, {
              address: "cc" + "22".repeat(31),
              already_stored: true,
            }),
          );
        }),
      );

      const bytes = new Uint8Array([104, 105]); // "hi"
      await client.prepareChunkUpload(bytes);
      expect(capturedBody!.data).toBe("aGk=");
    });
  });

  describe("finalizeChunkUpload()", () => {
    it("sends upload_id + tx_hashes and returns the address string", async () => {
      let capturedBody: Record<string, unknown> | undefined;
      vi.stubGlobal(
        "fetch",
        vi.fn((_input: string | URL | Request, init?: RequestInit) => {
          capturedBody = JSON.parse(init!.body as string);
          return Promise.resolve(
            jsonResponse(200, { address: "cc" + "22".repeat(31) }),
          );
        }),
      );

      const addr = await client.finalizeChunkUpload("chunk-1", {
        qh1: "tx1",
        qh2: "tx2",
      });
      expect(capturedBody).toEqual({
        upload_id: "chunk-1",
        tx_hashes: { qh1: "tx1", qh2: "tx2" },
      });
      expect(addr).toBe("cc" + "22".repeat(31));
      expect(addr).toHaveLength(64);
    });
  });

  // ---- Error handling ----

  describe("error handling", () => {
    it("throws NotFoundError on 404", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(jsonResponse(404, { error: "chunk not found" })),
        ),
      );

      await expect(client.dataGetPublic("0xnone")).rejects.toThrow(NotFoundError);
    });

    it("throws BadRequestError on 400", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(jsonResponse(400, { error: "invalid address" })),
        ),
      );

      await expect(client.dataGetPublic("bad")).rejects.toThrow(BadRequestError);
    });

    it("throws PaymentError on 402", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(jsonResponse(402, { error: "insufficient funds" })),
        ),
      );

      await expect(client.dataPutPublic(Buffer.from("x"))).rejects.toThrow(PaymentError);
    });

    it("throws AlreadyExistsError on 409", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(jsonResponse(409, { error: "already exists" })),
        ),
      );

      await expect(client.chunkPut(Buffer.from("dup"))).rejects.toThrow(AlreadyExistsError);
    });

    it("throws TooLargeError on 413", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(jsonResponse(413, { error: "payload too large" })),
        ),
      );

      await expect(client.dataPutPublic(Buffer.from("huge"))).rejects.toThrow(TooLargeError);
    });

    it("throws InternalError on 500", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(jsonResponse(500, { error: "internal error" })),
        ),
      );

      await expect(client.health()).rejects.toThrow(InternalError);
    });

    it("throws ServiceUnavailableError on 503", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(jsonResponse(503, { error: "no wallet" })),
        ),
      );

      await expect(client.walletBalance()).rejects.toThrow(ServiceUnavailableError);
    });

    it("preserves error message from response body", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(jsonResponse(404, { error: "chunk 0xabc not found" })),
        ),
      );

      await expect(client.dataGetPublic("0xabc")).rejects.toThrow("chunk 0xabc not found");
    });

    it("falls back to statusText when body has no error field", async () => {
      const resp = new Response("{}", {
        status: 404,
        statusText: "Not Found",
        headers: { "Content-Type": "application/json" },
      });
      vi.stubGlobal("fetch", vi.fn(() => Promise.resolve(resp)));

      await expect(client.dataGetPublic("0x1")).rejects.toThrow(NotFoundError);
    });
  });

  // ---- Network errors ----

  describe("network errors", () => {
    it("throws NetworkError when fetch rejects", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() => Promise.reject(new TypeError("Failed to fetch"))),
      );

      await expect(client.health()).rejects.toThrow(NetworkError);
    });

    it("includes the original error message", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() => Promise.reject(new TypeError("Failed to fetch"))),
      );

      await expect(client.health()).rejects.toThrow("Failed to fetch");
    });

    it("throws NetworkError on abort/timeout", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(() => {
          const err = new DOMException("The operation was aborted", "AbortError");
          return Promise.reject(err);
        }),
      );

      const timeoutClient = new RestClient({ baseUrl: "http://localhost:8082", timeout: 100 });
      await expect(timeoutClient.health()).rejects.toThrow(NetworkError);
    });
  });

  // ---- Constructor / options ----

  describe("constructor options", () => {
    it("strips trailing slashes from baseUrl", async () => {
      const c = new RestClient({ baseUrl: "http://localhost:8082///" });
      await c.health();

      const fetchFn = vi.mocked(fetch);
      const [url] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/health");
    });

    it("defaults baseUrl to http://localhost:8082", async () => {
      const c = new RestClient();
      await c.health();

      const fetchFn = vi.mocked(fetch);
      const [url] = fetchFn.mock.calls[0];
      expect(url).toBe("http://localhost:8082/health");
    });
  });
});
