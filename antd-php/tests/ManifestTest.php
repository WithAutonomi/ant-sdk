<?php

declare(strict_types=1);

namespace Autonomi\Antd\Tests;

use Autonomi\Antd\AntdClient;
use Autonomi\Antd\Errors\AntdError;
use Autonomi\Antd\Errors\BadRequestError;
use Autonomi\Antd\Errors\NotFoundError;
use Autonomi\Antd\Models\BuildManifestOptions;
use Autonomi\Antd\Models\ManifestEntryInput;
use GuzzleHttp\Client;
use GuzzleHttp\Handler\MockHandler;
use GuzzleHttp\HandlerStack;
use GuzzleHttp\Middleware;
use GuzzleHttp\Psr7\Response;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;
use Psr\Http\Message\RequestInterface;

/**
 * The manifest API over a mocked daemon (Guzzle MockHandler): request shapes,
 * the base64 the REST API carries the `.ant` bytes in, unset sizes, the
 * entry check made before sending, and the bad-request mapping.
 */
class ManifestTest extends TestCase
{
    /** The five-byte `.ant` header; "wUFOVAE=" is its base64. */
    private const HEADER = "\xC1ANT\x01";

    /** @var list<array{request: RequestInterface}> */
    private array $history = [];

    private function client(Response ...$responses): AntdClient
    {
        $stack = HandlerStack::create(new MockHandler($responses));
        $stack->push(Middleware::history($this->history));
        return new AntdClient('http://localhost:8082', 300.0, new Client(['handler' => $stack]));
    }

    /** @param array<mixed> $body */
    private function json(int $status, array $body): Response
    {
        return new Response($status, ['Content-Type' => 'application/json'], (string) json_encode($body));
    }

    private function raw(int $status, string $json): Response
    {
        return new Response($status, ['Content-Type' => 'application/json'], $json);
    }

    private function lastRequest(): RequestInterface
    {
        $this->assertNotEmpty($this->history, 'no request was sent');
        return $this->history[count($this->history) - 1]['request'];
    }

    /** @return array<mixed> */
    private function lastBody(): array
    {
        $body = json_decode((string) $this->lastRequest()->getBody(), true);
        $this->assertIsArray($body);
        return $body;
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

    private const BUILT = '{
        "manifest": "wUFOVAE=",
        "link": "ant://manifest/wUFOVAE",
        "entries": [
            {"effective_name": "a.txt", "path": "a.txt", "size": 10, "kind": "embedded",
             "content_address": "cc", "exact_size": 10},
            {"effective_name": "11", "kind": "public", "content_address": "11"}
        ]
    }';

    // --- Build ---

    public function testBuildSendsEntriesAndOptionsAndDecodesTheBytes(): void
    {
        $client = $this->client($this->raw(200, self::BUILT));
        $res = $client->buildManifest([
            new ManifestEntryInput(path: 'a.txt', size: 10, dataMap: 'abcd'),
            new ManifestEntryInput(address: '11'),
        ], new BuildManifestOptions(name: 'album', embedRoots: false));

        $this->assertSame('POST', $this->lastRequest()->getMethod());
        $this->assertSame('/v1/manifests/build', $this->lastRequest()->getUri()->getPath());
        $this->assertSame([
            'entries' => [
                ['path' => 'a.txt', 'size' => 10, 'data_map' => 'abcd'],
                ['address' => '11'],
            ],
            'embed_roots' => false,
            'name' => 'album',
        ], $this->lastBody());

        // Raw bytes out: the caller never sees the base64.
        $this->assertSame(self::HEADER, $res->manifest);
        $this->assertSame('ant://manifest/wUFOVAE', $res->link);
        $this->assertCount(2, $res->entries);

        [$a, $p] = $res->entries;
        $this->assertSame(['a.txt', 'a.txt', 10, 'embedded', 'cc', 10], [$a->effectiveName, $a->path, $a->size, $a->kind, $a->contentAddress, $a->exactSize]);
        $this->assertNull($a->dataMap);
        $this->assertNull($a->error);
        $this->assertSame(['11', 'public', '11'], [$p->effectiveName, $p->kind, $p->contentAddress]);
        $this->assertNull($p->path);
        $this->assertNull($p->size);
        $this->assertNull($p->exactSize);
        $this->assertNull($p->dataMap);
    }

    public function testBuildDefaultsToEmbeddingRootsAndLeavesUnsetOptionsOut(): void
    {
        $client = $this->client(
            $this->raw(200, '{"manifest": "", "entries": []}'),
            $this->raw(200, '{"manifest": "", "entries": []}'),
        );
        $client->buildManifest([new ManifestEntryInput(address: '11')]);
        $this->assertSame(['entries' => [['address' => '11']], 'embed_roots' => true], $this->lastBody());

        $res = $client->buildManifest([new ManifestEntryInput(address: '11')], new BuildManifestOptions());
        $this->assertSame(['entries' => [['address' => '11']], 'embed_roots' => true], $this->lastBody());
        $this->assertSame('', $res->manifest);
        $this->assertNull($res->link);
        $this->assertSame([], $res->entries);
    }

    public function testBuildSendsTorrentInfoHashesAndOmitsEmptyStrings(): void
    {
        $v1 = str_repeat('a', 40);
        $v2 = str_repeat('b', 64);
        $client = $this->client($this->raw(200, '{"manifest": "wUFOVAE=", "entries": []}'));
        $client->buildManifest(
            [new ManifestEntryInput(path: '', dataMap: 'abcd', address: '')],
            new BuildManifestOptions(name: '', torrentInfoHashes: [$v1, $v2]),
        );
        $this->assertSame([
            'entries' => [['data_map' => 'abcd']],
            'embed_roots' => true,
            'torrent_info_hashes' => [$v1, $v2],
        ], $this->lastBody());
    }

    public function testBuildSendsAZeroSizeButNeverInventsOne(): void
    {
        $client = $this->client($this->raw(200, '{"manifest": "", "entries": []}'));
        $client->buildManifest([
            new ManifestEntryInput(path: 'empty.txt', size: 0, address: '11'),
            new ManifestEntryInput(path: 'unknown.txt', address: '22'),
        ]);
        $entries = $this->lastBody()['entries'];
        $this->assertSame(0, $entries[0]['size']);
        $this->assertArrayNotHasKey('size', $entries[1]);
    }

    public function testBuildSendsAKeyedEntryArrayAsAList(): void
    {
        $client = $this->client($this->raw(200, '{"manifest": "", "entries": []}'));
        $client->buildManifest(['x' => new ManifestEntryInput(address: '11'), 'y' => new ManifestEntryInput(address: '22')]);
        $this->assertStringContainsString('"entries":[{', (string) $this->lastRequest()->getBody());
        $this->assertSame([['address' => '11'], ['address' => '22']], $this->lastBody()['entries']);
    }

    /** @return array<string, array{0: list<mixed>, 1: string}> */
    public static function invalidEntries(): array
    {
        $ok = new ManifestEntryInput(address: '11');
        return [
            'neither' => [[new ManifestEntryInput(path: 'a.txt')], '1 invalid entries: entries[0]: needs a data_map or an address'],
            'both' => [[$ok, new ManifestEntryInput(dataMap: 'aa', address: 'bb')], '1 invalid entries: entries[1]: give data_map or address, not both'],
            'both empty strings' => [[new ManifestEntryInput(dataMap: '', address: '')], '1 invalid entries: entries[0]: needs a data_map or an address'],
            'two bad entries' => [
                [new ManifestEntryInput(dataMap: 'aa', address: 'bb'), $ok, new ManifestEntryInput(path: 'c.txt')],
                '2 invalid entries: entries[0]: give data_map or address, not both; entries[2]: needs a data_map or an address',
            ],
            'negative size' => [[$ok, $ok, new ManifestEntryInput(size: -1, address: '11')], '1 invalid entries: entries[2]: size must not be negative'],
            'not an entry' => [[$ok, ['address' => '11']], '1 invalid entries: entries[1]: not a ManifestEntryInput'],
            'more than 20' => [
                array_fill(0, 23, new ManifestEntryInput()),
                '23 invalid entries: ' . implode('; ', array_map(fn($i) => "entries[{$i}]: needs a data_map or an address", range(0, 19))) . '; and 3 more',
            ],
        ];
    }

    /** @param list<mixed> $entries */
    #[DataProvider('invalidEntries')]
    public function testBuildRejectsABadEntryBeforeSending(array $entries, string $message): void
    {
        $client = $this->client(); // an empty MockHandler: any request would fail the test
        $e = $this->catchAntdError(fn() => $client->buildManifest($entries));
        $this->assertInstanceOf(BadRequestError::class, $e);
        $this->assertSame(400, $e->statusCode);
        $this->assertSame("antd error 400: Bad request: {$message}", $e->getMessage());
        $this->assertSame([], $this->history);
    }

    /** @param list<mixed> $entries */
    #[DataProvider('invalidEntries')]
    public function testBuildAsyncRejectsABadEntryBeforeSending(array $entries, string $message): void
    {
        $client = $this->client();
        $e = $this->catchAntdError(fn() => $client->buildManifestAsync($entries));
        $this->assertInstanceOf(BadRequestError::class, $e);
        $this->assertSame(400, $e->statusCode);
        $this->assertSame("antd error 400: Bad request: {$message}", $e->getMessage());
        $this->assertSame([], $this->history);
    }

    public function testBuildAsync(): void
    {
        $client = $this->client($this->raw(200, self::BUILT));
        $res = $client->buildManifestAsync([new ManifestEntryInput(path: 'a.txt', size: 10, dataMap: 'abcd')])->wait();
        $this->assertSame(self::HEADER, $res->manifest);
        $this->assertSame(10, $res->entries[0]->exactSize);
        $this->assertTrue($this->lastBody()['embed_roots']);
    }

    public function testBuildRefusesAManifestThatIsNotBase64(): void
    {
        $client = $this->client($this->raw(200, '{"manifest": "not base64!", "entries": []}'));
        $this->expectException(\UnexpectedValueException::class);
        $client->buildManifest([new ManifestEntryInput(address: '11')]);
    }

    public function testBuildBadRequestIsTypedAndKeepsTheDaemonsMessage(): void
    {
        $message = 'Bad request: entries[0]: path ../x is not portable; entries[1]: invalid hex';
        $client = $this->client($this->json(400, ['error' => $message, 'code' => 'BAD_REQUEST']));
        $e = $this->catchAntdError(fn() => $client->buildManifest([
            new ManifestEntryInput(path: '../x', address: '11'),
            new ManifestEntryInput(dataMap: 'zz'),
        ]));
        $this->assertInstanceOf(BadRequestError::class, $e);
        $this->assertSame(400, $e->statusCode);
        $this->assertStringContainsString($message, $e->getMessage());
    }

    public function testBuildAsyncBadRequestIsTyped(): void
    {
        $client = $this->client($this->json(400, ['error' => 'Bad request: entries[0]: bad', 'code' => 'BAD_REQUEST']));
        $e = $this->catchAntdError(fn() => $client->buildManifestAsync([new ManifestEntryInput(address: 'zz')])->wait());
        $this->assertInstanceOf(BadRequestError::class, $e);
        $this->assertStringContainsString('entries[0]: bad', $e->getMessage());
    }

    public function testBuildMissingWrapperRecordsIsNotFound(): void
    {
        $client = $this->client($this->json(404, ['error' => 'Not found: entries[1]: record gone', 'code' => 'NOT_FOUND']));
        $e = $this->catchAntdError(fn() => $client->buildManifest([new ManifestEntryInput(dataMap: 'abcd')]));
        $this->assertInstanceOf(NotFoundError::class, $e);
        $this->assertStringContainsString('entries[1]', $e->getMessage());
    }

    // --- Decode ---

    private const DECODED = '{
        "source": "manifest", "name": "album", "torrent_info_hash_v2": "bb",
        "entries": [
            {"effective_name": "a.txt", "path": "a.txt", "kind": "embedded",
             "content_address": "cc", "data_map": "abcd", "exact_size": 3},
            {"effective_name": "b", "path": "b", "kind": "public", "content_address": "dd",
             "error": "Record not found: gone"}
        ]
    }';

    public function testDecodeSendsBase64AndParsesEntries(): void
    {
        $client = $this->client($this->raw(200, self::DECODED));
        $res = $client->decodeManifest(self::HEADER, true);

        $this->assertSame('POST', $this->lastRequest()->getMethod());
        $this->assertSame('/v1/manifests/decode', $this->lastRequest()->getUri()->getPath());
        $this->assertSame(['manifest' => 'wUFOVAE=', 'resolve' => true], $this->lastBody());

        $this->assertSame('manifest', $res->source);
        $this->assertSame('album', $res->name);
        $this->assertNull($res->torrentInfoHashV1);
        $this->assertSame('bb', $res->torrentInfoHashV2);
        $this->assertCount(2, $res->entries);

        [$a, $b] = $res->entries;
        $this->assertSame(['embedded', 'abcd', 3], [$a->kind, $a->dataMap, $a->exactSize]);
        $this->assertNull($a->size);
        $this->assertNull($a->error);
        $this->assertSame(['public', 'Record not found: gone'], [$b->kind, $b->error]);
        $this->assertNull($b->exactSize);
        $this->assertNull($b->dataMap);
    }

    public function testDecodeDefaultsToNoResolve(): void
    {
        $client = $this->client($this->raw(200, '{"source": "manifest", "entries": []}'));
        $res = $client->decodeManifest(self::HEADER);
        $this->assertSame(['manifest' => 'wUFOVAE=', 'resolve' => false], $this->lastBody());
        $this->assertNull($res->name);
        $this->assertNull($res->torrentInfoHashV2);
    }

    public function testBinaryBytesSurviveTheBase64RoundTrip(): void
    {
        $bytes = self::HEADER . implode('', array_map('chr', range(0, 255)));
        $client = $this->client(
            $this->json(200, ['manifest' => base64_encode($bytes), 'entries' => []]),
            $this->raw(200, '{"source": "manifest", "entries": []}'),
        );
        $built = $client->buildManifest([new ManifestEntryInput(address: '11')]);
        $this->assertSame($bytes, $built->manifest);

        $client->decodeManifest($built->manifest);
        $sent = $this->lastBody()['manifest'];
        $this->assertSame(base64_encode($bytes), $sent);
        $this->assertSame($bytes, base64_decode($sent, true));
    }

    public function testUnsetSizesReadAsNullNotZero(): void
    {
        $client = $this->client($this->raw(200, '{"source": "manifest", "entries": [
            {"effective_name": "absent", "kind": "public", "content_address": "aa"},
            {"effective_name": "null", "kind": "public", "content_address": "bb", "size": null, "exact_size": null},
            {"effective_name": "zero", "kind": "public", "content_address": "cc", "size": 0, "exact_size": 0},
            {"effective_name": "garbled", "kind": "public", "content_address": "dd", "size": "7", "exact_size": -1},
            {"effective_name": "big", "kind": "public", "content_address": "ee", "size": 54903201, "exact_size": 4294967296}
        ]}'));
        $sizes = array_map(fn($e) => [$e->size, $e->exactSize], $client->decodeManifest(self::HEADER)->entries);
        $this->assertSame([[null, null], [null, null], [0, 0], [null, null], [54903201, 4294967296]], $sizes);
    }

    public function testDecodeLinkSendsTheLinkAndNoBytes(): void
    {
        $address = str_repeat('42', 31) . 'aa';
        $client = $this->client($this->json(200, [
            'source' => 'file_link',
            'entries' => [['effective_name' => $address, 'kind' => 'public', 'content_address' => $address]],
        ]));
        $res = $client->decodeManifestLink($address);
        $this->assertSame(['link' => $address, 'resolve' => false], $this->lastBody());
        $this->assertSame('file_link', $res->source);
        $this->assertCount(1, $res->entries);
        $this->assertSame($address, $res->entries[0]->contentAddress);
        $this->assertNull($res->entries[0]->path);
    }

    public function testDecodeLinkWithResolve(): void
    {
        $client = $this->client($this->raw(200, self::DECODED));
        $client->decodeManifestLink('ant://manifest/wUFOVAE', true);
        $this->assertSame(['link' => 'ant://manifest/wUFOVAE', 'resolve' => true], $this->lastBody());
    }

    public function testDecodeAsyncAndLinkAsync(): void
    {
        $client = $this->client($this->raw(200, self::DECODED), $this->raw(200, self::DECODED));
        $res = $client->decodeManifestAsync(self::HEADER, true)->wait();
        $this->assertSame(['manifest' => 'wUFOVAE=', 'resolve' => true], $this->lastBody());
        $this->assertSame(3, $res->entries[0]->exactSize);

        $res = $client->decodeManifestLinkAsync('ant://manifest/wUFOVAE')->wait();
        $this->assertSame(['link' => 'ant://manifest/wUFOVAE', 'resolve' => false], $this->lastBody());
        $this->assertSame('album', $res->name);
    }

    public function testDecodeRefusesEmptyInputBeforeSending(): void
    {
        $client = $this->client();
        foreach ([
            fn() => $client->decodeManifest(''),
            fn() => $client->decodeManifestAsync(''),
            fn() => $client->decodeManifestLink(''),
            fn() => $client->decodeManifestLinkAsync(''),
        ] as $call) {
            $e = $this->catchAntdError($call);
            $this->assertInstanceOf(BadRequestError::class, $e);
            $this->assertSame(400, $e->statusCode);
            $this->assertSame('antd error 400: Bad request: needs a manifest (base64 .ant bytes) or a link', $e->getMessage());
        }
        $this->assertSame([], $this->history);
    }

    public function testDecodeBadRequestIsTyped(): void
    {
        $message = 'Bad request: not a manifest: missing or invalid header';
        $client = $this->client(
            $this->json(400, ['error' => $message, 'code' => 'BAD_REQUEST']),
            $this->json(400, ['error' => 'Bad request: not an ant:// link', 'code' => 'BAD_REQUEST']),
        );
        $e = $this->catchAntdError(fn() => $client->decodeManifest('nope'));
        $this->assertInstanceOf(BadRequestError::class, $e);
        $this->assertStringContainsString($message, $e->getMessage());

        $e = $this->catchAntdError(fn() => $client->decodeManifestLinkAsync('nope')->wait());
        $this->assertInstanceOf(BadRequestError::class, $e);
        $this->assertStringContainsString('not an ant:// link', $e->getMessage());
    }
}
