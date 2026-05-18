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
use GuzzleHttp\Middleware;
use GuzzleHttp\Psr7\Request;
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

    /**
     * Build a client that also records every outgoing Guzzle request into
     * $history. Used by the external-signer tests to assert on the JSON body
     * the SDK actually sends.
     *
     * @param list<array{request: Request, response: Response, error: \Throwable|null, options: array}> $history
     */
    private function createRecordingClient(MockHandler $mock, array &$history): AntdClient
    {
        $handlerStack = HandlerStack::create($mock);
        $handlerStack->push(Middleware::history($history));
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
            $this->jsonResponse(200, [
                'status' => 'ok',
                'network' => 'local',
                'version' => '0.4.0',
                'evm_network' => 'local',
                'uptime_seconds' => 42,
                'build_commit' => 'abcdef123456',
                'payment_token_address' => '0xtoken',
                'payment_vault_address' => '0xvault',
            ]),
        ]);
        $client = $this->createClient($mock);
        $health = $client->health();
        $this->assertTrue($health->ok);
        $this->assertSame('local', $health->network);
        $this->assertSame('0.4.0', $health->version);
        $this->assertSame('local', $health->evmNetwork);
        $this->assertSame(42, $health->uptimeSeconds);
        $this->assertSame('abcdef123456', $health->buildCommit);
        $this->assertSame('0xtoken', $health->paymentTokenAddress);
        $this->assertSame('0xvault', $health->paymentVaultAddress);
    }

    public function testHealthPreV0_4_0Daemon(): void
    {
        // Older daemons reply with just status + network; the empty defaults
        // populate the diagnostic fields rather than throwing.
        $mock = new MockHandler([
            $this->jsonResponse(200, ['status' => 'ok', 'network' => 'default']),
        ]);
        $client = $this->createClient($mock);
        $health = $client->health();
        $this->assertTrue($health->ok);
        $this->assertSame('default', $health->network);
        $this->assertSame('', $health->version);
        $this->assertSame('', $health->evmNetwork);
        $this->assertSame(0, $health->uptimeSeconds);
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
            $this->jsonResponse(200, [
                'cost' => '50',
                'file_size' => 4,
                'chunk_count' => 3,
                'estimated_gas_cost_wei' => '150000000000000',
                'payment_mode' => 'single',
            ]),
        ]);
        $client = $this->createClient($mock);
        $est = $client->dataCost('test');
        $this->assertSame('50', $est->cost);
        $this->assertSame(4, $est->fileSize);
        $this->assertSame(3, $est->chunkCount);
        $this->assertSame('150000000000000', $est->estimatedGasCostWei);
        $this->assertSame('single', $est->paymentMode);
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

    public function testFileCost(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'cost' => '1000',
                'file_size' => 4096,
                'chunk_count' => 3,
                'estimated_gas_cost_wei' => '150000000000000',
                'payment_mode' => 'auto',
            ]),
        ]);
        $client = $this->createClient($mock);
        $est = $client->fileCost('/tmp/test.txt', true);
        $this->assertSame('1000', $est->cost);
        $this->assertSame(4096, $est->fileSize);
        $this->assertSame(3, $est->chunkCount);
        $this->assertSame('150000000000000', $est->estimatedGasCostWei);
        $this->assertSame('auto', $est->paymentMode);
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

    // --- External Signer (Two-Phase Upload) ---

    public function testPrepareUploadOmitsVisibilityWhenNull(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'upload_id' => 'up-priv-1',
                'payment_type' => 'wave_batch',
                'payments' => [
                    ['quote_hash' => 'qh1', 'rewards_address' => 'ra1', 'amount' => '100'],
                ],
                'total_amount' => '100',
                'payment_vault_address' => '0xvault',
                'payment_token_address' => '0xtoken',
                'rpc_url' => 'http://localhost:8545',
            ]),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);

        $result = $client->prepareUpload('/tmp/test.txt');

        $body = json_decode((string) $history[0]['request']->getBody(), true);
        $this->assertSame('/tmp/test.txt', $body['path']);
        $this->assertArrayNotHasKey('visibility', $body);

        $this->assertSame('up-priv-1', $result->uploadId);
        $this->assertSame('wave_batch', $result->paymentType);
        $this->assertCount(1, $result->payments);
        $this->assertSame('qh1', $result->payments[0]->quoteHash);
        $this->assertSame('100', $result->totalAmount);
    }

    public function testPrepareUploadPublicSendsVisibility(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'upload_id' => 'up-pub-1',
                'payment_type' => 'wave_batch',
                'payments' => [
                    ['quote_hash' => 'qh1', 'rewards_address' => 'ra1', 'amount' => '100'],
                ],
                'total_amount' => '100',
                'payment_vault_address' => '0xvault',
                'payment_token_address' => '0xtoken',
                'rpc_url' => 'http://localhost:8545',
            ]),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);

        $result = $client->prepareUploadPublic('/tmp/test.txt');

        $body = json_decode((string) $history[0]['request']->getBody(), true);
        $this->assertSame('/tmp/test.txt', $body['path']);
        $this->assertSame('public', $body['visibility']);
        $this->assertSame('up-pub-1', $result->uploadId);
    }

    public function testFinalizeUploadSurfacesDataMapAddress(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'data_map' => 'deadbeef',
                'data_map_address' => 'cafebabe',
                'chunks_stored' => 4,
            ]),
        ]);
        $client = $this->createClient($mock);

        $result = $client->finalizeUpload('up1', ['qh1' => 'tx1']);

        $this->assertSame('deadbeef', $result->dataMap);
        $this->assertSame('cafebabe', $result->dataMapAddress);
        $this->assertSame('', $result->address, 'legacy address should be empty when not store_data_map');
        $this->assertSame(4, $result->chunksStored);
    }

    public function testFinalizeUploadDefaultsDataMapAddressForOldDaemon(): void
    {
        // Pre-0.6.1 daemons don't return data_map_address; field defaults to "".
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'data_map' => 'deadbeef',
                'chunks_stored' => 2,
            ]),
        ]);
        $client = $this->createClient($mock);

        $result = $client->finalizeUpload('up1', ['qh1' => 'tx1']);

        $this->assertSame('deadbeef', $result->dataMap);
        $this->assertSame('', $result->dataMapAddress);
        $this->assertSame(2, $result->chunksStored);
    }

    public function testPrepareChunkUploadParsesWaveBatchResponse(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'address' => 'aa' . str_repeat('00', 31),
                'already_stored' => false,
                'upload_id' => 'chunk-1',
                'payment_type' => 'wave_batch',
                'payments' => [
                    ['quote_hash' => 'qh1', 'rewards_address' => 'ra1', 'amount' => '100'],
                    ['quote_hash' => 'qh2', 'rewards_address' => 'ra2', 'amount' => '100'],
                ],
                'total_amount' => '200',
                'payment_vault_address' => '0xvault',
                'payment_token_address' => '0xtoken',
                'rpc_url' => 'http://localhost:8545',
            ]),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);

        $result = $client->prepareChunkUpload('hello');

        // Request: bytes must arrive base64-encoded under `data`.
        $body = json_decode((string) $history[0]['request']->getBody(), true);
        $this->assertSame(base64_encode('hello'), $body['data']);

        $this->assertFalse($result->alreadyStored);
        $this->assertSame('chunk-1', $result->uploadId);
        $this->assertSame('wave_batch', $result->paymentType);
        $this->assertCount(2, $result->payments);
        $this->assertSame('qh1', $result->payments[0]->quoteHash);
        $this->assertSame('100', $result->payments[1]->amount);
        $this->assertSame('200', $result->totalAmount);
        $this->assertSame('0xvault', $result->paymentVaultAddress);
        $this->assertSame('http://localhost:8545', $result->rpcUrl);
    }

    public function testPrepareChunkUploadAlreadyStoredOmitsPaymentFields(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'address' => 'bb' . str_repeat('11', 31),
                'already_stored' => true,
                // no upload_id, no payments, no payment_type, etc.
            ]),
        ]);
        $client = $this->createClient($mock);

        $result = $client->prepareChunkUpload('already-on-network');

        $this->assertTrue($result->alreadyStored);
        $this->assertNotSame('', $result->address, 'address must still be populated');
        $this->assertSame('', $result->uploadId);
        $this->assertSame([], $result->payments);
        $this->assertSame('', $result->totalAmount);
        $this->assertSame('', $result->paymentType);
    }

    public function testFinalizeChunkUploadReturnsAddress(): void
    {
        $addr = 'cc' . str_repeat('22', 31);
        $mock = new MockHandler([
            $this->jsonResponse(200, ['address' => $addr]),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);

        $result = $client->finalizeChunkUpload('chunk-1', [
            'qh1' => 'tx1',
            'qh2' => 'tx2',
        ]);

        $body = json_decode((string) $history[0]['request']->getBody(), true);
        $this->assertSame('chunk-1', $body['upload_id']);
        $this->assertSame(['qh1' => 'tx1', 'qh2' => 'tx2'], $body['tx_hashes']);

        $this->assertSame($addr, $result);
        $this->assertSame(64, strlen($result));
    }
}
