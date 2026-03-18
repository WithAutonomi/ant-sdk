<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

readonly class Archive
{
    /**
     * @param ArchiveEntry[] $entries
     */
    public function __construct(
        public array $entries,
    ) {}
}
