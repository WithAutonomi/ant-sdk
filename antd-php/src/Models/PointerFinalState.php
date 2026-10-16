<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * One final state, as a finality check reports it.
 */
readonly class PointerFinalState
{
    public function __construct(
        /** The state's identifier (hex). */
        public string $stateId,
        /** `"chunk"`, `"pointer"`, or `"unknown"`. */
        public string $kind,
        /** The raw target kind tag; 255 if the daemon sent none. */
        public int $kindTag,
        /** The address the state points at (hex). */
        public string $target,
        /** How many peers of the close group hold it. */
        public int $holders,
        /** The pointer this state hands over to, for a transfer; otherwise null. */
        public ?string $transferredTo,
    ) {}
}
