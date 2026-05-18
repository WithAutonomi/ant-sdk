<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * A single payment required for an upload (one entry in a wave-batch).
 *
 * Quote hashes and rewards addresses are returned as hex strings with the
 * "0x" prefix; the amount is a decimal string in atto token units.
 */
readonly class PaymentInfo
{
    public function __construct(
        /** Hex (0x-prefixed) quote hash from the close-group quote. */
        public string $quoteHash,
        /** Hex (0x-prefixed) rewards address of the peer receiving payment. */
        public string $rewardsAddress,
        /** Atto-token amount as a decimal string. */
        public string $amount,
    ) {}
}
