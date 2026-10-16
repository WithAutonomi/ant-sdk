<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * What a manifest says about one entry (`buildManifest()`,
 * `decodeManifest()`, `decodeManifestLink()`). Optional fields the daemon
 * leaves out read as null, never as 0 or an empty string.
 */
readonly class ManifestEntryInfo
{
    public function __construct(
        /** `path`, or the content address in hex when there is none. */
        public string $effectiveName,
        /** The relative path the entry extracts under; null when there is none. */
        public ?string $path,
        /** The size recorded in the manifest (the creator's claim); null when none was recorded. */
        public ?int $size,
        /** `"embedded"` or `"public"`. */
        public string $kind,
        /**
         * The file's public DataMap address (hex), whether or not it was ever
         * made public; the same for private and public uploads of one file.
         */
        public string $contentAddress,
        /**
         * The embedded DataMap in the hex form `dataGet()` and `fileGet()`
         * accept. Decode only; null for public entries and on build.
         */
        public ?string $dataMap,
        /**
         * The exact plaintext size: from an embedded root DataMap, or after a
         * resolving decode. Null when it is not known.
         */
        public ?int $exactSize,
        /** Why a resolving decode failed for this entry; null when it did not. */
        public ?string $error,
    ) {}
}
