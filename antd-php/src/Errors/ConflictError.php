<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/**
 * The request conflicts with the resource's current state (HTTP 409 with
 * `code: "CONFLICT"`). For pointers, two cases share this code, and it does
 * not say which one happened or whether anything was paid: a write while a
 * prepared write to the same pointer awaits payment is refused before paying
 * (it clears once that prepared write is finalized or expires); an update
 * that lost to a newer state while it was in flight may already have been
 * paid for. Read the pointer again and check what was paid before submitting
 * another paid write.
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
