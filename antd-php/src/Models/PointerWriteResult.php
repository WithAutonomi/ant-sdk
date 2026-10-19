<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * The state a pointer write stored (`pointerCreate()` / `pointerUpdate()`).
 */
readonly class PointerWriteResult
{
    public function __construct(
        /** The pointer's address (hex, no prefix). */
        public string $address,
        /** The stored state's identifier (hex): what the write was paid against. */
        public string $stateId,
        /** The state's counter, as a canonical decimal string ({@see PointerCounter}). */
        public string $counter,
    ) {}
}
