<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Pointer counters, kept as validated decimal strings.
 *
 * A pointer's counter is an unsigned 64-bit integer, and a final state (a
 * transfer or a freeze) sits at 2^64 - 1. PHP's `int` is signed 64-bit, so it
 * cannot hold that value, and a float would round it. The daemon sends
 * counters as decimal strings for exactly this reason, and this SDK keeps
 * them that way: every counter is a canonical decimal string (digits only, no
 * sign, no leading zeros) within the u64 range, checked by {@see parse()}.
 * No GMP or BCMath is needed. Compare two counters for equality with `===`;
 * for ordering, compare lengths first, then the strings.
 */
final class PointerCounter
{
    /** The counter of a pointer's final state (2^64 - 1): nothing can replace it. */
    public const FINAL = '18446744073709551615';

    private function __construct()
    {
    }

    /**
     * Validate a counter the daemon sent and return it in canonical form.
     *
     * Accepts only a string of ASCII digits whose value fits a u64. A JSON
     * number, an empty string, a sign, a fraction, whitespace or a value past
     * 2^64 - 1 is rejected, never read as 0.
     *
     * @param mixed $value The decoded JSON value.
     * @param string $field The field name, for the error message.
     * @throws \UnexpectedValueException when the value is not a decimal u64.
     */
    public static function parse(mixed $value, string $field = 'counter'): string
    {
        if (is_string($value) && preg_match('/\A[0-9]+\z/', $value) === 1) {
            $digits = ltrim($value, '0');
            if ($digits === '') {
                return '0';
            }
            $len = strlen($digits);
            if ($len < 20 || ($len === 20 && strcmp($digits, self::FINAL) <= 0)) {
                return $digits;
            }
        }
        throw new \UnexpectedValueException(sprintf(
            'antd: pointer %s %s is not a decimal u64 counter',
            $field,
            is_string($value) ? '"' . $value . '"' : get_debug_type($value),
        ));
    }
}
