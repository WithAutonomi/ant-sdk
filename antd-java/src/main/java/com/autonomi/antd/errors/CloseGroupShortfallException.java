package com.autonomi.antd.errors;

/**
 * Too few of an address's close group answered, or took a write, for the
 * result to be the network's (HTTP 503 with
 * {@code code: "CLOSE_GROUP_SHORTFALL"}; gRPC {@code UNAVAILABLE} with
 * {@code x-antd-error-code: CLOSE_GROUP_SHORTFALL}).
 *
 * <p>Reads are free to retry; a read during an update or churn usually clears
 * once the update settles. A paid write is not, unless {@link #isRetryable()}
 * is {@code true}: a pointer finalize then kept the paid state under the same
 * {@code upload_id}, and calling {@code pointerFinalize} again with that
 * {@code upload_id} stores it against the same payment. Bound that loop.
 *
 * <p>It extends {@link AntdException} directly, not
 * {@link ServiceUnavailableException} (REST 503) or {@link NetworkException}
 * (gRPC {@code UNAVAILABLE}), so it reads the same on both transports. Daemons
 * before the pointer API reported this condition as a 500.
 */
public class CloseGroupShortfallException extends AntdException {

    /** The daemon's machine-readable code for this error. */
    public static final String CODE = "CLOSE_GROUP_SHORTFALL";

    private final boolean retryable;

    /**
     * Creates the exception.
     *
     * @param message   the error message from the daemon
     * @param retryable whether the daemon kept a paid pointer finalize for a
     *                  repeat with the same {@code upload_id}
     */
    public CloseGroupShortfallException(String message, boolean retryable) {
        super(503, message);
        this.retryable = retryable;
    }

    /**
     * Whether a pointer finalize kept the paid state: repeat
     * {@code pointerFinalize} with the same {@code upload_id} to store it
     * against the same payment. {@code false} everywhere else, including every
     * read and every daemon-wallet write.
     *
     * @return {@code true} only for a retained pointer finalize
     */
    public boolean isRetryable() {
        return retryable;
    }
}
