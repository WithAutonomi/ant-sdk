<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/** Indicates the service is unavailable, e.g. wallet not configured (HTTP 503). */
class ServiceUnavailableError extends AntdError
{
    public function __construct(string $message)
    {
        parent::__construct(503, $message);
    }
}
