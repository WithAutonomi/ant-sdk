<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/** Indicates the resource already exists (HTTP 409). */
class AlreadyExistsError extends AntdError
{
    public function __construct(string $message)
    {
        parent::__construct(409, $message);
    }
}
