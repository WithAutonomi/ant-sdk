package com.autonomi.antd.models;

/**
 * Pre-upload cost breakdown returned by {@code dataCost} and {@code fileCost}.
 *
 * <p>The server samples up to 5 chunk addresses and extrapolates the storage
 * cost. Gas is an advisory heuristic, not a live gas-oracle query.
 *
 * @param cost                 storage cost in atto tokens (string to preserve precision)
 * @param fileSize             original size in bytes
 * @param chunkCount           number of data chunks the file would split into
 * @param estimatedGasCostWei  advisory gas heuristic in wei (string for precision)
 * @param paymentMode          "auto" | "merkle" | "single"
 */
public record UploadCostEstimate(
    String cost,
    long fileSize,
    int chunkCount,
    String estimatedGasCostWei,
    String paymentMode) {}
