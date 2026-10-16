<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Whose pointer decides what an address resolves to, after following every
 * transfer (`pointerController()`).
 */
readonly class PointerController
{
    public function __construct(
        /** The pointer whose owner now decides (hex). */
        public string $pointer,
        /** @var list<string> Every pointer the address was handed over to, in order. */
        public array $transfers,
        /** `$pointer` is final without being handed over: nobody can move it. */
        public bool $frozen,
    ) {}
}
