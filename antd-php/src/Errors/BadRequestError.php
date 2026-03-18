<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/** Indicates invalid request parameters (HTTP 400). */
class BadRequestError extends AntdError
{
    public function __construct(string $message)
    {
        parent::__construct(400, $message);
    }
}
