package com.autonomi.antd.errors;

/** Resource already exists (HTTP 409). */
public class AlreadyExistsException extends AntdException {
    public AlreadyExistsException(String message) {
        super(409, message);
    }
}
