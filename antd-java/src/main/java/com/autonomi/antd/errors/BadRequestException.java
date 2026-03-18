package com.autonomi.antd.errors;

/** Invalid request parameters (HTTP 400). */
public class BadRequestException extends AntdException {
    public BadRequestException(String message) {
        super(400, message);
    }
}
