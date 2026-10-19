<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * A pointer's current state, as the network serves it (`pointerGet()`).
 */
readonly class PointerRecord
{
    public function __construct(
        /** The pointer's address (hex, no prefix). */
        public string $address,
        /**
         * The owner's ML-DSA-65 public key (hex, 1,952 bytes). The address is
         * derived from it, so it is the proof of who owns the pointer.
         */
        public string $owner,
        /**
         * The state's counter, as a canonical decimal string. A final state
         * sits at {@see PointerCounter::FINAL} (2^64 - 1).
         */
        public string $counter,
        /** `"chunk"`, `"pointer"`, or `"unknown"` for a kind the daemon does not know. */
        public string $kind,
        /** The raw target kind tag (0 chunk, 1 pointer); 255 if the daemon sent none. */
        public int $kindTag,
        /** The address the pointer points at (hex). */
        public string $target,
        /** The state's identifier (hex). */
        public string $stateId,
        /**
         * The state is at the final counter: the pointer was handed over or
         * frozen, and nothing can replace it. (`is_final` on the wire;
         * `final` is a reserved word in PHP.)
         */
        public bool $isFinal,
        /** The pointer this one was handed over to, when its final state is a transfer; otherwise null. */
        public ?string $transferredTo,
    ) {}

    /** The target's kind, or null if this SDK does not know its tag. */
    public function targetKind(): ?PointerTargetKind
    {
        return PointerTargetKind::fromTag($this->kindTag);
    }
}
