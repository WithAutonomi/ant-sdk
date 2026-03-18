<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

class AntdError extends \RuntimeException
{
    public readonly int $statusCode;

    public function __construct(int $statusCode, string $message)
    {
        $this->statusCode = $statusCode;
        parent::__construct("antd error {$statusCode}: {$message}", $statusCode);
    }
}
