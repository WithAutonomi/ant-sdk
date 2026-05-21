<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Result of a private file upload. The DataMap is returned to the caller;
 * it is NOT stored on-network.
 */
readonly class FilePutResult
{
    public function __construct(
        /** Hex-encoded caller-held DataMap. */
        public string $dataMap,
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
