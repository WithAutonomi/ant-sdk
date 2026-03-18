package com.autonomi.antd.errors;

/** Internal server error (HTTP 500). */
public class InternalException extends AntdException {
    public InternalException(String message) {
        super(500, message);
    }
}
