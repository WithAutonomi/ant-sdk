<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * The result of `buildManifest()`.
 */
readonly class BuiltManifest
{
    /**
     * @param list<ManifestEntryInfo> $entries
     */
    public function __construct(
        /** The `.ant` bytes, raw (the SDK decodes the daemon's base64). */
        public string $manifest,
        /**
         * The `ant://manifest/` link; null when it does not fit the
         * recommended 1,500 bytes (share the `.ant` bytes instead).
         */
        public ?string $link,
        /** In encoded order (sorted by effective name). */
        public array $entries,
    ) {}
}
