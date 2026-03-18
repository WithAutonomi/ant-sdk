<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

readonly class ArchiveEntry
{
    public function __construct(
        public string $path,
        public string $address,
        public int $created,
        public int $modified,
        public int $size,
    ) {}
}
