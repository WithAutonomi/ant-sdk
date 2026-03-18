<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

readonly class GraphEntry
{
    /**
     * @param string $owner
     * @param string[] $parents
     * @param string $content
     * @param GraphDescendant[] $descendants
     */
    public function __construct(
        public string $owner,
        public array $parents,
        public string $content,
        public array $descendants,
    ) {}
}
