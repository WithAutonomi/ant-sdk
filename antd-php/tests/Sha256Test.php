<?php

declare(strict_types=1);

namespace Autonomi\Antd\Tests;

use Autonomi\Antd\AntdClient;
use Autonomi\Antd\Errors\AntdError;
use Autonomi\Antd\Errors\BadRequestError;
use Autonomi\Antd\Models\DataPutResult;
use Autonomi\Antd\Models\FinalizeUploadResult;
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
 * The `sha256` fields (antd 0.17.0 or later) over a mocked daemon: upload
 * results, manifest entry input and manifest entry info. An absent key and an
 * empty string both read as null.
 */
class Sha256Test extends TestCase
{
    private const HASH = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

    private const ENTRIES = [
        ['effective_name' => 'a.txt', 'path' => 'a.txt', 'kind' => 'public', 'content_address' => 'aa', 'sha256' => self::HASH],
        ['effective_name' => 'b.txt', 'path' => 'b.txt', 'kind' => 'public', 'content_address' => 'bb'],
        ['effective_name' => 'c.txt', 'path' => 'c.txt', 'kind' => 'public', 'content_address' => 'cc', 'sha256' => ''],
    ];

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

    private function lastRawBody(): string
    {
        $this->assertNotEmpty($this->history, 'no request was sent');
        return (string) $this->history[count($this->history) - 1]['request']->getBody();
    }

    /** @return array<mixed> */
    private function lastBody(): array
    {
        return json_decode($this->lastRawBody(), true);
    }

    // --- Upload results ---

    /**
     * Each upload call (sync and async) with a response body that has no
     * sha256 yet.
     *
     * @return array<string, array{array<mixed>, callable(AntdClient): object}>
     */
    public static function uploads(): array
    {
        $dataPublic = ['address' => 'ad', 'chunks_stored' => 3, 'payment_mode_used' => 'single'];
        $data = ['data_map' => 'dm', 'chunks_stored' => 3, 'payment_mode_used' => 'single'];
        $filePublic = ['address' => 'ad', 'storage_cost_atto' => '1', 'gas_cost_wei' => '2', 'chunks_stored' => 3, 'payment_mode_used' => 'auto'];
        $file = ['data_map' => 'dm', 'storage_cost_atto' => '1', 'gas_cost_wei' => '2', 'chunks_stored' => 3, 'payment_mode_used' => 'auto'];
        $finalize = ['data_map' => 'dm', 'address' => '', 'data_map_address' => 'da', 'chunks_stored' => 3];
        return [
            'dataPutPublic' => [$dataPublic, fn(AntdClient $c) => $c->dataPutPublic('x')],
            'dataPutPublicAsync' => [$dataPublic, fn(AntdClient $c) => $c->dataPutPublicAsync('x')->wait()],
            'dataPut' => [$data, fn(AntdClient $c) => $c->dataPut('x')],
            'dataPutAsync' => [$data, fn(AntdClient $c) => $c->dataPutAsync('x')->wait()],
            'filePutPublic' => [$filePublic, fn(AntdClient $c) => $c->filePutPublic('/tmp/f')],
            'filePutPublicAsync' => [$filePublic, fn(AntdClient $c) => $c->filePutPublicAsync('/tmp/f')->wait()],
            'filePut' => [$file, fn(AntdClient $c) => $c->filePut('/tmp/f')],
            'filePutAsync' => [$file, fn(AntdClient $c) => $c->filePutAsync('/tmp/f')->wait()],
            'finalizeUpload' => [$finalize, fn(AntdClient $c) => $c->finalizeUpload('up', ['q' => 't'])],
            'finalizeUploadAsync' => [$finalize, fn(AntdClient $c) => $c->finalizeUploadAsync('up', ['q' => 't'])->wait()],
        ];
    }

    /** @param array<mixed> $body */
    #[DataProvider('uploads')]
    public function testUploadResultReadsSha256(array $body, callable $call): void
    {
        $result = $call($this->client($this->json(200, $body + ['sha256' => self::HASH])));
        $this->assertSame(self::HASH, $result->sha256);
        // The existing fields are untouched.
        $this->assertSame(3, $result->chunksStored);
    }

    /** @param array<mixed> $body */
    #[DataProvider('uploads')]
    public function testUploadResultReadsNullWhenSha256IsAbsent(array $body, callable $call): void
    {
        $result = $call($this->client($this->json(200, $body)));
        $this->assertNull($result->sha256, 'an older daemon sends no sha256');
    }

    /** @param array<mixed> $body */
    #[DataProvider('uploads')]
    public function testUploadResultReadsNullWhenSha256IsEmptyOrNull(array $body, callable $call): void
    {
        $this->assertNull($call($this->client($this->json(200, $body + ['sha256' => ''])))->sha256);
        $this->assertNull($call($this->client($this->json(200, $body + ['sha256' => null])))->sha256);
    }

    public function testExistingPositionalConstructionStillCompiles(): void
    {
        $this->assertNull((new DataPutResult('dm', 3, 'auto'))->sha256);
        $this->assertNull((new FinalizeUploadResult('dm', '', '', 3))->sha256);
        $this->assertNull((new ManifestEntryInput('p', null, null, 'aa'))->sha256);
    }

    // --- Manifest entry input ---

    public function testBuildSendsSha256OnlyOnEntriesThatSetIt(): void
    {
        $client = $this->client($this->json(200, ['manifest' => 'wUFOVAE=', 'entries' => []]));
        $client->buildManifest([
            new ManifestEntryInput(path: 'a.txt', address: '11', sha256: self::HASH),
            new ManifestEntryInput(path: 'b.txt', address: '22'),
            new ManifestEntryInput(path: 'c.txt', address: '33', sha256: ''),
            new ManifestEntryInput(path: 'd.txt', dataMap: 'abcd', sha256: 'ABC'),
        ]);
        $this->assertSame([
            ['path' => 'a.txt', 'sha256' => self::HASH, 'address' => '11'],
            ['path' => 'b.txt', 'address' => '22'],
            ['path' => 'c.txt', 'address' => '33'],
            // Passed through as given: no lowercasing, no checks.
            ['path' => 'd.txt', 'sha256' => 'ABC', 'data_map' => 'abcd'],
        ], $this->lastBody()['entries']);
        $this->assertStringNotContainsString('null', $this->lastRawBody());
    }

    public function testBuildAsyncSendsSha256(): void
    {
        $client = $this->client($this->json(200, ['manifest' => 'wUFOVAE=', 'entries' => []]));
        $client->buildManifestAsync([new ManifestEntryInput(address: '11', sha256: self::HASH)])->wait();
        $this->assertSame([['sha256' => self::HASH, 'address' => '11']], $this->lastBody()['entries']);
    }

    // --- Manifest entry info ---

    public function testBuildReadsEntrySha256(): void
    {
        $client = $this->client($this->json(200, ['manifest' => 'wUFOVAE=', 'entries' => self::ENTRIES]));
        $res = $client->buildManifest([new ManifestEntryInput(address: '11')]);
        $this->assertSame([self::HASH, null, null], array_map(fn($e) => $e->sha256, $res->entries));
    }

    public function testDecodeReadsEntrySha256(): void
    {
        $body = ['source' => 'manifest', 'entries' => self::ENTRIES];
        $client = $this->client($this->json(200, $body), $this->json(200, $body));
        $bytes = $client->decodeManifest("\xC1ANT\x01");
        $link = $client->decodeManifestLink('ant://manifest/x');
        foreach ([$bytes, $link] as $res) {
            $this->assertSame([self::HASH, null, null], array_map(fn($e) => $e->sha256, $res->entries));
        }
    }

    // --- Errors ---

    public function testBadSha256IsABadRequestWithTheDaemonsMessage(): void
    {
        $message = 'Bad request: entries[0]: invalid hex sha256: Invalid character z at position 0';
        $client = $this->client($this->json(400, ['error' => $message, 'code' => 'BAD_REQUEST']));
        try {
            $client->buildManifest([new ManifestEntryInput(address: '11', sha256: 'zz')]);
            $this->fail('Expected a BadRequestError');
        } catch (AntdError $e) {
            $this->assertInstanceOf(BadRequestError::class, $e);
            $this->assertSame(400, $e->statusCode);
            $this->assertStringContainsString('entries[0]: invalid hex sha256', $e->getMessage());
        }
        $this->assertSame('zz', $this->lastBody()['entries'][0]['sha256'], 'sent as given');
    }
}
