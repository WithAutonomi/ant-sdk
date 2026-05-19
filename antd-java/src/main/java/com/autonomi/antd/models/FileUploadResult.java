package com.autonomi.antd.models;

/**
 * Result of a public file upload.
 *
 * <p>Returned by {@link com.autonomi.antd.AntdClient#fileUploadPublic(String)} and the equivalent
 * gRPC and async client methods.
 *
 * @param address          hex-encoded network address of the uploaded file
 * @param storageCostAtto  total storage cost paid in token units (atto). "0" if all chunks already existed.
 * @param gasCostWei       total gas cost paid in wei as a decimal string (u128 exceeds JSON safe-integer range).
 * @param chunksStored     number of chunks stored on the network (uint64)
 * @param paymentModeUsed  which payment mode was actually used: "auto", "merkle", or "single"
 */
public record FileUploadResult(
        String address,
        String storageCostAtto,
        String gasCostWei,
        long chunksStored,
        String paymentModeUsed) {}
