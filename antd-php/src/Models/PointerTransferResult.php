<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * What a transfer stored, and where the close group says it stands
 * (`pointerTransfer()`).
 */
readonly class PointerTransferResult
{
    public function __construct(
        /** The transferred pointer's address (hex). */
        public string $address,
        /** The final state's identifier (hex). */
        public string $stateId,
        /**
         * The close group's view once the write landed. Null when that check
         * failed ({@see $finalityError} says why), which does not undo the
         * transfer: it is stored and final. Ask again with `pointerFinality()`.
         */
        public ?PointerFinality $finality,
        /** Why the finality check failed, when {@see $finality} is null. */
        public ?string $finalityError,
    ) {}
}
