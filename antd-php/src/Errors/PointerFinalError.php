<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/**
 * The pointer is at its final state: it was handed over (transferred) or
 * frozen, so nothing can update or transfer it again (HTTP 409 with
 * `code: "POINTER_FINAL"`). Refused before anything is paid.
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
