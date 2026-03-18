<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

readonly class PutResult
{
    public function __construct(
        public string $cost,
        public string $address,
    ) {}
}
