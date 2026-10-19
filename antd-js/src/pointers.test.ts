import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { RestClient } from "./rest-client.js";
import { POINTER_FINAL_COUNTER, PointerKind } from "./models.js";
import {
  AlreadyExistsError,
  AntdError,
  BadRequestError,
  CloseGroupShortfallError,
  ConflictError,
  ForkError,
  InternalError,
  NotFoundError,
  PointerFinalError,
  ServiceUnavailableError,
  fromErrorBody,
} from "./errors.js";

// ---------------------------------------------------------------------------
// Pointer API over a mocked REST daemon.
// ---------------------------------------------------------------------------

const A = "aa".repeat(32);
const B = "bb".repeat(32);
const T1 = "11".repeat(32);
const T2 = "22".repeat(32);
const SID = "5e".repeat(32);
const OWNER_PK = "ab".repeat(1952);
const U64_MAX = "18446744073709551615";

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    statusText: status === 200 ? "OK" : "Error",
    headers: { "Content-Type": "application/json" },
  });
}

type Captured = { method: string; path: string; body: Record<string, unknown> | undefined };

/**
 * Stub fetch with a single canned response and record every request, so a
 * test can check the method, path and JSON body the client sent (and how many
 * times it sent it).
 */
function stubFetch(status: number, body: unknown): Captured[] {
  const calls: Captured[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
      calls.push({
        method: (init?.method ?? "GET").toUpperCase(),
        path: url.pathname,
        body: typeof init?.body === "string" ? JSON.parse(init.body) : undefined,
      });
      return Promise.resolve(jsonResponse(status, body));
    }),
  );
  return calls;
}

/** Await a promise expected to reject and return the rejection. */
async function rejection(p: Promise<unknown>): Promise<unknown> {
  return p.then(
    () => {
      throw new Error("expected a rejection");
    },
    (e: unknown) => e,
  );
}

const finalState = {
  state_id: SID,
  kind: "pointer",
  kind_tag: 1,
  target: B,
  holders: 5,
  transferred_to: B,
};

const finalFinality = {
  address: A,
  group: 5,
  answered: 5,
  status: "final",
  counter: null,
  state: finalState,
  states: [],
  majority: null,
  transferred_to: B,
};

describe("RestClient pointers", () => {
  let client: RestClient;

  beforeEach(() => {
    client = new RestClient({ baseUrl: "http://localhost:8082" });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  describe("pointerKeys()", () => {
    it("GETs /v1/pointers/keys and returns the addresses", async () => {
      const calls = stubFetch(200, { keys: [{ address: A }, { address: B }] });
      expect(await client.pointerKeys()).toEqual([A, B]);
      expect(calls).toEqual([{ method: "GET", path: "/v1/pointers/keys", body: undefined }]);
    });

    it("returns [] when the daemon holds no keys", async () => {
      stubFetch(200, { keys: [] });
      expect(await client.pointerKeys()).toEqual([]);
    });
  });

  describe("pointerCreate()", () => {
    it("POSTs owner + target, omits kind when not given, and parses the counter as bigint", async () => {
      const calls = stubFetch(200, { address: A, state_id: SID, counter: "0" });
      const w = await client.pointerCreate(A, T1);
      expect(w).toEqual({ address: A, stateId: SID, counter: 0n });
      expect(typeof w.counter).toBe("bigint");
      expect(calls).toEqual([
        { method: "POST", path: "/v1/pointers", body: { owner: A, target: T1 } },
      ]);
    });

    it("forwards an explicit kind", async () => {
      const calls = stubFetch(200, { address: A, state_id: SID, counter: "0" });
      await client.pointerCreate(A, B, PointerKind.Pointer);
      expect(calls[0].body).toEqual({ owner: A, target: B, kind: "pointer" });
    });

    it("keeps ALREADY_EXISTS as AlreadyExistsError", async () => {
      stubFetch(409, { error: "Already exists: pointer", code: "ALREADY_EXISTS" });
      const err = await rejection(client.pointerCreate(A, T1));
      expect(err).toBeInstanceOf(AlreadyExistsError);
    });
  });

  describe("pointerUpdate()", () => {
    it("POSTs to /v1/pointers/update and returns the new counter", async () => {
      const calls = stubFetch(200, { address: A, state_id: SID, counter: "1" });
      const w = await client.pointerUpdate(A, T2, PointerKind.Chunk);
      expect(w.counter).toBe(1n);
      expect(calls).toEqual([
        {
          method: "POST",
          path: "/v1/pointers/update",
          body: { owner: A, target: T2, kind: "chunk" },
        },
      ]);
    });

    it("throws PointerFinalError (not AlreadyExistsError) on POINTER_FINAL", async () => {
      stubFetch(409, { error: "Pointer is final: transferred", code: "POINTER_FINAL" });
      const err = await rejection(client.pointerUpdate(A, T1));
      expect(err).toBeInstanceOf(PointerFinalError);
      expect(err).not.toBeInstanceOf(AlreadyExistsError);
      expect((err as AntdError).statusCode).toBe(409);
      expect((err as AntdError).message).toBe("Pointer is final: transferred");
    });

    it("throws ConflictError while a prepared write is pending", async () => {
      stubFetch(409, { error: "Conflict: pending prepare", code: "CONFLICT" });
      const err = await rejection(client.pointerUpdate(A, T1));
      expect(err).toBeInstanceOf(ConflictError);
      expect(err).not.toBeInstanceOf(AlreadyExistsError);
    });

    it("throws BadRequestError for an owner the daemon holds no key for", async () => {
      stubFetch(400, { error: "Bad request: no key for owner", code: "BAD_REQUEST" });
      await expect(client.pointerUpdate(B, T1)).rejects.toThrow(BadRequestError);
    });

    it("sends a paid write exactly once, even when it fails", async () => {
      const calls = stubFetch(503, {
        error: "Close group shortfall: stored on 3 of 5",
        code: "CLOSE_GROUP_SHORTFALL",
      });
      await expect(client.pointerUpdate(A, T1)).rejects.toThrow(CloseGroupShortfallError);
      expect(calls).toHaveLength(1);
    });
  });

  describe("pointerTransfer()", () => {
    it("POSTs owner + recipient and parses the close group's finality", async () => {
      const calls = stubFetch(200, { address: A, state_id: SID, finality: finalFinality });
      const t = await client.pointerTransfer(A, B);
      expect(calls).toEqual([
        { method: "POST", path: "/v1/pointers/transfer", body: { owner: A, recipient: B } },
      ]);
      expect(t.address).toBe(A);
      expect(t.stateId).toBe(SID);
      expect(t.finalityError).toBeNull();
      expect(t.finality).toEqual({
        address: A,
        group: 5,
        answered: 5,
        status: "final",
        rawStatus: "final",
        counter: null,
        state: {
          stateId: SID,
          kind: "pointer",
          kindTag: 1,
          target: B,
          holders: 5,
          transferredTo: B,
        },
        states: [],
        majority: null,
        transferredTo: B,
      });
    });

    it("surfaces a failed finality check as null + finalityError", async () => {
      stubFetch(200, {
        address: A,
        state_id: SID,
        finality: null,
        finality_error: "only 3 of 5 answered",
      });
      const t = await client.pointerTransfer(A, B);
      expect(t.finality).toBeNull();
      expect(t.finalityError).toBe("only 3 of 5 answered");
    });
  });

  describe("pointerGet()", () => {
    it("GETs /v1/pointers/{addr} and maps every field", async () => {
      const calls = stubFetch(200, {
        address: A,
        owner: OWNER_PK,
        counter: "7",
        kind: "chunk",
        kind_tag: 0,
        target: T1,
        state_id: SID,
        is_final: false,
        transferred_to: null,
      });
      const r = await client.pointerGet(A);
      expect(calls[0]).toEqual({ method: "GET", path: `/v1/pointers/${A}`, body: undefined });
      expect(r).toEqual({
        address: A,
        owner: OWNER_PK,
        counter: 7n,
        kind: "chunk",
        kindTag: 0,
        target: T1,
        stateId: SID,
        isFinal: false,
        transferredTo: null,
      });
    });

    it("reads a transferred pointer at the final counter, 2^64 - 1, exactly", async () => {
      stubFetch(200, {
        address: A,
        owner: OWNER_PK,
        counter: U64_MAX,
        kind: "pointer",
        kind_tag: 1,
        target: B,
        state_id: SID,
        is_final: true,
        transferred_to: B,
      });
      const r = await client.pointerGet(A);
      expect(r.counter).toBe(POINTER_FINAL_COUNTER);
      expect(r.counter).toBe(18446744073709551615n);
      expect(r.isFinal).toBe(true);
      expect(r.transferredTo).toBe(B);
    });

    it("keeps an unknown target kind with its raw tag", async () => {
      stubFetch(200, {
        address: A,
        owner: OWNER_PK,
        counter: "0",
        kind: "unknown",
        kind_tag: 9,
        target: T1,
        state_id: SID,
        is_final: false,
        transferred_to: null,
      });
      const r = await client.pointerGet(A);
      expect(r.kind).toBe("unknown");
      expect(r.kindTag).toBe(9);
    });

    it("throws NotFoundError when no pointer exists", async () => {
      stubFetch(404, { error: "Record not found: pointer", code: "NOT_FOUND" });
      await expect(client.pointerGet(A)).rejects.toThrow(NotFoundError);
    });

    it("throws ForkError on POINTER_FORKED", async () => {
      stubFetch(409, { error: "Pointer is forked: no majority", code: "POINTER_FORKED" });
      const err = await rejection(client.pointerGet(A));
      expect(err).toBeInstanceOf(ForkError);
      expect(err).not.toBeInstanceOf(AlreadyExistsError);
    });

    it("throws CloseGroupShortfallError (retryable false) on a short read", async () => {
      stubFetch(503, {
        error: "Close group shortfall: only 3 answered",
        code: "CLOSE_GROUP_SHORTFALL",
      });
      const err = await rejection(client.pointerGet(A));
      expect(err).toBeInstanceOf(CloseGroupShortfallError);
      expect(err).not.toBeInstanceOf(ServiceUnavailableError);
      expect((err as CloseGroupShortfallError).retryable).toBe(false);
      expect((err as AntdError).statusCode).toBe(503);
    });
  });

  describe("pointerResolve()", () => {
    it("GETs /v1/pointers/{addr}/resolve", async () => {
      const calls = stubFetch(200, { kind: "chunk", kind_tag: 0, target: T2 });
      expect(await client.pointerResolve(A)).toEqual({ kind: "chunk", kindTag: 0, target: T2 });
      expect(calls[0].path).toBe(`/v1/pointers/${A}/resolve`);
    });
  });

  describe("pointerFinality()", () => {
    it("parses an open pointer with a corroborated counter", async () => {
      const calls = stubFetch(200, {
        address: A,
        group: 5,
        answered: 5,
        status: "open",
        counter: "1",
        state: null,
        states: [],
        majority: null,
        transferred_to: null,
      });
      const f = await client.pointerFinality(A);
      expect(calls[0].path).toBe(`/v1/pointers/${A}/finality`);
      expect(f.status).toBe("open");
      expect(f.counter).toBe(1n);
      expect(f.state).toBeNull();
      expect(f.majority).toBeNull();
      expect(f.transferredTo).toBeNull();
    });

    it("reads a null counter as null, not 0", async () => {
      stubFetch(200, {
        address: A,
        group: 5,
        answered: 2,
        status: "open",
        counter: null,
        state: null,
        states: [],
        majority: null,
        transferred_to: null,
      });
      expect((await client.pointerFinality(A)).counter).toBeNull();
    });

    it("parses a forked pointer's states and majority", async () => {
      const rival = { ...finalState, state_id: "6f".repeat(32), target: A, holders: 1, transferred_to: A };
      stubFetch(200, {
        address: A,
        group: 5,
        answered: 5,
        status: "forked",
        counter: null,
        state: null,
        states: [finalState, rival],
        majority: finalState,
        transferred_to: null,
      });
      const f = await client.pointerFinality(A);
      expect(f.status).toBe("forked");
      expect(f.states.map((s) => s.holders)).toEqual([5, 1]);
      expect(f.states[1].stateId).toBe("6f".repeat(32));
      expect(f.majority?.stateId).toBe(SID);
      expect(f.transferredTo).toBeNull();
    });

    it.each(["settling", "unconfirmed", "final"] as const)("keeps the known status %s", async (status) => {
      stubFetch(200, { ...finalFinality, status });
      const f = await client.pointerFinality(A);
      expect(f.status).toBe(status);
      expect(f.rawStatus).toBe(status);
    });

    it("maps a status from a newer daemon to unknown and keeps the raw string", async () => {
      stubFetch(200, { ...finalFinality, status: "superseded" });
      const f = await client.pointerFinality(A);
      expect(f.status).toBe("unknown");
      expect(f.rawStatus).toBe("superseded");
    });
  });

  describe("pointerController()", () => {
    it("GETs /v1/pointers/{addr}/controller", async () => {
      const calls = stubFetch(200, { pointer: B, transfers: [B], frozen: false });
      expect(await client.pointerController(A)).toEqual({
        pointer: B,
        transfers: [B],
        frozen: false,
      });
      expect(calls[0].path).toBe(`/v1/pointers/${A}/controller`);
    });
  });

  describe("pointerPrepare()", () => {
    const prepared = {
      upload_id: "up-1",
      op: "update",
      address: A,
      state_id: SID,
      counter: "2",
      payment_type: "wave_batch",
      payments: [{ quote_hash: "0xq1", rewards_address: "0xr1", amount: "100" }],
      total_amount: "100",
      payment_vault_address: "0xvault",
      payment_token_address: "0xtoken",
      rpc_url: "http://rpc.local",
    };

    it("sends a create/update with target and kind, and parses the wave-batch quote", async () => {
      const calls = stubFetch(200, prepared);
      const p = await client.pointerPrepare(A, { op: "update", target: T2, kind: PointerKind.Chunk });
      expect(calls).toEqual([
        {
          method: "POST",
          path: "/v1/pointers/prepare",
          body: { owner: A, op: "update", target: T2, kind: "chunk" },
        },
      ]);
      expect(p).toEqual({
        uploadId: "up-1",
        op: "update",
        address: A,
        stateId: SID,
        counter: 2n,
        paymentType: "wave_batch",
        payments: [{ quoteHash: "0xq1", rewardsAddress: "0xr1", amount: "100" }],
        totalAmount: "100",
        paymentVaultAddress: "0xvault",
        paymentTokenAddress: "0xtoken",
        rpcUrl: "http://rpc.local",
        signedQuotes: [],
      });
    });

    it("sends a transfer with only the recipient", async () => {
      const calls = stubFetch(200, { ...prepared, op: "transfer", counter: U64_MAX });
      const p = await client.pointerPrepare(A, { op: "transfer", recipient: B });
      expect(calls[0].body).toEqual({ owner: A, op: "transfer", recipient: B });
      expect(p.counter).toBe(POINTER_FINAL_COUNTER);
    });

    it("omits kind on a create without one", async () => {
      const calls = stubFetch(200, { ...prepared, op: "create", counter: "0" });
      await client.pointerPrepare(A, { op: "create", target: T1 });
      expect(calls[0].body).toEqual({ owner: A, op: "create", target: T1 });
    });

    it("asks for and parses signed quotes when includeSignedQuotes is set", async () => {
      const calls = stubFetch(200, {
        ...prepared,
        signed_quotes: [
          { quote_hash: "0xq1", quote: "cXVvdGU=", commitment_sidecar: "c2lkZQ==" },
          { quote_hash: "0xq2", quote: "cXVvdGUy" },
        ],
      });
      const p = await client.pointerPrepare(A, { op: "update", target: T2 }, { includeSignedQuotes: true });
      expect(calls[0].body).toEqual({
        owner: A,
        op: "update",
        target: T2,
        include_signed_quotes: true,
      });
      expect(p.signedQuotes).toEqual([
        { quoteHash: "0xq1", quote: "cXVvdGU=", commitmentSidecar: "c2lkZQ==" },
        { quoteHash: "0xq2", quote: "cXVvdGUy", commitmentSidecar: null },
      ]);
    });

    it("throws ConflictError when a prepared write is already pending", async () => {
      stubFetch(409, { error: "Conflict: a prepared write is pending", code: "CONFLICT" });
      await expect(client.pointerPrepare(A, { op: "update", target: T2 })).rejects.toThrow(ConflictError);
    });
  });

  describe("pointerFinalize()", () => {
    it("POSTs upload_id + tx_hashes and returns the stored state", async () => {
      const calls = stubFetch(200, { address: A, state_id: SID, counter: "2" });
      const r = await client.pointerFinalize("up-1", { "0xq1": "0xtx1" });
      expect(calls).toEqual([
        {
          method: "POST",
          path: "/v1/pointers/finalize",
          body: { upload_id: "up-1", tx_hashes: { "0xq1": "0xtx1" } },
        },
      ]);
      expect(r).toEqual({ address: A, stateId: SID, counter: 2n, finality: null });
    });

    it("parses a transfer's finality", async () => {
      stubFetch(200, { address: A, state_id: SID, counter: U64_MAX, finality: finalFinality });
      const r = await client.pointerFinalize("up-2", {});
      expect(r.counter).toBe(POINTER_FINAL_COUNTER);
      expect(r.finality?.status).toBe("final");
      expect(r.finality?.transferredTo).toBe(B);
    });

    it("throws a retryable CloseGroupShortfallError when the paid state was kept", async () => {
      const calls = stubFetch(503, {
        error:
          "Close group shortfall: stored on 3 of 5 (paid attempt retained: call finalize again with the same upload_id)",
        code: "CLOSE_GROUP_SHORTFALL",
        retryable: true,
      });
      const err = await rejection(client.pointerFinalize("up-1", { "0xq1": "0xtx1" }));
      expect(err).toBeInstanceOf(CloseGroupShortfallError);
      expect((err as CloseGroupShortfallError).retryable).toBe(true);
      // The client never repeats a paid call itself.
      expect(calls).toHaveLength(1);
    });
  });

  describe("counter parsing", () => {
    const record = (counter: unknown) => ({
      address: A,
      owner: OWNER_PK,
      counter,
      kind: "chunk",
      kind_tag: 0,
      target: T1,
      state_id: SID,
      is_final: false,
      transferred_to: null,
    });

    it.each([
      ["0", 0n],
      ["1", 1n],
      ["9007199254740993", 9007199254740993n], // 2^53 + 1: past Number precision
      [U64_MAX, 18446744073709551615n],
    ])("reads %s exactly", async (wire, want) => {
      stubFetch(200, record(wire));
      expect((await client.pointerGet(A)).counter).toBe(want);
    });

    it.each([
      ["18446744073709551616"], // 2^64: one past u64
      ["-1"],
      ["1.5"],
      ["1e3"],
      [" 1"],
      ["0x10"],
      [""],
      ["abc"],
    ])("rejects the malformed counter %j instead of reading 0", async (wire) => {
      stubFetch(200, record(wire));
      const err = await rejection(client.pointerGet(A));
      expect(err).toBeInstanceOf(InternalError);
      expect((err as Error).message).toContain("not a decimal counter");
    });

    it.each([[5], [null], [undefined]])("rejects a non-string counter (%j) on a record", async (wire) => {
      stubFetch(200, record(wire));
      await expect(client.pointerGet(A)).rejects.toThrow(InternalError);
    });

    it("rejects a malformed finality counter instead of reading null", async () => {
      stubFetch(200, { ...finalFinality, status: "open", counter: "nope" });
      await expect(client.pointerFinality(A)).rejects.toThrow(InternalError);
    });

    it("rejects a malformed write counter", async () => {
      stubFetch(200, { address: A, state_id: SID, counter: 3 });
      await expect(client.pointerCreate(A, T1)).rejects.toThrow(InternalError);
    });
  });

  describe("fromErrorBody() pointer codes", () => {
    it.each([
      ["POINTER_FINAL", 409, PointerFinalError],
      ["POINTER_FORKED", 409, ForkError],
      ["CONFLICT", 409, ConflictError],
      ["CLOSE_GROUP_SHORTFALL", 503, CloseGroupShortfallError],
      ["ALREADY_EXISTS", 409, AlreadyExistsError],
      ["SERVICE_UNAVAILABLE", 503, ServiceUnavailableError],
    ] as const)("maps %s (%i) to its class", (code, status, cls) => {
      const err = fromErrorBody(status, "msg", { error: "msg", code });
      expect(err).toBeInstanceOf(cls);
      expect(err).toBeInstanceOf(AntdError);
      expect(err.statusCode).toBe(status);
      expect(err.message).toBe("msg");
    });

    it("reads retryable only when the body says true", () => {
      const shortfall = (retryable: unknown) =>
        fromErrorBody(503, "m", { code: "CLOSE_GROUP_SHORTFALL", retryable }) as CloseGroupShortfallError;
      expect(shortfall(true).retryable).toBe(true);
      expect(shortfall(false).retryable).toBe(false);
      expect(shortfall("true").retryable).toBe(false);
      expect(shortfall(undefined).retryable).toBe(false);
    });

    it("keeps the error classes' names for logging", () => {
      expect(new PointerFinalError("m").name).toBe("PointerFinalError");
      expect(new ConflictError("m").name).toBe("ConflictError");
      expect(new CloseGroupShortfallError("m").name).toBe("CloseGroupShortfallError");
      expect(new CloseGroupShortfallError("m").statusCode).toBe(503);
      expect(new CloseGroupShortfallError("m").retryable).toBe(false);
    });
  });
});
