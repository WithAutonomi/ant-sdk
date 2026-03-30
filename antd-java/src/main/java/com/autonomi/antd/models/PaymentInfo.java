package com.autonomi.antd.models;

/**
 * A single payment required for an upload.
 *
 * @param quoteHash      hex-encoded quote hash
 * @param rewardsAddress hex-encoded rewards address
 * @param amount         amount in atto tokens as string
 */
public record PaymentInfo(String quoteHash, String rewardsAddress, String amount) {}
