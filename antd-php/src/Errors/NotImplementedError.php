<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/** Indicates the operation is not implemented by the daemon (HTTP 501). */
class NotImplementedError extends AntdError
{
    public function __construct(string $message)
    {
        parent::__construct(501, $message);
    }
}
