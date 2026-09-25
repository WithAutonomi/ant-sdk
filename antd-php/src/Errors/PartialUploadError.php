<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/**
 * A finalize stored some chunks while others stayed unstored after the
 * daemon's own retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`).
 *
 * The on-chain payment persists and the stored chunks stay on the network.
 * How to finish the upload depends on {@see $retryable} and
 * {@see $retentionKnown}:
 *
 *  - `retryable` — the daemon kept the paid attempt (payment proofs +
 *    unstored chunks) under the same `upload_id`. Call the **same** finalize
 *    method again with the same `upload_id` and payment artefacts (the same
 *    tx hashes) to store the remainder against the same payment: no
 *    re-prepare, no second signature, no double payment. Bound that loop —
 *    a persistent failure returns this error on every call, so cap the
 *    attempts and treat a `chunksFailed` that stops shrinking as stuck. The
 *    retained attempt expires with the daemon's pending-upload TTL.
 *  - `retentionKnown && !retryable` — the daemon confirmed nothing was
 *    retained (a daemon-wallet upload, or a merkle finalize that
 *    deliberately left sub-batches unpaid). Re-prepare the same content;
 *    already-stored chunks are skipped.
 *  - `!retentionKnown` — retention is unknown. The daemon may still hold the
 *    paid attempt: it records the resume handle before it returns this
 *    error. Stop automatic recovery, keep the `upload_id` and the original
 *    payment artefacts, and reconcile before re-preparing or paying again.
 *    Never pay again on this signal alone. Daemons older than 0.14.0 never
 *    send `retryable`, so their partial uploads read as unknown.
 *
 * `retryable` implies `retentionKnown`; the constructor enforces it.
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
     * Implies {@see $retentionKnown}.
     */
    public readonly bool $retryable;

    /**
     * `true` when the daemon said whether it retained the paid attempt (the
     * body carried a boolean `retryable`). `false` means retention is
     * unknown, not that nothing was retained: keep the `upload_id` and the
     * payment artefacts and reconcile before re-preparing or paying again.
     */
    public readonly bool $retentionKnown;

    public function __construct(
        string $message,
        int $chunksStored = 0,
        int $chunksFailed = 0,
        int $totalChunks = 0,
        bool $retryable = false,
        bool $retentionKnown = false,
    ) {
        $this->chunksStored = $chunksStored;
        $this->chunksFailed = $chunksFailed;
        $this->totalChunks = $totalChunks;
        $this->retryable = $retryable;
        $this->retentionKnown = $retentionKnown || $retryable;
        parent::__construct($message);
    }
}
