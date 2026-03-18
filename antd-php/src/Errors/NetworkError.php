<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/** Indicates the daemon cannot reach the network (HTTP 502). */
class NetworkError extends AntdError
{
    public function __construct(string $message)
    {
        parent::__construct(502, $message);
    }
}
