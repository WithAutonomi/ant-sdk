<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Result of a public data put. The DataMap is stored on-network as an extra
 * chunk; `$address` is the shareable retrieval handle.
 */
readonly class DataPutPublicResult
{
    public function __construct(
        /** Hex-encoded on-network DataMap address. */
        public string $address,
        /** Number of chunks stored on the network. */
        public int $chunksStored,
        /** Which payment mode was actually used: "auto", "merkle", or "single". */
        public string $paymentModeUsed,
    ) {}
}
