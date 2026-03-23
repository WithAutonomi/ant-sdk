package com.autonomi.antd.errors;

/** Feature not implemented by the daemon (HTTP 501). */
public class NotImplementedByServerException extends AntdException {
    public NotImplementedByServerException(String message) {
        super(501, message);
    }
}
