package com.autonomi.antd.errors;

/**
 * The request conflicts with the resource's current state (HTTP 409 with
 * {@code code: "CONFLICT"}; gRPC {@code ABORTED} with
 * {@code x-antd-error-code: CONFLICT}).
 *
 * <p>For pointers, two cases share this code, and it does not say which one
 * happened or whether anything was paid: a write while a prepared write to the
 * same pointer awaits payment is refused before paying (finalize the prepared
 * write, or wait for it to expire); an update that lost to a newer state while
 * it was in flight may already have been paid for. Read the pointer again and
 * check what was paid before submitting another paid write.
 *
 * <p>Not an {@link AlreadyExistsException}, although both are 409s.
 */
public class ConflictException extends AntdException {

    /** The daemon's machine-readable code for this error. */
    public static final String CODE = "CONFLICT";

    /**
     * Creates the exception.
     *
     * @param message the error message from the daemon
     */
    public ConflictException(String message) {
        super(409, message);
    }
}
