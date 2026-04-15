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
        return new AntdClient('http://localhost:8082', 300.0, $httpClient);
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

    // --- Files ---

    public function testFileUploadPublic(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'address' => 'file1',
                'storage_cost_atto' => '1000',
                'gas_cost_wei' => '42',
                'chunks_stored' => 3,
                'payment_mode_used' => 'auto',
            ]),
        ]);
        $client = $this->createClient($mock);
        $result = $client->fileUploadPublic('/tmp/test.txt');
        $this->assertSame('file1', $result->address);
        $this->assertSame('1000', $result->storageCostAtto);
        $this->assertSame('42', $result->gasCostWei);
        $this->assertSame(3, $result->chunksStored);
        $this->assertSame('auto', $result->paymentModeUsed);
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
            $this->jsonResponse(200, [
                'address' => 'dir1',
                'storage_cost_atto' => '2000',
                'gas_cost_wei' => '100',
                'chunks_stored' => 5,
                'payment_mode_used' => 'merkle',
            ]),
        ]);
        $client = $this->createClient($mock);
        $result = $client->dirUploadPublic('/tmp/mydir');
        $this->assertSame('dir1', $result->address);
        $this->assertSame('2000', $result->storageCostAtto);
        $this->assertSame('100', $result->gasCostWei);
        $this->assertSame(5, $result->chunksStored);
        $this->assertSame('merkle', $result->paymentModeUsed);
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
