<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/** Indicates the resource was not found on the network (HTTP 404). */
class NotFoundError extends AntdError
{
    public function __construct(string $message)
    {
        parent::__construct(404, $message);
    }
}
