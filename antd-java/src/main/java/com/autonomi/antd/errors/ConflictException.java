package com.autonomi.antd.errors;

/**
 * The request conflicts with the resource's current state (HTTP 409 with
 * {@code code: "CONFLICT"}; gRPC {@code ABORTED} with
 * {@code x-antd-error-code: CONFLICT}). For pointers: a write while a prepared
 * write to the same pointer awaits payment (finalize it, or wait for it to
 * expire), or an update that lost to a newer state while it was in flight.
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
