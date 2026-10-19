<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Where a pointer stands with respect to finality, as its whole close group
 * reports it. The backing string is the daemon's wire value.
 *
 * {@link self::Unknown} is a status this SDK does not know, which a newer
 * daemon may send; {@see PointerFinality::$rawStatus} keeps the wire string.
 * Give a `match` on this enum a `default` arm for it.
 */
enum PointerFinalityStatus: string
{
    /**
     * No peer that answered holds a final state: the owner can still move
     * the pointer. Rules a final state out only when every peer answered.
     */
    case Open = 'open';
    /** One final state, not yet held by a majority: a transfer still spreading, or a write that fell short. */
    case Settling = 'settling';
    /** One final state held by a majority, but not every peer answered, so a rival could still be unseen. Ask again. */
    case Unconfirmed = 'unconfirmed';
    /** One final state held by a majority, every peer answered, no rival. The only status to rely on for a transfer. */
    case Final = 'final';
    /** The owner signed two or more different final states. */
    case Forked = 'forked';
    /** A status this SDK does not know (a newer daemon). */
    case Unknown = 'unknown';

    /** Parse the daemon's wire string; anything unrecognised is {@link self::Unknown}. */
    public static function fromWire(string $status): self
    {
        return self::tryFrom($status) ?? self::Unknown;
    }
}
