<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * The result of `decodeManifest()` and `decodeManifestLink()`.
 */
readonly class DecodedManifest
{
    /**
     * @param list<ManifestEntryInfo> $entries
     */
    public function __construct(
        /**
         * `"manifest"`, or `"file_link"` for a file link or bare address
         * (reported as one public entry with no path).
         */
        public string $source,
        /** The suggested root directory name; null when there is none. */
        public ?string $name,
        /** The BitTorrent v1 info hash (hex); null when there is none. */
        public ?string $torrentInfoHashV1,
        /** The BitTorrent v2 info hash (hex); null when there is none. */
        public ?string $torrentInfoHashV2,
        /** In encoded order (sorted by effective name). */
        public array $entries,
    ) {}
}
