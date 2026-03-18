<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/** Indicates a version conflict or fork was detected (HTTP 409). */
class ForkError extends AntdError
{
    public function __construct(string $message)
    {
        parent::__construct(409, $message);
    }
}
