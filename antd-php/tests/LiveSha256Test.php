<?php

declare(strict_types=1);

namespace Autonomi\Antd\Tests;

use Autonomi\Antd\AntdClient;
use Autonomi\Antd\Errors\AntdError;
use Autonomi\Antd\Errors\BadRequestError;
use Autonomi\Antd\Models\BuiltManifest;
use Autonomi\Antd\Models\DecodedManifest;
use Autonomi\Antd\Models\ManifestEntryInfo;
use Autonomi\Antd\Models\ManifestEntryInput;
use PHPUnit\Framework\TestCase;

/**
 * Live check of the `sha256` fields against antd 0.17.0 or later. The only
 * paid call is one small public data upload.
 *
 * Skipped unless both are set:
 *
 *  - `ANTD_TEST_URL` - the daemon's REST base URL
 *  - `ANTD_TEST_SHA_LINK` - a manifest link with entries `public.txt` and
 *    `private.txt` (each with a sha256) and `nohash.txt` (none)
 *
 * Also read:
 *
 *  - `ANTD_TEST_SHA_PUBLIC_ADDRESS` / `ANTD_TEST_SHA_PUBLIC_SHA256` - a public
 *    upload and its plaintext's SHA-256
 *  - `ANTD_TEST_SHA_DATA_MAP_SHA256` - the SHA-256 of `private.txt`
 *
 *     source ~/sha-fanout-daemon/fixtures.env
 *     vendor/bin/phpunit --testdox tests/LiveSha256Test.php
 */
class LiveSha256Test extends TestCase
{
    private static function env(string $name): ?string
    {
        $value = getenv($name);
        return is_string($value) && trim($value) !== '' ? trim($value) : null;
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

    public function testLiveSha256(): void
    {
        $url = self::env('ANTD_TEST_URL');
        $link = self::env('ANTD_TEST_SHA_LINK');
        if ($url === null || $link === null) {
            $this->markTestSkipped('set ANTD_TEST_URL and ANTD_TEST_SHA_LINK to run');
        }
        $publicAddress = (string) self::env('ANTD_TEST_SHA_PUBLIC_ADDRESS');
        $publicSha = (string) self::env('ANTD_TEST_SHA_PUBLIC_SHA256');
        $dataMapSha = (string) self::env('ANTD_TEST_SHA_DATA_MAP_SHA256');
        $client = new AntdClient($url, 300.0);

        // 1. Decode the fixture link without resolving.
        $decoded = $client->decodeManifestLink($link, false);
        $this->assertSame($publicSha, self::entry($decoded, 'public.txt')->sha256);
        $this->assertSame($dataMapSha, self::entry($decoded, 'private.txt')->sha256);
        $this->assertNull(self::entry($decoded, 'nohash.txt')->sha256);

        // 2. Build with a sha256: the returned entry carries it.
        $built = $client->buildManifest([
            new ManifestEntryInput(path: 'a.txt', address: $publicAddress, sha256: $publicSha),
        ]);
        $this->assertSame($publicSha, self::entry($built, 'a.txt')->sha256);
        $this->assertSame($publicSha, self::entry($client->decodeManifest($built->manifest), 'a.txt')->sha256);

        // 3. A bad sha256 is the daemon's 400.
        try {
            $client->buildManifest([
                new ManifestEntryInput(path: 'a.txt', address: $publicAddress, sha256: 'zz'),
            ]);
            $this->fail('Expected a BadRequestError');
        } catch (AntdError $e) {
            $this->assertInstanceOf(BadRequestError::class, $e);
            $this->assertSame(400, $e->statusCode);
            $this->assertStringContainsString('sha256', $e->getMessage());
        }

        // 4. One paid call: the upload's sha256 is the plaintext's.
        $payload = 'sha-fanout php ' . time();
        $result = $client->dataPutPublic($payload);
        $this->assertSame(hash('sha256', $payload), $result->sha256);
        fwrite(STDERR, "\nlive upload sha256: " . hash('sha256', $payload) . ' returned: ' . $result->sha256 . "\n");
    }
}
