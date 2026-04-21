import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { RestClient } from "./rest-client.js";
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
    respond: () => jsonResponse(200, { status: "ok", network: "local" }),
  },

  // Data public PUT
  {
    method: "POST",
    match: (p) => p === "/v1/data/public",
    respond: () => jsonResponse(200, { cost: "100", address: "0xabc" }),
  },

  // Data public GET
  {
    method: "GET",
    match: (p) => p.startsWith("/v1/data/public/"),
    respond: () => jsonResponse(200, { data: b64("hello world") }),
  },

  // Data private PUT
  {
    method: "POST",
    match: (p) => p === "/v1/data/private",
    respond: () => jsonResponse(200, { cost: "200", data_map: "0xdm" }),
  },

  // Data private GET
  {
    method: "GET",
    match: (p) => p === "/v1/data/private",
    respond: () => jsonResponse(200, { data: b64("secret data") }),
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

  // File upload public
  {
    method: "POST",
    match: (p) => p === "/v1/files/upload/public",
    respond: () =>
      jsonResponse(200, {
        address: "0xfile",
        storage_cost_atto: "1000",
        gas_cost_wei: "42",
        chunks_stored: 3,
        payment_mode_used: "auto",
      }),
  },

  // Dir upload public
  {
    method: "POST",
    match: (p) => p === "/v1/dirs/upload/public",
    respond: () =>
      jsonResponse(200, {
        address: "0xdir",
        storage_cost_atto: "2000",
        gas_cost_wei: "100",
        chunks_stored: 5,
        payment_mode_used: "merkle",
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
    it("returns ok: true and network name", async () => {
      const result = await client.health();
      expect(result).toEqual({ ok: true, network: "local" });
    });
  });

  // ---- Data public ----

  describe("dataPutPublic()", () => {
    it("returns PutResult with cost and address", async () => {
      const data = Buffer.from("test data");
      const result = await client.dataPutPublic(data);
      expect(result).toEqual({ cost: "100", address: "0xabc" });
    });

    it("sends base64-encoded data in the request body", async () => {
      const data = Buffer.from("test data");
      await client.dataPutPublic(data);

      const fetchFn = vi.mocked(fetch);
      const [, init] = fetchFn.mock.calls[0];
      const body = JSON.parse(init!.body as string);
      expect(body.data).toBe(data.toString("base64"));
    });

    it("includes payment_mode when provided", async () => {
      const data = Buffer.from("test data");
      await client.dataPutPublic(data, { paymentMode: "wallet" });

      const fetchFn = vi.mocked(fetch);
      const [, init] = fetchFn.mock.calls[0];
      const body = JSON.parse(init!.body as string);
      expect(body.payment_mode).toBe("wallet");
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

  describe("dataPutPrivate()", () => {
    it("returns PutResult with cost and data_map as address", async () => {
      const data = Buffer.from("private data");
      const result = await client.dataPutPrivate(data);
      expect(result).toEqual({ cost: "200", address: "0xdm" });
    });
  });

  describe("dataGetPrivate()", () => {
    it("returns decoded Buffer and passes data_map as query param", async () => {
      const result = await client.dataGetPrivate("0xdm");
      expect(result.toString()).toBe("secret data");

      const fetchFn = vi.mocked(fetch);
      const [url] = fetchFn.mock.calls[0];
      expect(url).toContain("data_map=0xdm");
    });
  });

  // ---- Data cost ----

  describe("dataCost()", () => {
    it("returns full breakdown", async () => {
      const data = Buffer.from("estimate me");
      const est = await client.dataCost(data);
      expect(est.cost).toBe("50");
      expect(est.fileSize).toBe(4);
      expect(est.chunkCount).toBe(3);
      expect(est.estimatedGasCostWei).toBe("150000000000000");
      expect(est.paymentMode).toBe("single");
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

  // ---- Files ----

  describe("fileUploadPublic()", () => {
    it("returns FileUploadResult with all five fields", async () => {
      const result = await client.fileUploadPublic("/tmp/foo.txt");
      expect(result).toEqual({
        address: "0xfile",
        storageCostAtto: "1000",
        gasCostWei: "42",
        chunksStored: 3,
        paymentModeUsed: "auto",
      });
    });
  });

  describe("dirUploadPublic()", () => {
    it("returns FileUploadResult with all five fields", async () => {
      const result = await client.dirUploadPublic("/tmp/mydir");
      expect(result).toEqual({
        address: "0xdir",
        storageCostAtto: "2000",
        gasCostWei: "100",
        chunksStored: 5,
        paymentModeUsed: "merkle",
      });
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
    });
  });

  describe("finalizeUpload()", () => {
    it("returns FinalizeUploadResult with address and chunksStored", async () => {
      const result = await client.finalizeUpload("uid-1", { "0xq1": "0xtx1" });
      expect(result).toEqual({ address: "0xfinal", chunksStored: 5 });
    });
  });

  describe("finalizeMerkleUpload()", () => {
    it("returns FinalizeUploadResult with address and chunksStored", async () => {
      const result = await client.finalizeMerkleUpload("uid-merkle", "0xpool1");
      expect(result).toEqual({ address: "0xfinal", chunksStored: 5 });
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

      // Use a short timeout client to trigger the timeout path
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
