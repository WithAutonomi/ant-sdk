package com.autonomi.antd.errors;

/** Service unavailable, e.g. wallet not configured (HTTP 503). */
public class ServiceUnavailableException extends AntdException {
    public ServiceUnavailableException(String message) {
        super(503, message);
    }
}
