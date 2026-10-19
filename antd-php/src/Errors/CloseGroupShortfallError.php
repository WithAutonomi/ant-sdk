<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/**
 * Too few of an address's close group answered, or took a write, for the
 * result to be the network's (HTTP 503 with `code: "CLOSE_GROUP_SHORTFALL"`).
 *
 * Reads are free to retry: a shortfall on a pointer read usually clears once
 * an update in flight settles. A paid write is not, because every attempt
 * pays again, except where {@see $retryable} is `true`: a pointer finalize
 * kept the paid state, and calling `pointerFinalize()` again with the same
 * `upload_id` stores it against the same payment.
 *
 * Not only for pointers: a daemon with the pointer API reports a close group
 * that fell short on any call (a chunk store, say) this way; older daemons
 * sent a plain 500, read as {@see InternalError}.
 *
 * Extends {@see AntdError} directly, not {@see ServiceUnavailableError}:
 * that one means the daemon lacks a dependency such as a wallet, which
 * waiting does not fix.
 */
class CloseGroupShortfallError extends AntdError
{
    /**
     * `true` only when a pointer finalize kept the paid state, so the same
     * `pointerFinalize()` call (same `upload_id`) can store it against the
     * same payment. Read strictly: only the JSON boolean `true` sets it.
     */
    public readonly bool $retryable;

    public function __construct(string $message, bool $retryable = false, int $statusCode = 503)
    {
        $this->retryable = $retryable;
        parent::__construct($statusCode, $message);
    }
}
