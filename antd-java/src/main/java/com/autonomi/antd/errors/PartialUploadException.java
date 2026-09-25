package com.autonomi.antd.errors;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * A finalize stored some chunks while others remained unstored after the
 * daemon's retries (HTTP 502 with code {@code PARTIAL_UPLOAD}; gRPC
 * {@code ABORTED}). The on-chain payment persists and the stored chunks stay
 * on the network. How to finish the upload depends on {@link #isRetryable()}
 * and {@link #isRetentionKnown()}:
 *
 * <ul>
 *   <li>{@code isRetryable()} — the daemon kept the paid attempt (payment
 *       proofs + unstored chunks) under the same {@code upload_id}. Call the
 *       <b>same</b> finalize method again with the same {@code upload_id} and
 *       the same payment artefacts (tx hashes, or the winner pool hash) to
 *       store the remainder against the same payment — no re-prepare, no
 *       second signature, no double payment. Bound the loop: a persistent
 *       failure throws this exception on every call, so cap the attempts and
 *       treat a {@link #getChunksFailed()} that stops shrinking as stuck. The
 *       retained attempt expires with the daemon's pending-upload TTL.</li>
 *   <li>{@code isRetentionKnown() && !isRetryable()} — the daemon confirmed
 *       it kept nothing (for example a merkle finalize with deliberately
 *       unpaid batches). Re-prepare the same content; already-stored chunks
 *       are skipped.</li>
 *   <li>{@code !isRetentionKnown()} — retention is unknown. The daemon may
 *       still hold the paid attempt: it records the resume handle before it
 *       returns the error. Stop automatic recovery, keep the
 *       {@code upload_id} and the original payment artefacts, and reconcile
 *       before re-preparing or paying again. Never pay again on this signal
 *       alone: re-preparing skips chunks already stored, not chunks that were
 *       paid for and are still unstored. Daemons older than 0.14.0 never send
 *       {@code retryable}, so their REST partial uploads read as unknown.</li>
 * </ul>
 *
 * <p>{@code isRetryable()} always implies {@code isRetentionKnown()}.
 *
 * <p>Extends {@link NetworkException} because a {@code PARTIAL_UPLOAD} arrives
 * as HTTP 502, which this SDK has always surfaced as {@code NetworkException};
 * existing {@code catch (NetworkException e)} blocks therefore keep working
 * and can narrow with {@code instanceof} when they want the counts.
 *
 * <p>Over REST the counts and both flags come from the structured error body:
 * retention is known only when the body carries {@code retryable} as a JSON
 * boolean, and {@code retryable} is that boolean. Over gRPC the daemon
 * surfaces a partial upload as status {@code ABORTED} whose description
 * starts with the fixed prefix {@code "Partial upload:"}
 * ({@code "Partial upload: S/T chunks stored, F failed ..."}, with a
 * {@code "paid attempt retained"} hint when retryable). The gRPC client maps
 * {@code ABORTED} to this exception only when
 * {@link #isPartialUploadMessage(String)} finds that prefix at the start of
 * the description (an {@code ABORTED} that merely quotes it further in keeps
 * the generic mapping), and parses the rest via {@link #fromMessage(String)}:
 * when the count layout matches and all three counts convert to a
 * {@code long}, retention is known and {@code retryable} follows the hint;
 * otherwise the counts are zero, retention is unknown and {@code retryable}
 * is {@code false}, even with the hint.
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
    private final boolean retentionKnown;

    /**
     * Same as
     * {@link #PartialUploadException(String, long, long, long, boolean, boolean)}
     * with {@code retentionKnown == retryable}: a {@code false} flag given
     * without saying whether retention is known reads as unknown, the
     * conservative default.
     */
    public PartialUploadException(String message, long chunksStored, long chunksFailed,
                                  long totalChunks, boolean retryable) {
        this(message, chunksStored, chunksFailed, totalChunks, retryable, retryable);
    }

    /**
     * @param message        the daemon's error message
     * @param chunksStored   chunks the daemon stored before giving up
     * @param chunksFailed   chunks still unstored after the daemon's retries
     * @param totalChunks    total chunks in the upload
     * @param retryable      the daemon kept the paid attempt under the same
     *                       {@code upload_id}
     * @param retentionKnown the daemon's retention decision was read; forced
     *                       {@code true} when {@code retryable} is, so
     *                       {@code retryable} always implies it
     */
    public PartialUploadException(String message, long chunksStored, long chunksFailed,
                                  long totalChunks, boolean retryable, boolean retentionKnown) {
        super(message);
        this.chunksStored = chunksStored;
        this.chunksFailed = chunksFailed;
        this.totalChunks = totalChunks;
        this.retryable = retryable;
        this.retentionKnown = retentionKnown || retryable;
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
     * <p>When the message matches the count layout and all three counts
     * convert to a {@code long}, retention is known and {@code retryable} is
     * {@code true} exactly when the {@code "paid attempt retained"} hint is
     * present. On a layout miss or a failed conversion (a count that overflows
     * a {@code long}) all three counts are zero, retention is unknown and
     * {@code retryable} is {@code false}, even when the hint is present: a
     * caller must never be steered into the same-upload_id retry loop by a
     * message whose counts it could not read, nor told that nothing was
     * retained.
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
                        msg.contains(RETAINED_HINT), true);
            } catch (NumberFormatException overflow) {
                // A count beyond Long.MAX_VALUE: fall through to the
                // all-or-nothing default rather than keep the counts that did
                // convert.
            }
        }
        return new PartialUploadException(msg, 0L, 0L, 0L, false, false);
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
     * the same payment. {@code false} does not by itself mean nothing was
     * retained: check {@link #isRetentionKnown()} before re-preparing.
     */
    public boolean isRetryable() {
        return retryable;
    }

    /**
     * {@code true} when the daemon's retention decision was read: over REST the
     * error body carried {@code retryable} as a JSON boolean; over gRPC the
     * description's counts parsed. Together with {@code isRetryable() == false}
     * this means the daemon confirmed nothing was retained, so re-preparing is
     * the recovery. {@code false} means retention is unknown: the daemon may
     * still hold the paid attempt, so stop automatic recovery, keep the
     * {@code upload_id} and the original payment artefacts, and reconcile
     * before re-preparing or paying again. Always {@code true} when
     * {@link #isRetryable()} is.
     */
    public boolean isRetentionKnown() {
        return retentionKnown;
    }
}
