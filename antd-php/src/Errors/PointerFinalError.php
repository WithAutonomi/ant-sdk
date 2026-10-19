<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/**
 * The pointer is at its final state: it was handed over (transferred) or
 * frozen, so nothing can update or transfer it again (HTTP 409 with
 * `code: "POINTER_FINAL"`). Usually refused before anything is paid: the
 * daemon reads the pointer first. A write that was already paid for when the
 * network refused it (the pointer became final while the write was in flight)
 * keeps that payment, so read the pointer before paying again.
 *
 * Extends {@see AntdError} directly, not {@see AlreadyExistsError}: it
 * shares the 409 status but means something else.
 */
class PointerFinalError extends AntdError
{
    public function __construct(string $message, int $statusCode = 409)
    {
        parent::__construct($statusCode, $message);
    }
}
