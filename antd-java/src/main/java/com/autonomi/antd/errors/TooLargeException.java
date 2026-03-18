package com.autonomi.antd.errors;

/** Payload too large (HTTP 413). */
public class TooLargeException extends AntdException {
    public TooLargeException(String message) {
        super(413, message);
    }
}
