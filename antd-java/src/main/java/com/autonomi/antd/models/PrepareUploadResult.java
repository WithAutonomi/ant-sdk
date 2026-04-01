package com.autonomi.antd.models;

import java.util.List;

/**
 * Result of preparing an upload for external signing.
 *
 * @param uploadId            hex identifier for this upload session
 * @param payments            payments that must be signed externally
 * @param totalAmount         total amount across all payments
 * @param dataPaymentsAddress data payments contract address
 * @param paymentTokenAddress payment token contract address
 * @param rpcUrl              EVM RPC URL for submitting transactions
 */
public record PrepareUploadResult(
        String uploadId,
        List<PaymentInfo> payments,
        String totalAmount,
        String dataPaymentsAddress,
        String paymentTokenAddress,
        String rpcUrl) {}
