package com.autonomi.antd.errors;

/** Insufficient funds or payment failure (HTTP 402). */
public class PaymentException extends AntdException {
    public PaymentException(String message) {
        super(402, message);
    }
}
