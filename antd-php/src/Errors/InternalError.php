<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/** Indicates an internal server error (HTTP 500). */
class InternalError extends AntdError
{
    public function __construct(string $message)
    {
        parent::__construct(500, $message);
    }
}
