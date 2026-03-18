<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

/** Indicates insufficient funds or payment failure (HTTP 402). */
class PaymentError extends AntdError
{
    public function __construct(string $message)
    {
        parent::__construct(402, $message);
    }
}
