<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/** Indicates the payload is too large (HTTP 413). */
class TooLargeError extends AntdError
{
    public function __construct(string $message)
    {
        parent::__construct(413, $message);
    }
}
