package com.autonomi.antd.models;

import java.util.List;

/**
 * Result of preparing a single-chunk publish for external signing via
 * {@code POST /v1/chunks/prepare}.
 *
 * <p>When {@link #alreadyStored} is {@code true}, the chunk is already
 * on-network — only {@link #address} and {@link #alreadyStored} are
 * populated, and no finalize call is needed. Otherwise the wave-batch payment
 * fields describe what the external signer must submit before calling
 * {@code finalizeChunkUpload}.
 *
 * <p>Requires antd &gt;= 0.7.0.
 *
 * @param address             content-addressed BLAKE3 of the chunk bytes
 *                            (hex, 64 chars). Always set.
 * @param alreadyStored       {@code true} if the chunk is already stored and
 *                            no payment is needed.
 * @param uploadId            opaque identifier to pass back to finalize.
 *                            Empty when {@code alreadyStored == true}.
 * @param paymentType         always {@code "wave_batch"} for single-chunk
 *                            publishes. Empty when {@code alreadyStored}.
 * @param payments            per-quote payment entries for
 *                            {@code payForQuotes()}. Typically 5–7 (one per
 *                            peer in the close group). Empty when
 *                            {@code alreadyStored}.
 * @param totalAmount         total amount to pay (atto tokens, decimal
 *                            string). Empty when {@code alreadyStored}.
 * @param paymentVaultAddress payment vault contract address. Empty when
 *                            {@code alreadyStored}.
 * @param paymentTokenAddress payment token contract address. Empty when
 *                            {@code alreadyStored}.
 * @param rpcUrl              EVM RPC URL for submitting transactions. Empty
 *                            when {@code alreadyStored}.
 */
public record PrepareChunkResult(
        String address,
        boolean alreadyStored,
        String uploadId,
        String paymentType,
        List<PaymentInfo> payments,
        String totalAmount,
        String paymentVaultAddress,
        String paymentTokenAddress,
        String rpcUrl) {}
