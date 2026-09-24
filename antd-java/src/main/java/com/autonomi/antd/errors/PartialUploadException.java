package com.autonomi.antd.errors;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * A finalize stored some chunks while others remained unstored after the
 * daemon's retries (HTTP 502 with code {@code PARTIAL_UPLOAD}; gRPC
 * {@code ABORTED}). The on-chain payment persists and the stored chunks stay
 * on the network. How to finish the upload depends on {@link #isRetryable()}:
 *
 * <ul>
 *   <li>{@code true} — the daemon kept the paid attempt (payment proofs +
 *       unstored chunks) under the same {@code upload_id}. Call the
 *       <b>same</b> finalize method again with the same arguments to store the
 *       remainder against the same payment — no re-prepare, no second
 *       signature, no double payment. Bound the loop: a persistent failure
 *       throws this exception on every call, so cap the attempts and treat a
 *       {@link #getChunksFailed()} that stops shrinking as stuck. The retained
 *       attempt expires with the daemon's pending-upload TTL. (Sent by antd
 *       &gt;= 0.14.0; older daemons never set the flag, so it reads
 *       {@code false} and the re-prepare path applies.)</li>
 *   <li>{@code false} — nothing was retained (a merkle finalize with
 *       deliberately unpaid batches, or an older daemon). Re-preparing the
 *       same content skips already-stored chunks, so a retry pays only for
 *       the missing remainder.</li>
 * </ul>
 *
 * <p>Extends {@link NetworkException} because a {@code PARTIAL_UPLOAD} arrives
 * as HTTP 502, which this SDK has always surfaced as {@code NetworkException};
 * existing {@code catch (NetworkException e)} blocks therefore keep working
 * and can narrow with {@code instanceof} when they want the counts.
 *
 * <p>Over REST the counts and the flag come from the structured error body.
 * Over gRPC they are parsed best-effort from the status description
 * ({@code "Partial upload: S/T chunks stored, F failed ..."}, with a
 * {@code "paid attempt retained"} hint when retryable) via
 * {@link #fromMessage(String)}; an unrecognised message leaves the counts
 * zero and {@code retryable} false.
 *
 * <p>See {@code docs/external-signer-flow.md} §6 ("Retry a partial store")
 * for the daemon-side contract.
 */
public class PartialUploadException extends NetworkException {

    /** Machine-readable error code the daemon sends in the REST error body. */
    public static final String CODE = "PARTIAL_UPLOAD";

    /**
     * Fixed prefix of the daemon's {@code PARTIAL_UPLOAD} message:
     * {@code "Partial upload: <stored>/<total> chunks stored, <failed> failed"}.
     */
    private static final Pattern COUNTS =
            Pattern.compile("Partial upload: (\\d+)/(\\d+) chunks stored, (\\d+) failed");

    /** Message tail the daemon appends when it kept the paid attempt. */
    private static final String RETAINED_HINT = "paid attempt retained";

    private final long chunksStored;
    private final long chunksFailed;
    private final long totalChunks;
    private final boolean retryable;

    public PartialUploadException(String message, long chunksStored, long chunksFailed,
                                  long totalChunks, boolean retryable) {
        super(message);
        this.chunksStored = chunksStored;
        this.chunksFailed = chunksFailed;
        this.totalChunks = totalChunks;
        this.retryable = retryable;
    }

    /**
     * Builds the exception from a bare {@code PARTIAL_UPLOAD} message, recovering
     * the chunk counts and the retryable hint from the text. Used for gRPC, where
     * the status carries no structured detail; REST callers get the body fields.
     * An unrecognised message yields zero counts and {@code retryable == false}.
     */
    public static PartialUploadException fromMessage(String message) {
        String msg = message == null ? "" : message;
        long stored = 0L;
        long total = 0L;
        long failed = 0L;
        Matcher m = COUNTS.matcher(msg);
        if (m.find()) {
            stored = parseCount(m.group(1));
            total = parseCount(m.group(2));
            failed = parseCount(m.group(3));
        }
        boolean retryable = msg.contains(RETAINED_HINT);
        return new PartialUploadException(msg, stored, failed, total, retryable);
    }

    private static long parseCount(String digits) {
        try {
            return Long.parseLong(digits);
        } catch (NumberFormatException e) {
            return 0L;
        }
    }

    /** Chunks the daemon stored before giving up. */
    public long getChunksStored() {
        return chunksStored;
    }

    /** Chunks still unstored after the daemon's retries. */
    public long getChunksFailed() {
        return chunksFailed;
    }

    /** Total chunks in the upload. */
    public long getTotalChunks() {
        return totalChunks;
    }

    /**
     * {@code true} when the daemon kept the paid attempt under the same
     * {@code upload_id}, so the same finalize call stores the remainder against
     * the same payment; {@code false} when the retry is a re-prepare.
     */
    public boolean isRetryable() {
        return retryable;
    }
}
