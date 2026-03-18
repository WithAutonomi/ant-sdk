<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

readonly class HealthStatus
{
    public function __construct(
        public bool $ok,
        public string $network,
    ) {}
}
