<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Payment-batching strategy for uploads.
 *
 * - {@link self::Auto}   — server picks (merkle for 64+ chunks, single otherwise).
 * - {@link self::Merkle} — force merkle-batch (saves gas, min 2 chunks).
 * - {@link self::Single} — force per-chunk payments (works for any chunk count).
 *
 * The backing string is the exact wire-format the daemon accepts; pass via
 * the `paymentMode` argument on put/cost methods.
 */
enum PaymentMode: string
{
    case Auto = 'auto';
    case Merkle = 'merkle';
    case Single = 'single';
}
