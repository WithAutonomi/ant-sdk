<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Result of a private data put. The DataMap is returned to the caller; it
 * is NOT stored on-network.
 */
readonly class DataPutResult
{
    public function __construct(
        /** Hex-encoded caller-held DataMap. */
        public string $dataMap,
        /** Number of chunks stored on the network. */
        public int $chunksStored,
        /** Which payment mode was actually used: "auto", "merkle", or "single". */
        public string $paymentModeUsed,
    ) {}
}
