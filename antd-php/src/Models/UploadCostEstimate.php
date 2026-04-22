<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Pre-upload cost breakdown returned by {@see AntdClient::dataCost()} and
 * {@see AntdClient::fileCost()}.
 *
 * The server samples up to 5 chunk addresses and extrapolates the storage
 * cost. Gas is an advisory heuristic, not a live gas-oracle query.
 */
readonly class UploadCostEstimate
{
    public function __construct(
        public string $cost,                 // storage cost in atto tokens
        public int $fileSize,                // original file size in bytes
        public int $chunkCount,              // number of data chunks
        public string $estimatedGasCostWei,  // advisory gas heuristic in wei
        public string $paymentMode,          // "auto" | "merkle" | "single"
    ) {}
}
