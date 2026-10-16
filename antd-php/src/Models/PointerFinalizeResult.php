<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * The state a pointer finalize stored (`pointerFinalize()`).
 */
readonly class PointerFinalizeResult
{
    public function __construct(
        /** The pointer's address (hex). */
        public string $address,
        /** The stored state's identifier (hex). */
        public string $stateId,
        /** The stored state's counter, as a canonical decimal string ({@see PointerCounter}). */
        public string $counter,
        /** Transfers only: where the close group says the transfer stands; otherwise null. */
        public ?PointerFinality $finality,
    ) {}
}
