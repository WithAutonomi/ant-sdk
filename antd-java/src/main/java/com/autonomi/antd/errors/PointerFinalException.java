package com.autonomi.antd.errors;

/**
 * The pointer is at its final state, transferred or frozen: nothing can update
 * it or hand it over again (HTTP 409 with {@code code: "POINTER_FINAL"}; gRPC
 * {@code FAILED_PRECONDITION} with {@code x-antd-error-code: POINTER_FINAL}).
 * Refused before anything is paid.
 *
 * <p>Not an {@link AlreadyExistsException}, although both are 409s.
 */
public class PointerFinalException extends AntdException {

    /** The daemon's machine-readable code for this error. */
    public static final String CODE = "POINTER_FINAL";

    /**
     * Creates the exception.
     *
     * @param message the error message from the daemon
     */
    public PointerFinalException(String message) {
        super(409, message);
    }
}
