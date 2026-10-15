<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * What a pointer points at. The backing string is the wire value the daemon
 * accepts as `kind`.
 *
 * - {@link self::Chunk}   — an immutable chunk, such as a public file's or
 *   public data's data map. The daemon's default when no kind is sent.
 * - {@link self::Pointer} — another pointer: a forwarding the owner can still
 *   change. Use `pointerTransfer()` to hand a pointer over for good.
 */
enum PointerTargetKind: string
{
    case Chunk = 'chunk';
    case Pointer = 'pointer';

    /** The kind a raw `kind_tag` names (0 chunk, 1 pointer), or null for one this SDK does not know. */
    public static function fromTag(int $tag): ?self
    {
        return match ($tag) {
            0 => self::Chunk,
            1 => self::Pointer,
            default => null,
        };
    }
}
