<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Result of preparing a single-chunk external-signer publish via
 * POST /v1/chunks/prepare.
 *
 * When `alreadyStored` is true, the chunk is already on-network and no
 * payment / finalize call is required — `address` is still populated but
 * the payment fields are empty strings / empty list. Otherwise the
 * wave-batch payment fields describe what the external signer must submit
 * before calling finalizeChunkUpload().
 *
 * Requires antd >= 0.7.0.
 */
readonly class PrepareChunkResult
{
    public function __construct(
        /** Content-addressed BLAKE3 of the chunk bytes (hex, 64 chars). Always set. */
        public string $address,
        /** True if the chunk is already stored on the network — no payment needed. */
        public bool $alreadyStored,
        /** Opaque identifier to pass back to finalizeChunkUpload(). Empty when alreadyStored. */
        public string $uploadId,
        /** Always "wave_batch" for single-chunk publishes. Empty when alreadyStored. */
        public string $paymentType,
        /** @var list<PaymentInfo> Per-quote payments. Empty when alreadyStored. */
        public array $payments,
        /** Total atto-token amount across all payments. Empty when alreadyStored. */
        public string $totalAmount,
        /** Payment vault contract address (hex with 0x prefix). Empty when alreadyStored. */
        public string $paymentVaultAddress,
        /** Payment token contract address (hex with 0x prefix). Empty when alreadyStored. */
        public string $paymentTokenAddress,
        /** EVM RPC URL for submitting payment transactions. Empty when alreadyStored. */
        public string $rpcUrl,
    ) {}
}
