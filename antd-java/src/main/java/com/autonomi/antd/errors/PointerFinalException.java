package com.autonomi.antd.errors;

/**
 * The pointer is at its final state, transferred or frozen: nothing can update
 * it or hand it over again (HTTP 409 with {@code code: "POINTER_FINAL"}; gRPC
 * {@code FAILED_PRECONDITION} with {@code x-antd-error-code: POINTER_FINAL}).
 * Usually refused before anything is paid: the daemon reads the pointer first.
 * A write that was already paid for when the network refused it (the pointer
 * became final while the write was in flight) keeps that payment, so read the
 * pointer before paying again.
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
