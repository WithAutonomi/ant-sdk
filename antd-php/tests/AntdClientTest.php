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
use Autonomi\Antd\Models\PaymentMode;
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
     * $history. Used by the external-signer tests and the payment-mode
     * forwarding tests to assert on the JSON body the SDK actually sends.
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

    // --- PaymentMode ---

    public function testPaymentModeWireValues(): void
    {
        $this->assertSame('auto', PaymentMode::Auto->value);
        $this->assertSame('merkle', PaymentMode::Merkle->value);
        $this->assertSame('single', PaymentMode::Single->value);
    }

    // --- Data Public ---

    public function testDataPutPublic(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'address' => 'abc123',
                'chunks_stored' => 3,
                'payment_mode_used' => 'single',
            ]),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);
        $result = $client->dataPutPublic('hello');
        $this->assertSame('abc123', $result->address);
        $this->assertSame(3, $result->chunksStored);
        $this->assertSame('single', $result->paymentModeUsed);

        $body = json_decode((string) $history[0]['request']->getBody(), true);
        $this->assertSame('auto', $body['payment_mode']);
    }

    public function testDataPutPublicForwardsPaymentMode(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'address' => 'abc',
                'chunks_stored' => 1,
                'payment_mode_used' => 'merkle',
            ]),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);
        $client->dataPutPublic('hello', PaymentMode::Merkle);

        $body = json_decode((string) $history[0]['request']->getBody(), true);
        $this->assertSame('merkle', $body['payment_mode']);
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

    public function testDataPut(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'data_map' => 'dm123',
                'chunks_stored' => 2,
                'payment_mode_used' => 'merkle',
            ]),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);
        $result = $client->dataPut('secret', PaymentMode::Merkle);
        $this->assertSame('dm123', $result->dataMap);
        $this->assertSame(2, $result->chunksStored);
        $this->assertSame('merkle', $result->paymentModeUsed);

        $request = $history[0]['request'];
        $this->assertSame('POST', $request->getMethod());
        $this->assertStringEndsWith('/v1/data', (string) $request->getUri());
        $body = json_decode((string) $request->getBody(), true);
        $this->assertSame('merkle', $body['payment_mode']);
    }

    public function testDataGet(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, ['data' => base64_encode('secret')]),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);
        $data = $client->dataGet('dm123');
        $this->assertSame('secret', $data);

        $request = $history[0]['request'];
        $this->assertSame('POST', $request->getMethod());
        $this->assertStringEndsWith('/v1/data/get', (string) $request->getUri());
        $body = json_decode((string) $request->getBody(), true);
        $this->assertSame('dm123', $body['data_map']);
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
        $history = [];
        $client = $this->createRecordingClient($mock, $history);
        $est = $client->dataCost('test', PaymentMode::Single);
        $this->assertSame('50', $est->cost);
        $this->assertSame(4, $est->fileSize);
        $this->assertSame(3, $est->chunkCount);
        $this->assertSame('150000000000000', $est->estimatedGasCostWei);
        $this->assertSame('single', $est->paymentMode);

        $body = json_decode((string) $history[0]['request']->getBody(), true);
        $this->assertSame('single', $body['payment_mode']);
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

    // --- Files public ---

    public function testFilePutPublic(): void
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
        $history = [];
        $client = $this->createRecordingClient($mock, $history);
        $result = $client->filePutPublic('/tmp/test.txt');
        $this->assertSame('file1', $result->address);
        $this->assertSame('1000', $result->storageCostAtto);
        $this->assertSame('42', $result->gasCostWei);
        $this->assertSame(3, $result->chunksStored);
        $this->assertSame('auto', $result->paymentModeUsed);

        $request = $history[0]['request'];
        $this->assertStringEndsWith('/v1/files/public', (string) $request->getUri());
        $body = json_decode((string) $request->getBody(), true);
        $this->assertSame('auto', $body['payment_mode']);
    }

    public function testFileGetPublic(): void
    {
        $mock = new MockHandler([
            new Response(200),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);
        $client->fileGetPublic('file1', '/tmp/out.txt');

        $request = $history[0]['request'];
        $this->assertSame('POST', $request->getMethod());
        $this->assertStringEndsWith('/v1/files/public/get', (string) $request->getUri());
        $body = json_decode((string) $request->getBody(), true);
        $this->assertSame('file1', $body['address']);
        $this->assertSame('/tmp/out.txt', $body['dest_path']);
    }

    // --- Files private ---

    public function testFilePut(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(200, [
                'data_map' => 'fdm1',
                'storage_cost_atto' => '900',
                'gas_cost_wei' => '42',
                'chunks_stored' => 2,
                'payment_mode_used' => 'merkle',
            ]),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);
        $result = $client->filePut('/tmp/secret.txt', PaymentMode::Merkle);
        $this->assertSame('fdm1', $result->dataMap);
        $this->assertSame('900', $result->storageCostAtto);
        $this->assertSame(2, $result->chunksStored);
        $this->assertSame('merkle', $result->paymentModeUsed);

        $request = $history[0]['request'];
        $this->assertSame('POST', $request->getMethod());
        $this->assertStringEndsWith('/v1/files', (string) $request->getUri());
        $body = json_decode((string) $request->getBody(), true);
        $this->assertSame('merkle', $body['payment_mode']);
    }

    public function testFileGet(): void
    {
        $mock = new MockHandler([
            new Response(200),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);
        $client->fileGet('fdm1', '/tmp/priv-out.txt');

        $request = $history[0]['request'];
        $this->assertSame('POST', $request->getMethod());
        $this->assertStringEndsWith('/v1/files/get', (string) $request->getUri());
        $body = json_decode((string) $request->getBody(), true);
        $this->assertSame('fdm1', $body['data_map']);
        $this->assertSame('/tmp/priv-out.txt', $body['dest_path']);
    }

    // --- File cost ---

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
        $history = [];
        $client = $this->createRecordingClient($mock, $history);
        $est = $client->fileCost('/tmp/test.txt', true, PaymentMode::Single);
        $this->assertSame('1000', $est->cost);
        $this->assertSame(4096, $est->fileSize);

        $body = json_decode((string) $history[0]['request']->getBody(), true);
        $this->assertSame('single', $body['payment_mode']);
        $this->assertTrue($body['is_public']);
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
