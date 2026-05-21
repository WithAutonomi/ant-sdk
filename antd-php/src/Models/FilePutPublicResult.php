<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Result of a public file upload. The DataMap is stored on-network as an
 * extra chunk; `$address` is the shareable retrieval handle.
 */
readonly class FilePutPublicResult
{
    public function __construct(
        /** Hex-encoded on-network DataMap address. */
        public string $address,
        /** Total storage cost paid in token units (atto). "0" if all chunks already existed. */
        public string $storageCostAtto,
        /** Total gas cost paid in wei as a decimal string. */
        public string $gasCostWei,
        /** Number of chunks stored on the network (uint64). */
        public int $chunksStored,
        /** Which payment mode was actually used: "auto", "merkle", or "single". */
        public string $paymentModeUsed,
    ) {}
}
