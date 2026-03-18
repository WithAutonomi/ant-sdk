package com.autonomi.antd.errors;

/** Daemon cannot reach the network (HTTP 502). */
public class NetworkException extends AntdException {
    public NetworkException(String message) {
        super(502, message);
    }
}
