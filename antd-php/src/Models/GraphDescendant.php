<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

readonly class GraphDescendant
{
    public function __construct(
        public string $publicKey,
        public string $content,
    ) {}
}
