<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * One file for `buildManifest()`. Set exactly one of `$dataMap` (the entry
 * embeds it) or `$address` (a public file); `buildManifest()` refuses an
 * entry with both or neither before sending anything.
 *
 *     new ManifestEntryInput(address: $public->address, path: 'notes/one.txt');
 *     new ManifestEntryInput(dataMap: $private->dataMap, path: 'secret.bin', size: 82);
 */
readonly class ManifestEntryInput
{
    public function __construct(
        /**
         * The relative path the entry extracts under, subject to the portable
         * path rules (the daemon refuses `../x`, absolute paths and the like).
         * Null or empty: it extracts under its content address.
         */
        public ?string $path = null,
        /**
         * The plaintext size to record, as given (the creator's claim). Null:
         * none is recorded, and readers take the exact size from an embedded
         * root DataMap. Never sent as 0 in place of null.
         */
        public ?int $size = null,
        /**
         * A hex DataMap, as `dataPut()` and `filePut()` return it. The entry
         * embeds it: the manifest is the key to the file.
         */
        public ?string $dataMap = null,
        /** A public file's DataMap address (hex, 32 bytes). */
        public ?string $address = null,
    ) {}
}
