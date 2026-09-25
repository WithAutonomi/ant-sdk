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
 * starts with the fixed prefix {@code "Partial upload:"} and closes with one
 * of two parenthesised retention hints:
 * {@code "Partial upload: S/T chunks stored, F failed after retries: <reason> (<hint>)"},
 * where the hint starts {@code "paid attempt retained"} when the daemon kept
 * the paid attempt, and
 * {@code "stored chunks persist; re-prepare the same content"} when it did
 * not (daemons older than 0.14.0 write only the second). The gRPC client
 * maps {@code ABORTED} to this exception only when
 * {@link #isPartialUploadMessage(String)} finds that prefix at the start of
 * the description (an {@code ABORTED} that merely quotes it further in keeps
 * the generic mapping), and parses the rest via {@link #fromMessage(String)}:
 * retention is known only when the description starts with the count layout,
 * all three counts convert to a {@code long}, and the description ends with
 * one of the two hints, which then decides {@code retryable}. A layout miss
 * or an overflowing count zeroes the counts and leaves both flags
 * {@code false}, even with the hint. Readable counts with a missing,
 * truncated or unrecognised hint keep the counts, but both flags stay
 * {@code false}: retention is unknown, not "nothing retained".
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
     * Count layout that opens the message:
     * {@code "Partial upload: <stored>/<total> chunks stored, <failed> failed"}.
     * Matched only at the start ({@link Matcher#lookingAt()}), like the
     * prefix gate, so counts quoted later in a garbled message are never read.
     */
    private static final Pattern COUNTS =
            Pattern.compile("Partial upload: (\\d+)/(\\d+) chunks stored, (\\d+) failed");

    /*
     * The daemon closes every PARTIAL_UPLOAD message with one of two
     * parenthesised hints (partial_upload_hint in antd/src/error.rs): the
     * retained hint when it kept the paid attempt for a same-upload_id retry,
     * the not-retained hint when it did not. Daemons older than 0.14.0 write
     * only the not-retained hint.
     */
    private static final String RETAINED_HINT = "paid attempt retained";
    private static final String NOT_RETAINED_HINT =
            "stored chunks persist; re-prepare the same content";

    /**
     * The hint that closes the message: {@code "(<hint>...)"} at the very end
     * of the input. {@code \z}, not {@code $}: in java.util.regex {@code $}
     * also matches before a final line terminator. A hint quoted inside the
     * failure reason, a truncated tail, or any text or newline after the hint
     * does not match.
     */
    private static final Pattern RETENTION_TAIL = Pattern.compile(
            "\\((" + Pattern.quote(RETAINED_HINT) + "|" + Pattern.quote(NOT_RETAINED_HINT)
                    + ")[^()]*\\)\\z");

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
     * the chunk counts and the retention hint from the text. Used for gRPC, where
     * the status carries no structured detail; REST callers get the body fields.
     * Callers should gate on {@link #isPartialUploadMessage(String)} first.
     *
     * <p>Retention is known only when the message starts with the count
     * layout, all three counts convert to a {@code long}, and the message ends
     * with one of the daemon's two hints, {@code "(paid attempt retained...)"}
     * or {@code "(stored chunks persist; re-prepare the same content...)"};
     * {@code retryable} is then {@code true} only for the first. On a layout
     * miss or a failed conversion (a count that overflows a {@code long}) all
     * three counts are zero and both flags are {@code false}, even when the
     * hint is present. Readable counts with a missing, truncated or
     * unrecognised hint, or with text or a newline after it, keep the counts
     * but leave both flags {@code false}: the daemon's answer on retention was
     * not read, so retention is unknown. A message the SDK could not fully
     * read must never steer a caller into the same-upload_id retry loop, nor
     * tell it that nothing was retained.
     */
    public static PartialUploadException fromMessage(String message) {
        String msg = message == null ? "" : message;
        Matcher m = COUNTS.matcher(msg);
        if (m.lookingAt()) {
            try {
                long stored = Long.parseLong(m.group(1));
                long total = Long.parseLong(m.group(2));
                long failed = Long.parseLong(m.group(3));
                Matcher tail = RETENTION_TAIL.matcher(msg);
                boolean known = tail.find();
                return new PartialUploadException(msg, stored, failed, total,
                        known && RETAINED_HINT.equals(tail.group(1)), known);
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
     * description's counts parsed and it ended with one of the daemon's two
     * retention hints. Together with {@code isRetryable() == false}
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
