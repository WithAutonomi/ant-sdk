package com.autonomi.antd.models;

import java.util.List;

/**
 * Result of preparing an upload for external signing.
 * PaymentType is "wave_batch" or "merkle" — determines which fields are populated
 * and which contract call the external signer must make.
 *
 * @param uploadId               hex identifier for this upload session
 * @param paymentType            "wave_batch" or "merkle"
 * @param payments               per-quote payments for payForQuotes() (wave_batch only)
 * @param totalAmount            total atto tokens ("0" for merkle)
 * @param paymentVaultAddress     payment vault contract address
 * @param paymentTokenAddress    payment token contract address
 * @param rpcUrl                 EVM RPC URL for submitting transactions
 * @param depth                  merkle tree depth 1-8 (merkle only)
 * @param poolCommitments        pool commitments for payForMerkleTree() (merkle only)
 * @param merklePaymentTimestamp unix seconds timestamp (merkle only)
 * @param totalChunks            total chunks incl. already-stored (added in antd 0.10.0; 0 on older daemons)
 * @param alreadyStoredCount     chunks already on-network, excluded from payment (added in antd 0.10.0)
 */
public record PrepareUploadResult(
        String uploadId,
        String paymentType,
        List<PaymentInfo> payments,
        String totalAmount,
        String paymentVaultAddress,
        String paymentTokenAddress,
        String rpcUrl,
        Integer depth,
        List<PoolCommitmentEntry> poolCommitments,
        Long merklePaymentTimestamp,
        long totalChunks,
        long alreadyStoredCount) {}
