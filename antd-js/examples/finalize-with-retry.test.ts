import { afterEach, describe, expect, it, vi } from "vitest";

import { NotFoundError, PartialUploadError } from "../src/errors.js";
import { RestClient } from "../src/rest-client.js";
import { finalizeWithRetry } from "./finalize-with-retry.js";

// The example's retry helper repeats a finalize only for a partial the daemon
// confirmed it retained, and every stop rethrows the original typed error so
// the caller can still tell the three recovery cases apart.

const noDelay = vi.fn(() => Promise.resolve());
const log = vi.fn();
const opts = { delay: noDelay, log, maxAttempts: 3 };

function partial(
  chunksFailed: number,
  flags: { retryable?: boolean; retentionKnown?: boolean },
): PartialUploadError {
  return new PartialUploadError(`Partial upload: ${10 - chunksFailed}/10 chunks stored`, {
    chunksStored: 10 - chunksFailed,
    chunksFailed,
    totalChunks: 10,
    ...flags,
  });
}

const retained = (chunksFailed: number) => partial(chunksFailed, { retryable: true });

/** A finalize stub that throws each error in turn, then resolves `result`. */
function finalizeStub<T>(errors: unknown[], result?: T) {
  let call = 0;
  return vi.fn(async () => {
    const err = errors[call++];
    if (err !== undefined) throw err;
    return result as T;
  });
}

/** The error a promise rejects with; fails the test if it resolves. */
function rejection(p: Promise<unknown>): Promise<unknown> {
  return p.then(
    () => {
      throw new Error("expected finalizeWithRetry to throw");
    },
    (e: unknown) => e,
  );
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

afterEach(() => {
  vi.clearAllMocks();
  vi.unstubAllGlobals();
});

describe("finalizeWithRetry (examples/finalize-with-retry.ts)", () => {
  it("returns the first success without retrying", async () => {
    const attempt = finalizeStub([], "done");
    await expect(finalizeWithRetry("u1", attempt, opts)).resolves.toBe("done");
    expect(attempt).toHaveBeenCalledTimes(1);
    expect(noDelay).not.toHaveBeenCalled();
  });

  it("repeats the same call while the daemon retains the attempt and progress continues", async () => {
    const attempt = finalizeStub([retained(4), retained(2)], "done");
    await expect(finalizeWithRetry("u1", attempt, opts)).resolves.toBe("done");
    expect(attempt).toHaveBeenCalledTimes(3);
    expect(noDelay.mock.calls).toEqual([[1], [2]]);
  });

  it("rethrows the original PartialUploadError when the attempts run out", async () => {
    const last = retained(1);
    const attempt = finalizeStub([retained(3), retained(2), last], "never");
    const err = await rejection(finalizeWithRetry("u1", attempt, opts));
    expect(err).toBe(last);
    expect(attempt).toHaveBeenCalledTimes(3);
    expect(log.mock.calls.at(-1)?.[0]).toMatch(/stays retained under upload_id u1/);
  });

  it("rethrows the original PartialUploadError when chunksFailed stops shrinking", async () => {
    const stalled = retained(2);
    const attempt = finalizeStub([retained(2), stalled], "never");
    const err = await rejection(finalizeWithRetry("u1", attempt, opts));
    expect(err).toBe(stalled);
    expect(attempt).toHaveBeenCalledTimes(2);
  });

  it("stops at once on confirmed non-retention and rethrows the error", async () => {
    const notRetained = partial(2, { retentionKnown: true, retryable: false });
    const attempt = finalizeStub([notRetained], "never");
    const err = await rejection(finalizeWithRetry("u1", attempt, opts));
    expect(err).toBe(notRetained);
    expect(attempt).toHaveBeenCalledTimes(1);
    expect(noDelay).not.toHaveBeenCalled();
  });

  it("stops at once on unknown retention: no retry, error rethrown, reconcile advised", async () => {
    const unknown = partial(2, {});
    const attempt = finalizeStub([unknown], "never");
    const err = await rejection(finalizeWithRetry("u1", attempt, opts));
    expect(err).toBe(unknown);
    expect((err as PartialUploadError).retentionKnown).toBe(false);
    expect(attempt).toHaveBeenCalledTimes(1);
    expect(noDelay).not.toHaveBeenCalled();
    expect(log.mock.calls.at(-1)?.[0]).toMatch(/keep upload_id u1 .*reconcile/);
  });

  it("stops when a later attempt reports unknown retention", async () => {
    const unknown = partial(1, {});
    const attempt = finalizeStub([retained(2), unknown], "never");
    const err = await rejection(finalizeWithRetry("u1", attempt, opts));
    expect(err).toBe(unknown);
    expect(attempt).toHaveBeenCalledTimes(2);
  });

  it("passes any other error through untouched", async () => {
    const gone = new NotFoundError("upload_id u1 not found");
    const attempt = finalizeStub([retained(2), gone], "never");
    const err = await rejection(finalizeWithRetry("u1", attempt, opts));
    expect(err).toBe(gone);
    expect(attempt).toHaveBeenCalledTimes(2);
  });

  describe("through RestClient.finalizeUpload", () => {
    const partialBody = (extra: Record<string, unknown>) => ({
      error: "Partial upload: 10/12 chunks stored, 2 failed after retries: quorum",
      code: "PARTIAL_UPLOAD",
      chunks_stored: 10,
      chunks_failed: 2,
      total_chunks: 12,
      ...extra,
    });

    it("resends the same upload_id and tx_hashes until the retained attempt completes", async () => {
      const fetchFn = vi
        .fn()
        .mockResolvedValueOnce(json(502, partialBody({ retryable: true })))
        .mockResolvedValueOnce(
          json(200, { chunks_stored: 12, data_map: "dm", data_map_address: "dma" }),
        );
      vi.stubGlobal("fetch", fetchFn);
      const client = new RestClient({ baseUrl: "http://localhost:8082" });
      const txHashes = { "0xq1": "0xtx1" };

      const fin = await finalizeWithRetry(
        "up-1",
        () => client.finalizeUpload("up-1", txHashes),
        opts,
      );

      expect(fin.chunksStored).toBe(12);
      expect(fetchFn).toHaveBeenCalledTimes(2);
      const bodies = fetchFn.mock.calls.map(([, init]) =>
        JSON.parse((init as RequestInit).body as string),
      );
      expect(bodies).toEqual([
        { upload_id: "up-1", tx_hashes: txHashes },
        { upload_id: "up-1", tx_hashes: txHashes },
      ]);
    });

    it("stops on an older daemon's partial (no retryable) and rethrows the typed error", async () => {
      const fetchFn = vi.fn().mockResolvedValue(json(502, partialBody({})));
      vi.stubGlobal("fetch", fetchFn);
      const client = new RestClient({ baseUrl: "http://localhost:8082" });

      const err = await rejection(
        finalizeWithRetry("up-1", () => client.finalizeUpload("up-1", {}), opts),
      );

      expect(err).toBeInstanceOf(PartialUploadError);
      expect(err).toMatchObject({ retryable: false, retentionKnown: false, chunksFailed: 2 });
      expect(fetchFn).toHaveBeenCalledTimes(1);
    });
  });
});
