<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * The optional parts of a `buildManifest()` call. `new BuildManifestOptions()`
 * (or passing no options at all) gives the daemon's defaults.
 */
readonly class BuildManifestOptions
{
    /**
     * @param list<string> $torrentInfoHashes
     */
    public function __construct(
        /** A suggested root directory name (one portable path component). Null or empty: none. */
        public ?string $name = null,
        /**
         * BitTorrent info hashes of the same files: hex, 40 characters for v1
         * and/or 64 for v2.
         */
        public array $torrentInfoHashes = [],
        /**
         * Resolve each shrunk DataMap's root (fetching its wrapper records)
         * and embed the root when it is at most 64 KiB, so recipients skip
         * that fetch (ADR-0006's policy). This is the default; false embeds
         * shrunk DataMaps exactly as given and skips the network.
         */
        public bool $embedRoots = true,
    ) {}
}
