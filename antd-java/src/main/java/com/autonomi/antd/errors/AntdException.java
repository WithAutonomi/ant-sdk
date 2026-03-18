package com.autonomi.antd.errors;

/**
 * Base exception type for all antd daemon errors.
 */
public class AntdException extends RuntimeException {

    private final int statusCode;

    public AntdException(int statusCode, String message) {
        super("antd error " + statusCode + ": " + message);
        this.statusCode = statusCode;
    }

    /** Returns the HTTP status code from the daemon response. */
    public int getStatusCode() {
        return statusCode;
    }
}
