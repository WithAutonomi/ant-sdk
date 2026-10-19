<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/**
 * The request conflicts with the resource's current state (HTTP 409 with
 * `code: "CONFLICT"`), such as a pointer write while a prepared write to the
 * same pointer awaits payment. It clears once that prepared write is
 * finalized or expires.
 *
 * Extends {@see AntdError} directly, not {@see AlreadyExistsError}: it
 * shares the 409 status but means something else.
 */
class ConflictError extends AntdError
{
    public function __construct(string $message, int $statusCode = 409)
    {
        parent::__construct($statusCode, $message);
    }
}
