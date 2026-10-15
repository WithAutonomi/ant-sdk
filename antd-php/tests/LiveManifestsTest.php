<?php

declare(strict_types=1);

namespace Autonomi\Antd\Tests;

use Autonomi\Antd\AntdClient;
use Autonomi\Antd\Errors\AntdError;
use Autonomi\Antd\Errors\BadRequestError;
use Autonomi\Antd\Models\BuildManifestOptions;
use Autonomi\Antd\Models\BuiltManifest;
use Autonomi\Antd\Models\DecodedManifest;
use Autonomi\Antd\Models\ManifestEntryInfo;
use Autonomi\Antd\Models\ManifestEntryInput;
use PHPUnit\Framework\TestCase;

/**
 * Live manifest round trip against a running antd with a devnet behind it.
 * It builds and decodes manifests of data that is already uploaded, so it
 * makes no paid calls and needs no wallet.
 *
 * Skipped unless both are set:
 *
 *  - `ANTD_TEST_URL` — the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
 *  - `ANTD_TEST_MANIFEST_ADDRESSES` — two comma-separated public data addresses
 *
 * Optional:
 *
 *  - `ANTD_TEST_MANIFEST_SIZES` — the two uploads' exact plaintext sizes
 *  - `ANTD_TEST_MANIFEST_DATA_MAP` / `ANTD_TEST_MANIFEST_DATA_MAP_SIZE` — a
 *    private upload's hex DataMap and its size, added as an embedded entry
 *  - `ANTD_TEST_MANIFEST_LINK` — an `ant://manifest/` link to decode
 *
 *     ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_MANIFEST_ADDRESSES=<hex>,<hex> \
 *         vendor/bin/phpunit tests/LiveManifestsTest.php
 */
class LiveManifestsTest extends TestCase
{
    private static function env(string $name): ?string
    {
        $value = getenv($name);
        return is_string($value) && trim($value) !== '' ? trim($value) : null;
    }

    /** @return list<string> */
    private static function list(?string $value): array
    {
        return $value === null ? [] : array_map('trim', explode(',', $value));
    }

    private static function entry(BuiltManifest|DecodedManifest $m, string $name): ManifestEntryInfo
    {
        foreach ($m->entries as $e) {
            if ($e->effectiveName === $name) {
                return $e;
            }
        }
        self::fail("no entry named {$name}");
    }

    private function catchAntdError(callable $call): AntdError
    {
        try {
            $call();
        } catch (AntdError $e) {
            return $e;
        }
        $this->fail('Expected an AntdError');
    }

    public function testLiveManifestRoundTrip(): void
    {
        $url = self::env('ANTD_TEST_URL');
        $addresses = self::list(self::env('ANTD_TEST_MANIFEST_ADDRESSES'));
        if ($url === null || count($addresses) < 2) {
            $this->markTestSkipped('set ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES to run');
        }
        [$one, $two] = $addresses;
        $sizes = array_map('intval', self::list(self::env('ANTD_TEST_MANIFEST_SIZES')));
        $dataMap = self::env('ANTD_TEST_MANIFEST_DATA_MAP');
        $dataMapSize = self::env('ANTD_TEST_MANIFEST_DATA_MAP_SIZE');
        $client = new AntdClient($url, 300.0);

        // 1. Build from the two addresses and, when given, the DataMap.
        $entries = [
            new ManifestEntryInput(path: 'live/one.txt', address: $one),
            new ManifestEntryInput(path: 'live/two.txt', address: $two),
        ];
        if ($dataMap !== null) {
            $entries[] = new ManifestEntryInput(path: 'live/private.bin', dataMap: $dataMap);
        }
        $built = $client->buildManifest($entries, new BuildManifestOptions(name: 'antd-php-live'));

        // 2. Kinds, effective names and the link.
        $this->assertStringStartsWith("\xC1ANT\x01", $built->manifest);
        $this->assertNotNull($built->link);
        $this->assertStringStartsWith('ant://manifest/', $built->link);
        $this->assertCount(count($entries), $built->entries);
        $names = array_map(fn($e) => $e->effectiveName, $built->entries);
        $expected = $dataMap === null ? ['live/one.txt', 'live/two.txt'] : ['live/one.txt', 'live/private.bin', 'live/two.txt'];
        $this->assertSame($expected, $names, 'entries come back sorted by effective name');
        $this->assertSame('public', self::entry($built, 'live/one.txt')->kind);
        $this->assertSame($one, self::entry($built, 'live/one.txt')->contentAddress);
        $this->assertSame('public', self::entry($built, 'live/two.txt')->kind);
        $this->assertNull(self::entry($built, 'live/one.txt')->size, 'no size given, none recorded');
        if ($dataMap !== null) {
            $this->assertSame('embedded', self::entry($built, 'live/private.bin')->kind);
        }

        // 3. Decode the bytes and the link, resolving.
        foreach ([
            'bytes' => $client->decodeManifest($built->manifest, true),
            'link' => $client->decodeManifestLinkAsync($built->link, true)->wait(),
        ] as $how => $decoded) {
            $this->assertSame('manifest', $decoded->source, $how);
            $this->assertSame('antd-php-live', $decoded->name, $how);
            $this->assertNull($decoded->torrentInfoHashV1, $how);
            $this->assertSame($names, array_map(fn($e) => $e->effectiveName, $decoded->entries), $how);
            foreach (['live/one.txt', 'live/two.txt'] as $i => $name) {
                $e = self::entry($decoded, $name);
                $this->assertSame('public', $e->kind, $how);
                $this->assertNull($e->error, "{$how}: {$name}");
                $this->assertNull($e->dataMap, $how);
                $this->assertNull($e->size, $how);
                $this->assertNotNull($e->exactSize, "{$how}: {$name}");
                if ($sizes !== []) {
                    $this->assertSame($sizes[$i], $e->exactSize, "{$how}: {$name}");
                }
            }
            if ($dataMap !== null) {
                $p = self::entry($decoded, 'live/private.bin');
                $this->assertSame('embedded', $p->kind, $how);
                $this->assertNotNull($p->dataMap, $how);
                $this->assertNotSame('', $p->dataMap, $how);
                $this->assertNull($p->error, $how);
                if ($dataMapSize !== null) {
                    $this->assertSame((int) $dataMapSize, $p->exactSize, $how);
                }
            }
        }

        // Without resolve, a public entry's exact size is unknown: null, not 0.
        $plain = $client->decodeManifest($built->manifest);
        $this->assertNull(self::entry($plain, 'live/one.txt')->exactSize);
        $this->assertNull(self::entry($plain, 'live/two.txt')->exactSize);

        // The embedded DataMap decodes back to the same content address.
        if ($dataMap !== null) {
            $rebuilt = $client->buildManifest([
                new ManifestEntryInput(dataMap: (string) self::entry($plain, 'live/private.bin')->dataMap),
            ]);
            $this->assertSame(
                self::entry($built, 'live/private.bin')->contentAddress,
                $rebuilt->entries[0]->contentAddress,
            );
        }

        // A bare address reads as a file link: one public entry, no path.
        $file = $client->decodeManifestLink($one, true);
        $this->assertSame('file_link', $file->source);
        $this->assertCount(1, $file->entries);
        $this->assertNull($file->entries[0]->path);
        $this->assertSame($one, $file->entries[0]->contentAddress);
        if ($sizes !== []) {
            $this->assertSame($sizes[0], $file->entries[0]->exactSize);
        }

        // 4. The fixture link.
        $link = self::env('ANTD_TEST_MANIFEST_LINK');
        if ($link !== null) {
            $fixture = $client->decodeManifestLink($link, true);
            $this->assertSame('manifest', $fixture->source);
            $this->assertNotEmpty($fixture->entries);
            foreach ($fixture->entries as $e) {
                $this->assertNull($e->error, $e->effectiveName);
                $this->assertNotNull($e->exactSize, $e->effectiveName);
            }
        }

        // 5. Bad input: the daemon's 400 names the entry; both sources is
        // refused before sending.
        $e = $this->catchAntdError(fn() => $client->buildManifest([
            new ManifestEntryInput(path: 'ok.txt', address: $one),
            new ManifestEntryInput(path: '../x', address: $two),
        ]));
        $this->assertInstanceOf(BadRequestError::class, $e);
        $this->assertStringContainsString('entries[1]', $e->getMessage());

        $e = $this->catchAntdError(fn() => $client->decodeManifest('not a manifest'));
        $this->assertInstanceOf(BadRequestError::class, $e);

        // Refused before sending, and worded exactly as the daemon words it:
        // send the same mistake past the client check (raw REST) and compare.
        $local = $this->catchAntdError(fn() => $client->buildManifest([
            new ManifestEntryInput(path: 'ok.txt', address: $one),
            new ManifestEntryInput(dataMap: $dataMap ?? 'aa', address: $one),
            new ManifestEntryInput(path: 'c.txt'),
        ]));
        $this->assertInstanceOf(BadRequestError::class, $local);
        $this->assertSame(400, $local->statusCode);
        $remote = null;
        try {
            (new \GuzzleHttp\Client())->post($url . '/v1/manifests/build', ['json' => ['entries' => [
                ['path' => 'ok.txt', 'address' => $one],
                ['data_map' => $dataMap ?? 'aa', 'address' => $one],
                ['path' => 'c.txt'],
            ]]]);
        } catch (\GuzzleHttp\Exception\ClientException $ex) {
            $remote = json_decode((string) $ex->getResponse()->getBody(), true)['error'] ?? null;
        }
        $this->assertIsString($remote);
        // REST's error text carries a "Bad request: " prefix that gRPC and the client leave off.
        $this->assertSame('antd error 400: ' . preg_replace('/^Bad request: /', '', $remote), $local->getMessage());
    }
}
