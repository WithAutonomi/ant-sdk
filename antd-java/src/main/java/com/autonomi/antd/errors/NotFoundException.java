package com.autonomi.antd.errors;

/** Resource not found on the network (HTTP 404). */
public class NotFoundException extends AntdException {
    public NotFoundException(String message) {
        super(404, message);
    }
}
