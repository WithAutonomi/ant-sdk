<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/**
 * Indicates a version conflict or fork was detected (HTTP 409).
 *
 * A pointer whose owner signed two different final states, with no majority
 * on either, is reported as a ForkError (`code: "POINTER_FORKED"`).
 */
class ForkError extends AntdError
{
    public function __construct(string $message, int $statusCode = 409)
    {
        parent::__construct($statusCode, $message);
    }
}
