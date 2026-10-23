<?php

declare(strict_types=1);

namespace Autonomi\Antd;

use Autonomi\Antd\Errors\BadRequestError;
use Autonomi\Antd\Models\BuildManifestOptions;
use Autonomi\Antd\Models\BuiltManifest;
use Autonomi\Antd\Models\DecodedManifest;
use Autonomi\Antd\Models\ManifestEntryInfo;
use Autonomi\Antd\Models\ManifestEntryInput;
use GuzzleHttp\Promise\PromiseInterface;

/**
 * Manifests (ADR-0006): `.ant` files and `ant://` links that describe a set
 * of files, each with an optional path and size and either an embedded
 * DataMap or a public DataMap address. The daemon builds and decodes them
 * through ant-core, so callers never re-implement the format.
 *
 * Nothing is uploaded or paid for: build the manifest from DataMaps and
 * addresses already in hand (`dataPut()`, `dataPutPublic()`, `filePut()`,
 * `filePutPublic()`), then share its bytes or its link. Building (with root
 * embedding, the default) and a resolving decode read from the network, so
 * they can time out; any of these calls is safe to retry.
 *
 * The `.ant` bytes are raw PHP strings in and out; the base64 the REST API
 * carries them in never reaches the caller. Sizes are ints, and an unset
 * size is null, never 0.
 *
 * Mixed into {@see AntdClient} (it uses the client's private doJson() and
 * doJsonAsync()). Needs antd 0.16.0 or later.
 */
trait ManifestMethods
{
    /** The daemon's 400 text for a decode with neither bytes nor a link. */
    private const MANIFEST_INPUT_MISSING = 'needs a manifest (base64 .ant bytes) or a link';

    /**
     * Build a `.ant` manifest via `POST /v1/manifests/build`.
     *
     * Each entry must set exactly one of `dataMap` or `address`, and a size
     * must not be negative; a bad entry throws a {@see BadRequestError}
     * before anything is sent, worded as the daemon's 400 is (every bad
     * entry named as `entries[i]: ...`). The daemon checks the rest (hex,
     * portable paths, colliding names) the same way.
     *
     * @param list<ManifestEntryInput> $entries
     * @param BuildManifestOptions|null $options Null: the daemon's defaults (root embedding on).
     * @throws BadRequestError for an entry with both or neither of dataMap and address.
     * @throws BadRequestError for an entry the daemon refuses.
     * @throws \Autonomi\Antd\Errors\NotFoundError when a shrunk DataMap's wrapper records are not on the network.
     */
    public function buildManifest(array $entries, ?BuildManifestOptions $options = null): BuiltManifest
    {
        return self::parseBuiltManifest(
            $this->doJson('POST', '/v1/manifests/build', self::manifestBuildBody($entries, $options)),
        );
    }

    /**
     * Async: build a `.ant` manifest. The entries are checked before the
     * promise is returned, so a malformed entry throws synchronously.
     *
     * @param list<ManifestEntryInput> $entries
     * @return PromiseInterface<BuiltManifest>
     * @throws BadRequestError for an entry with both or neither of dataMap and address.
     */
    public function buildManifestAsync(array $entries, ?BuildManifestOptions $options = null): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/manifests/build', self::manifestBuildBody($entries, $options))->then(
            fn(?array $json) => self::parseBuiltManifest($json),
        );
    }

    /**
     * Decode `.ant` bytes via `POST /v1/manifests/decode`.
     *
     * With `$resolve`, the daemon fetches each entry's DataMap (and wrapper
     * records) to report `exactSize` and confirm the DataMap is on the
     * network; content chunks are not fetched, and one entry's failure is
     * reported in its `error`, not as a failed call.
     *
     * @param string $manifest The raw `.ant` bytes.
     * @throws BadRequestError if `$manifest` is empty.
     * @throws BadRequestError if the bytes are not a manifest.
     */
    public function decodeManifest(string $manifest, bool $resolve = false): DecodedManifest
    {
        return self::parseDecodedManifest(
            $this->doJson('POST', '/v1/manifests/decode', self::manifestDecodeBytesBody($manifest, $resolve)),
        );
    }

    /**
     * Async: decode `.ant` bytes. An empty `$manifest` throws synchronously.
     *
     * @return PromiseInterface<DecodedManifest>
     * @throws BadRequestError if `$manifest` is empty.
     */
    public function decodeManifestAsync(string $manifest, bool $resolve = false): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/manifests/decode', self::manifestDecodeBytesBody($manifest, $resolve))->then(
            fn(?array $json) => self::parseDecodedManifest($json),
        );
    }

    /**
     * Decode an `ant://` manifest link, file link or bare 64-hex address via
     * `POST /v1/manifests/decode`. A file link or address reads as
     * `source: "file_link"` with one public entry and no path. See
     * {@see decodeManifest()} for `$resolve`.
     *
     * @throws BadRequestError if `$link` is empty.
     * @throws BadRequestError if `$link` is not a link or address.
     */
    public function decodeManifestLink(string $link, bool $resolve = false): DecodedManifest
    {
        return self::parseDecodedManifest(
            $this->doJson('POST', '/v1/manifests/decode', self::manifestDecodeLinkBody($link, $resolve)),
        );
    }

    /**
     * Async: decode an `ant://` link or bare address. An empty `$link`
     * throws synchronously.
     *
     * @return PromiseInterface<DecodedManifest>
     * @throws BadRequestError if `$link` is empty.
     */
    public function decodeManifestLinkAsync(string $link, bool $resolve = false): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/manifests/decode', self::manifestDecodeLinkBody($link, $resolve))->then(
            fn(?array $json) => self::parseDecodedManifest($json),
        );
    }

    // --- Manifest request bodies ---

    /**
     * The JSON body for `POST /v1/manifests/build`. `embed_roots` is always
     * sent; unset fields are left out.
     *
     * @param array<mixed> $entries
     * @return array<string, mixed>
     * @throws BadRequestError
     */
    private static function manifestBuildBody(array $entries, ?BuildManifestOptions $options): array
    {
        $options ??= new BuildManifestOptions();
        $wire = [];
        $errors = [];
        foreach (array_values($entries) as $i => $entry) {
            if (!$entry instanceof ManifestEntryInput) {
                $errors[] = "entries[{$i}]: not a ManifestEntryInput";
                continue;
            }
            // An empty string is "not given", as the daemon reads it.
            $hasDataMap = $entry->dataMap !== null && $entry->dataMap !== '';
            $hasAddress = $entry->address !== null && $entry->address !== '';
            if ($hasDataMap && $hasAddress) {
                $errors[] = "entries[{$i}]: give data_map or address, not both";
                continue;
            }
            if (!$hasDataMap && !$hasAddress) {
                $errors[] = "entries[{$i}]: needs a data_map or an address";
                continue;
            }
            if ($entry->size !== null && $entry->size < 0) {
                $errors[] = "entries[{$i}]: size must not be negative";
                continue;
            }
            $item = [];
            if ($entry->path !== null && $entry->path !== '') {
                $item['path'] = $entry->path;
            }
            if ($entry->size !== null) {
                $item['size'] = $entry->size;
            }
            if ($hasDataMap) {
                $item['data_map'] = $entry->dataMap;
            } else {
                $item['address'] = $entry->address;
            }
            $wire[] = $item;
        }
        if ($errors !== []) {
            // The daemon's wording (antd/src/manifests.rs entry_errors_message):
            // every bad entry, at most 20 shown.
            $shown = implode('; ', array_slice($errors, 0, 20));
            $more = count($errors) > 20 ? '; and ' . (count($errors) - 20) . ' more' : '';
            throw new BadRequestError(count($errors) . " invalid entries: {$shown}{$more}");
        }
        $body = ['entries' => $wire, 'embed_roots' => $options->embedRoots];
        if ($options->name !== null && $options->name !== '') {
            $body['name'] = $options->name;
        }
        if ($options->torrentInfoHashes !== []) {
            $body['torrent_info_hashes'] = array_values($options->torrentInfoHashes);
        }
        return $body;
    }

    /**
     * @return array<string, string|bool>
     * @throws BadRequestError
     */
    private static function manifestDecodeBytesBody(string $manifest, bool $resolve): array
    {
        if ($manifest === '') {
            throw new BadRequestError(self::MANIFEST_INPUT_MISSING);
        }
        return ['manifest' => base64_encode($manifest), 'resolve' => $resolve];
    }

    /**
     * @return array<string, string|bool>
     * @throws BadRequestError
     */
    private static function manifestDecodeLinkBody(string $link, bool $resolve): array
    {
        if ($link === '') {
            throw new BadRequestError(self::MANIFEST_INPUT_MISSING);
        }
        return ['link' => $link, 'resolve' => $resolve];
    }

    // --- Manifest parsing helpers ---
    //
    // Fields are read strictly: a value of the wrong JSON type reads as the
    // field's empty value ('' for a required string, null for an optional
    // one). A size is an int only when the JSON holds a non-negative
    // integer; absent or null reads as null, never 0.

    /**
     * @param array<mixed>|null $json
     * @throws \UnexpectedValueException if the manifest is not valid base64.
     */
    private static function parseBuiltManifest(?array $json): BuiltManifest
    {
        $json ??= [];
        $raw = base64_decode(self::manifestStr($json, 'manifest'), true);
        if ($raw === false) {
            throw new \UnexpectedValueException('buildManifest: the daemon\'s manifest is not valid base64');
        }
        return new BuiltManifest(
            manifest: $raw,
            link: self::manifestOptStr($json, 'link'),
            entries: self::parseManifestEntries($json['entries'] ?? null),
        );
    }

    /**
     * @param array<mixed>|null $json
     */
    private static function parseDecodedManifest(?array $json): DecodedManifest
    {
        $json ??= [];
        return new DecodedManifest(
            source: self::manifestStr($json, 'source'),
            name: self::manifestOptStr($json, 'name'),
            torrentInfoHashV1: self::manifestOptStr($json, 'torrent_info_hash_v1'),
            torrentInfoHashV2: self::manifestOptStr($json, 'torrent_info_hash_v2'),
            entries: self::parseManifestEntries($json['entries'] ?? null),
        );
    }

    /**
     * @return list<ManifestEntryInfo>
     */
    private static function parseManifestEntries(mixed $raw): array
    {
        $out = [];
        foreach (is_array($raw) ? $raw : [] as $e) {
            if (!is_array($e)) {
                continue;
            }
            $out[] = new ManifestEntryInfo(
                effectiveName: self::manifestStr($e, 'effective_name'),
                path: self::manifestOptStr($e, 'path'),
                size: self::manifestOptSize($e, 'size'),
                kind: self::manifestStr($e, 'kind'),
                contentAddress: self::manifestStr($e, 'content_address'),
                dataMap: self::manifestOptStr($e, 'data_map'),
                exactSize: self::manifestOptSize($e, 'exact_size'),
                error: self::manifestOptStr($e, 'error'),
            );
        }
        return $out;
    }

    /** @param array<mixed> $json */
    private static function manifestStr(array $json, string $key): string
    {
        $value = $json[$key] ?? null;
        return is_string($value) ? $value : '';
    }

    /**
     * An optional string: null when absent, null (REST's unset) or empty.
     *
     * @param array<mixed> $json
     */
    private static function manifestOptStr(array $json, string $key): ?string
    {
        $value = $json[$key] ?? null;
        return is_string($value) && $value !== '' ? $value : null;
    }

    /**
     * An optional size: the value when it is a JSON non-negative integer,
     * otherwise null. REST leaves an unset size out, and that must never
     * read as 0.
     *
     * @param array<mixed> $json
     */
    private static function manifestOptSize(array $json, string $key): ?int
    {
        $value = $json[$key] ?? null;
        return is_int($value) && $value >= 0 ? $value : null;
    }
}
