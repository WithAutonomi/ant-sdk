package com.autonomi.antd.errors;

/**
 * Version conflict or fork detected (HTTP 409). A pointer whose owner signed
 * two different final states, with no majority of the close group holding
 * either, is reported as a {@code ForkException} (HTTP 409 with
 * {@code code: "POINTER_FORKED"}; gRPC {@code FAILED_PRECONDITION} with
 * {@code x-antd-error-code: POINTER_FORKED}).
 */
public class ForkException extends AntdException {

    /** The daemon's machine-readable code for a forked pointer. */
    public static final String POINTER_FORKED_CODE = "POINTER_FORKED";

    public ForkException(String message) {
        super(409, message);
    }
}
