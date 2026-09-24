<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/**
 * A finalize stored some chunks while others stayed unstored after the
 * daemon's own retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`).
 *
 * The on-chain payment persists and the stored chunks stay on the network.
 * How to finish the upload depends on {@see $retryable}:
 *
 *  - `true` — the daemon kept the paid attempt (payment proofs + unstored
 *    chunks) under the same `upload_id`. Call the **same** finalize method
 *    again with the same arguments to store the remainder against the same
 *    payment: no re-prepare, no second signature, no double payment. Bound
 *    that loop — a persistent failure returns this error on every call, so
 *    cap the attempts and treat a `chunksFailed` that stops shrinking as
 *    stuck. The retained attempt expires with the daemon's pending-upload
 *    TTL. Sent by antd >= 0.14.0; older daemons never send the flag, so it
 *    reads `false` and the re-prepare path below applies.
 *  - `false` — nothing was retained (an older daemon, or a merkle finalize
 *    with deliberately unpaid batches). Re-preparing the same content skips
 *    already-stored chunks, so a retry pays only for the remainder.
 *
 * Extends {@see NetworkError} because the daemon reports it as a 502, which
 * this SDK has always surfaced as `NetworkError`: existing
 * `catch (NetworkError $e)` blocks keep catching it, and callers that want
 * the counts catch this subclass first.
 *
 * See docs/external-signer-flow.md, "6. Retry a partial store".
 */
class PartialUploadError extends NetworkError
{
    /** Chunks the daemon stored before giving up. */
    public readonly int $chunksStored;

    /** Chunks still unstored after the daemon's retries. */
    public readonly int $chunksFailed;

    /** Chunks the upload consists of. */
    public readonly int $totalChunks;

    /**
     * `true` when the paid attempt was retained and the same finalize call
     * (same `upload_id`) stores the remainder against the same payment.
     */
    public readonly bool $retryable;

    public function __construct(
        string $message,
        int $chunksStored = 0,
        int $chunksFailed = 0,
        int $totalChunks = 0,
        bool $retryable = false,
    ) {
        $this->chunksStored = $chunksStored;
        $this->chunksFailed = $chunksFailed;
        $this->totalChunks = $totalChunks;
        $this->retryable = $retryable;
        parent::__construct($message);
    }
}
