<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Where a chain of pointers ends (`pointerResolve()`).
 */
readonly class PointerTarget
{
    public function __construct(
        /** `"chunk"`, or `"unknown"` for a target kind the daemon does not know. */
        public string $kind,
        /** The raw target kind tag; 255 if the daemon sent none. */
        public int $kindTag,
        /** The address at the end of the chain (hex). */
        public string $target,
    ) {}

    /** The target's kind, or null if this SDK does not know its tag. */
    public function targetKind(): ?PointerTargetKind
    {
        return PointerTargetKind::fromTag($this->kindTag);
    }
}
