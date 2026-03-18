package com.autonomi.antd.errors;

/** Version conflict or fork detected (HTTP 409). */
public class ForkException extends AntdException {
    public ForkException(String message) {
        super(409, message);
    }
}
