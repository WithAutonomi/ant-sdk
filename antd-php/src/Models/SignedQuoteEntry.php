<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * One `payments` quote in full signed form, returned when a prepare asks for
 * signed quotes (`includeSignedQuotes`). Both payloads are base64 and opaque:
 * only antd parses them.
 */
readonly class SignedQuoteEntry
{
    public function __construct(
        /** Hex (0x-prefixed) quote hash; matches the {@see PaymentInfo} entry. */
        public string $quoteHash,
        /** base64 of the msgpack-serialized signed PaymentQuote. */
        public string $quote,
        /** base64 of the msgpack-serialized StorageCommitment the quote pins; null for baseline quotes. */
        public ?string $commitmentSidecar = null,
    ) {}
}
