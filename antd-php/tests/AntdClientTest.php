<?php

declare(strict_types=1);

namespace Autonomi\Antd\Tests;

use Autonomi\Antd\AntdClient;
use Autonomi\Antd\Errors\NotFoundError;
use Autonomi\Antd\Errors\BadRequestError;
use Autonomi\Antd\Errors\PaymentError;
use Autonomi\Antd\Errors\InternalError;
use Autonomi\Antd\Errors\NetworkError;
use Autonomi\Antd\Errors\TooLargeError;
use Autonomi\Antd\Errors\AlreadyExistsError;
use Autonomi\Antd\Models\Archive;
use Autonomi\Antd\Models\ArchiveEntry;
use Autonomi\Antd\Models\GraphDescendant;
use GuzzleHttp\Client;
use GuzzleHttp\Handler\MockHandler;
use GuzzleHttp\HandlerStack;
use GuzzleHttp\Psr7\Response;
use PHPUnit\Framework\TestCase;

class AntdClientTest extends TestCase
{
    private function createClient(MockHandler $mock): AntdClient
    {
        $handlerStack = HandlerStack::create($mock);
        $httpClient = new Client(['handler' => $handlerStack]);
        return new AntdClient('http://localhost:8080', 300.0, $httpClient);
    }

    private function jsonResponse(int $status, array $body): Response
    {
        return new Response($status, ['Content-Type' => 'application/json'], json_encode($body));
    }

    // --- Health ---

    public function testHealth(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['status' => 'ok', 'network' => 'local']),
        ]);
        $client = $this->createClient($mock);
        $health = $client->health();
        $this->assertTrue($health->ok);
        $this->assertSame('local', $health->network);
    }

    // --- Data Public ---

    public function testDataPutPublic(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['cost' => '100', 'address' => 'abc123']),
        ]);
        $client = $this->createClient($mock);
        $result = $client->dataPutPublic('hello');
        $this->assertSame('abc123', $result->address);
        $this->assertSame('100', $result->cost);
    }

    public function testDataGetPublic(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['data' => base64_encode('hello')]),
        ]);
        $client = $this->createClient($mock);
        $data = $client->dataGetPublic('abc123');
        $this->assertSame('hello', $data);
    }

    // --- Data Private ---

    public function testDataPutPrivate(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['cost' => '200', 'data_map' => 'dm123']),
        ]);
        $client = $this->createClient($mock);
        $result = $client->dataPutPrivate('secret');
        $this->assertSame('dm123', $result->address);
        $this->assertSame('200', $result->cost);
    }

    public function testDataGetPrivate(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['data' => base64_encode('secret')]),
        ]);
        $client = $this->createClient($mock);
        $data = $client->dataGetPrivate('dm123');
        $this->assertSame('secret', $data);
    }

    // --- Data Cost ---

    public function testDataCost(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['cost' => '50']),
        ]);
        $client = $this->createClient($mock);
        $cost = $client->dataCost('test');
        $this->assertSame('50', $cost);
    }

    // --- Chunks ---

    public function testChunkPut(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['cost' => '10', 'address' => 'chunk1']),
        ]);
        $client = $this->createClient($mock);
        $result = $client->chunkPut('chunkdata');
        $this->assertSame('chunk1', $result->address);
        $this->assertSame('10', $result->cost);
    }

    public function testChunkGet(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['data' => base64_encode('chunkdata')]),
        ]);
        $client = $this->createClient($mock);
        $data = $client->chunkGet('chunk1');
        $this->assertSame('chunkdata', $data);
    }

    // --- Graph ---

    public function testGraphEntryPut(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['cost' => '500', 'address' => 'ge1']),
        ]);
        $client = $this->createClient($mock);
        $result = $client->graphEntryPut('sk1', [], 'abc', []);
        $this->assertSame('ge1', $result->address);
        $this->assertSame('500', $result->cost);
    }

    public function testGraphEntryGet(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'owner' => 'owner1',
                'parents' => [],
                'content' => 'abc',
                'descendants' => [['public_key' => 'pk1', 'content' => 'desc1']],
            ]),
        ]);
        $client = $this->createClient($mock);
        $entry = $client->graphEntryGet('ge1');
        $this->assertSame('owner1', $entry->owner);
        $this->assertCount(1, $entry->descendants);
        $this->assertSame('pk1', $entry->descendants[0]->publicKey);
        $this->assertSame('desc1', $entry->descendants[0]->content);
    }

    public function testGraphEntryExists(): void
    {
        $mock = new MockHandler([
            new Response(200),
        ]);
        $client = $this->createClient($mock);
        $this->assertTrue($client->graphEntryExists('ge1'));
    }

    public function testGraphEntryExistsNotFound(): void
    {
        $mock = new MockHandler([
            new Response(404),
        ]);
        $client = $this->createClient($mock);
        $this->assertFalse($client->graphEntryExists('missing'));
    }

    public function testGraphEntryCost(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['cost' => '500']),
        ]);
        $client = $this->createClient($mock);
        $cost = $client->graphEntryCost('pk1');
        $this->assertSame('500', $cost);
    }

    // --- Files ---

    public function testFileUploadPublic(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['cost' => '1000', 'address' => 'file1']),
        ]);
        $client = $this->createClient($mock);
        $result = $client->fileUploadPublic('/tmp/test.txt');
        $this->assertSame('file1', $result->address);
        $this->assertSame('1000', $result->cost);
    }

    public function testFileDownloadPublic(): void
    {
        $mock = new MockHandler([
            new Response(200),
        ]);
        $client = $this->createClient($mock);
        $client->fileDownloadPublic('file1', '/tmp/out.txt');
        // No exception means success
        $this->assertTrue(true);
    }

    public function testDirUploadPublic(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['cost' => '2000', 'address' => 'dir1']),
        ]);
        $client = $this->createClient($mock);
        $result = $client->dirUploadPublic('/tmp/mydir');
        $this->assertSame('dir1', $result->address);
        $this->assertSame('2000', $result->cost);
    }

    public function testDirDownloadPublic(): void
    {
        $mock = new MockHandler([
            new Response(200),
        ]);
        $client = $this->createClient($mock);
        $client->dirDownloadPublic('dir1', '/tmp/outdir');
        $this->assertTrue(true);
    }

    public function testArchiveGetPublic(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'entries' => [[
                    'path' => 'test.txt',
                    'address' => 'abc',
                    'created' => 1000,
                    'modified' => 2000,
                    'size' => 42,
                ]],
            ]),
        ]);
        $client = $this->createClient($mock);
        $archive = $client->archiveGetPublic('arc1');
        $this->assertCount(1, $archive->entries);
        $this->assertSame('test.txt', $archive->entries[0]->path);
        $this->assertSame('abc', $archive->entries[0]->address);
        $this->assertSame(1000, $archive->entries[0]->created);
        $this->assertSame(2000, $archive->entries[0]->modified);
        $this->assertSame(42, $archive->entries[0]->size);
    }

    public function testArchivePutPublic(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['cost' => '50', 'address' => 'arc2']),
        ]);
        $client = $this->createClient($mock);
        $archive = new Archive(entries: [
            new ArchiveEntry(path: 'test.txt', address: 'abc', created: 1000, modified: 2000, size: 42),
        ]);
        $result = $client->archivePutPublic($archive);
        $this->assertSame('arc2', $result->address);
        $this->assertSame('50', $result->cost);
    }

    public function testFileCost(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['cost' => '1000']),
        ]);
        $client = $this->createClient($mock);
        $cost = $client->fileCost('/tmp/test.txt', true, false);
        $this->assertSame('1000', $cost);
    }

    // --- Error Mapping ---

    public function testErrorMapping404(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(404, ['error' => 'not found']),
        ]);
        $client = $this->createClient($mock);
        $this->expectException(NotFoundError::class);
        $client->health();
    }

    public function testErrorMapping400(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(400, ['error' => 'bad request']),
        ]);
        $client = $this->createClient($mock);
        $this->expectException(BadRequestError::class);
        $client->health();
    }

    public function testErrorMapping402(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(402, ['error' => 'payment required']),
        ]);
        $client = $this->createClient($mock);
        $this->expectException(PaymentError::class);
        $client->health();
    }

    public function testErrorMapping409(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(409, ['error' => 'already exists']),
        ]);
        $client = $this->createClient($mock);
        $this->expectException(AlreadyExistsError::class);
        $client->health();
    }

    public function testErrorMapping413(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(413, ['error' => 'too large']),
        ]);
        $client = $this->createClient($mock);
        $this->expectException(TooLargeError::class);
        $client->health();
    }

    public function testErrorMapping500(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(500, ['error' => 'internal error']),
        ]);
        $client = $this->createClient($mock);
        $this->expectException(InternalError::class);
        $client->health();
    }

    public function testErrorMapping502(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(502, ['error' => 'network error']),
        ]);
        $client = $this->createClient($mock);
        $this->expectException(NetworkError::class);
        $client->health();
    }

    public function testErrorStatusCode(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(404, ['error' => 'not found']),
        ]);
        $client = $this->createClient($mock);
        try {
            $client->health();
            $this->fail('Expected NotFoundError');
        } catch (NotFoundError $e) {
            $this->assertSame(404, $e->statusCode);
            $this->assertStringContainsString('not found', $e->getMessage());
        }
    }
}
