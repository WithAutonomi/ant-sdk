<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Result of preparing an upload (file or in-memory data) for external signing.
 *
 * Returned by AntdClient::prepareUpload() and AntdClient::prepareDataUpload()
 * (and their Async variants). Wave-batch shape only — merkle support can be
 * added later if/when needed.
 */
readonly class PrepareUploadResult
{
    public function __construct(
        /** Opaque server-side identifier to pass back to finalizeUpload(). */
        public string $uploadId,
        /** "wave_batch" for the only mode currently exposed by this PHP client. */
        public string $paymentType,
        /** @var list<PaymentInfo> Per-quote payments the external signer must submit. */
        public array $payments,
        /** Total atto-token amount across all entries in $payments. */
        public string $totalAmount,
        /** Payment vault contract address (hex with 0x prefix). */
        public string $paymentVaultAddress,
        /** Payment token contract address (hex with 0x prefix). */
        public string $paymentTokenAddress,
        /** EVM RPC URL the external signer should submit transactions through. */
        public string $rpcUrl,
        /**
         * Total chunks in this upload, including any already on-network.
         * Added in antd 0.10.0; 0 against older daemons. The external signer
         * pays for ($totalChunks - $alreadyStoredCount) chunks.
         */
        public int $totalChunks = 0,
        /** Chunks already stored on-network and excluded from payment + PUT (added in antd 0.10.0). */
        public int $alreadyStoredCount = 0,
    ) {}
}
