/**
 * Bounded finalize retry for the external-signer flow, used by
 * `07-external-signer.ts` and tested in `finalize-with-retry.test.ts`.
 * Example code, not part of the SDK API: copy and adapt it.
 *
 * See docs/external-signer-flow.md §6.
 */

import { setTimeout as sleep } from "node:timers/promises";

import { PartialUploadError } from "../src/index.js";

export interface FinalizeRetryOptions {
  /** Finalize calls in total, the first included. Default 5. */
  maxAttempts?: number;
  /** Wait after failed call number `attempt`. Default `attempt * 2` seconds. */
  delay?: (attempt: number) => Promise<unknown>;
  /** Progress and stop messages. Default `console.log`. */
  log?: (message: string) => void;
}

/**
 * Run a finalize call and, when the daemon reports a storage shortfall AFTER
 * the payment settled and confirms it kept the paid attempt (`retryable`),
 * retry the same call against the same payment. antd >= 0.14.0 keeps the
 * attempt (payment proofs + unstored chunks) under the same upload_id, so
 * repeating the finalize stores only the remainder: no re-prepare, no second
 * signature, no double payment. `attemptFinalize` must issue the SAME
 * finalize method with the SAME arguments each time; the closure guarantees
 * that.
 *
 * The loop is bounded: a persistent failure (a chunk whose close group stays
 * unreachable) throws PartialUploadError on every call, so it caps the
 * attempts and treats a `chunksFailed` that stops shrinking as stuck.
 *
 * Every stop rethrows the original PartialUploadError, so the caller keeps
 * its counts and flags and picks the recovery:
 *
 *   - `retryable` (attempts exhausted or progress stalled): the paid attempt
 *     is still retained under `uploadId`; retry the same finalize later
 *     instead of re-preparing.
 *   - `retentionKnown && !retryable`: the daemon confirmed nothing was
 *     retained; re-prepare the same content.
 *   - `!retentionKnown`: retention is unknown and the daemon may still hold
 *     the paid attempt. The helper stops at once, without re-preparing or
 *     paying; keep `uploadId` and the original payment artefacts and
 *     reconcile before re-preparing or paying again.
 *
 * Any other error propagates untouched.
 */
export async function finalizeWithRetry<T>(
  uploadId: string,
  attemptFinalize: () => Promise<T>,
  options: FinalizeRetryOptions = {},
): Promise<T> {
  const maxAttempts = options.maxAttempts ?? 5;
  const delay = options.delay ?? ((attempt: number) => sleep(attempt * 2_000));
  const log = options.log ?? console.log;
  let lastFailed = Infinity;
  for (let attempt = 1; ; attempt++) {
    try {
      return await attemptFinalize(); // every chunk stored
    } catch (err) {
      if (!(err instanceof PartialUploadError)) {
        throw err;
      }
      const counts =
        `${err.chunksStored}/${err.totalChunks} chunks stored, ` +
        `${err.chunksFailed} still unstored`;
      if (!err.retentionKnown) {
        log(
          `finalize partial (${counts}); the daemon did not confirm whether it ` +
            `kept the paid attempt. Stopping: keep upload_id ${uploadId} and the ` +
            `original payment artefacts, and reconcile before re-preparing or ` +
            `paying again.`,
        );
        throw err;
      }
      if (!err.retryable) {
        log(
          `finalize partial (${counts}); the daemon kept nothing under upload_id ` +
            `${uploadId}. Re-prepare the same content to store the remainder.`,
        );
        throw err;
      }
      const stuck = attempt > 1 && err.chunksFailed >= lastFailed;
      if (attempt >= maxAttempts || stuck) {
        log(
          `finalize stuck after ${attempt} attempt(s) (${counts}). The paid ` +
            `attempt stays retained under upload_id ${uploadId} until the ` +
            `daemon's pending-upload TTL: retry the same finalize later.`,
        );
        throw err;
      }
      lastFailed = err.chunksFailed;
      log(
        `finalize partial (${counts}); retrying against the same payment ` +
          `(attempt ${attempt + 1}/${maxAttempts})`,
      );
      await delay(attempt);
    }
  }
}
