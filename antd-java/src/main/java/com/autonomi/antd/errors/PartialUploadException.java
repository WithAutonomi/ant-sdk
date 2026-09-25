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
 * Over gRPC the daemon surfaces a partial upload as status {@code ABORTED}
 * whose description starts with the fixed prefix {@code "Partial upload:"}
 * ({@code "Partial upload: S/T chunks stored, F failed ..."}, with a
 * {@code "paid attempt retained"} hint when retryable). The gRPC client maps
 * {@code ABORTED} to this exception only when
 * {@link #isPartialUploadMessage(String)} finds that prefix at the start of
 * the description (an {@code ABORTED} that merely quotes it further in keeps
 * the generic mapping), and parses the rest via {@link #fromMessage(String)}.
 * {@code retryable} is {@code true} only when all three counts parse and the
 * hint is present: a description whose counts do not match the layout, or
 * overflow a {@code long}, yields zero counts and {@code retryable == false}
 * even with the hint, because a bounded retry loop that cannot watch
 * {@link #getChunksFailed()} shrink cannot tell progress from a stuck upload.
 *
 * <p>See {@code docs/external-signer-flow.md} §6 ("Retry a partial store")
 * for the daemon-side contract.
 */
public class PartialUploadException extends NetworkException {

    /** Machine-readable error code the daemon sends in the REST error body. */
    public static final String CODE = "PARTIAL_UPLOAD";

    /**
     * Fixed text every {@code PARTIAL_UPLOAD} message from the daemon starts
     * with. Over gRPC this is the only marker that distinguishes a partial
     * upload from any other {@code ABORTED} status, and it counts only at the
     * start of the description (see {@link #isPartialUploadMessage(String)}).
     */
    public static final String MESSAGE_PREFIX = "Partial upload:";

    /**
     * Count layout that follows the prefix:
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
     * Whether {@code message} is the daemon's {@code PARTIAL_UPLOAD} wire text,
     * i.e. it starts with the fixed {@link #MESSAGE_PREFIX}. The gRPC client
     * uses this to decide whether an {@code ABORTED} status is a partial upload
     * at all. The match is anchored at the start rather than a containment
     * check: the daemon never wraps its own message, so a status that merely
     * quotes {@code "Partial upload:"} further into its description is not a
     * partial upload and must not select the paid-attempt retry path. A
     * {@code null} or unrelated message is not one either.
     */
    public static boolean isPartialUploadMessage(String message) {
        return message != null && message.startsWith(MESSAGE_PREFIX);
    }

    /**
     * Builds the exception from a bare {@code PARTIAL_UPLOAD} message, recovering
     * the chunk counts and the retryable hint from the text. Used for gRPC, where
     * the status carries no structured detail; REST callers get the body fields.
     * Callers should gate on {@link #isPartialUploadMessage(String)} first.
     *
     * <p>{@code retryable} is {@code true} only when the message matches the
     * count layout, all three counts convert to a {@code long}, and the
     * {@code "paid attempt retained"} hint is present. On a layout miss or a
     * failed conversion (a count that overflows a {@code long}) all three
     * counts are zero and {@code retryable} is {@code false}, even when the
     * hint is present: a caller must never be steered into the same-upload_id
     * retry loop by a message whose counts it could not read.
     */
    public static PartialUploadException fromMessage(String message) {
        String msg = message == null ? "" : message;
        Matcher m = COUNTS.matcher(msg);
        if (m.find()) {
            try {
                long stored = Long.parseLong(m.group(1));
                long total = Long.parseLong(m.group(2));
                long failed = Long.parseLong(m.group(3));
                return new PartialUploadException(msg, stored, failed, total,
                        msg.contains(RETAINED_HINT));
            } catch (NumberFormatException overflow) {
                // A count beyond Long.MAX_VALUE: fall through to the
                // all-or-nothing default rather than keep the counts that did
                // convert.
            }
        }
        return new PartialUploadException(msg, 0L, 0L, 0L, false);
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
