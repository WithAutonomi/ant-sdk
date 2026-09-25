<?php

declare(strict_types=1);

namespace Autonomi\Antd\Tests;

use Autonomi\Antd\AntdClient;
use Autonomi\Antd\Errors\AntdError;
use Autonomi\Antd\Errors\NotFoundError;
use Autonomi\Antd\Errors\BadRequestError;
use Autonomi\Antd\Errors\PaymentError;
use Autonomi\Antd\Errors\InternalError;
use Autonomi\Antd\Errors\NetworkError;
use Autonomi\Antd\Errors\TooLargeError;
use Autonomi\Antd\Errors\AlreadyExistsError;
use Autonomi\Antd\Errors\ErrorFactory;
use Autonomi\Antd\Errors\PartialUploadError;
use Autonomi\Antd\Models\PaymentMode;
use GuzzleHttp\Client;
use GuzzleHttp\Handler\MockHandler;
use GuzzleHttp\HandlerStack;
use GuzzleHttp\Middleware;
use GuzzleHttp\Psr7\Request;
use GuzzleHttp\Psr7\Response;
use PHPUnit\Framework\Attributes\DataProvider;
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

    public function testDataStreamPublic(): void
    {
        $mock = new MockHandler([
            new Response(200, ['Content-Length' => '5'], 'hello'),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);
        $stream = $client->dataStreamPublic('abc123');
        $this->assertInstanceOf(\Psr\Http\Message\StreamInterface::class, $stream);
        $this->assertSame('hello', (string) $stream);

        $request = $history[0]['request'];
        $this->assertSame('GET', $request->getMethod());
        $this->assertStringEndsWith('/v1/data/public/abc123/stream', (string) $request->getUri());
    }

    public function testDataStreamPublicErrorThrows(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(404, ['error' => 'not found', 'code' => 'NOT_FOUND']),
        ]);
        $client = $this->createClient($mock);
        $this->expectException(NotFoundError::class);
        $this->expectExceptionMessage('not found');
        $client->dataStreamPublic('missing');
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

    public function testDataStream(): void
    {
        $mock = new MockHandler([
            new Response(200, ['Content-Length' => '6'], 'secret'),
        ]);
        $history = [];
        $client = $this->createRecordingClient($mock, $history);
        $stream = $client->dataStream('dm123');
        $this->assertInstanceOf(\Psr\Http\Message\StreamInterface::class, $stream);
        $this->assertSame('secret', (string) $stream);

        $request = $history[0]['request'];
        $this->assertSame('POST', $request->getMethod());
        $this->assertStringEndsWith('/v1/data/stream', (string) $request->getUri());
        $body = json_decode((string) $request->getBody(), true);
        $this->assertSame('dm123', $body['data_map']);
    }

    public function testDataStreamErrorThrows(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(404, ['error' => 'not found', 'code' => 'NOT_FOUND']),
        ]);
        $client = $this->createClient($mock);
        $this->expectException(NotFoundError::class);
        $this->expectExceptionMessage('not found');
        $client->dataStream('missing');
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

    // --- Partial upload (PARTIAL_UPLOAD on a 502) ---

    public function testPartialUploadErrorCarriesCounts(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(502, [
                'error' => 'Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)',
                'code' => 'PARTIAL_UPLOAD',
                'chunks_stored' => 300,
                'chunks_failed' => 12,
                'total_chunks' => 312,
                'retryable' => true,
            ]),
        ]);
        $client = $this->createClient($mock);
        try {
            $client->finalizeUpload('up1', ['qh1' => 'tx1']);
            $this->fail('Expected PartialUploadError');
        } catch (PartialUploadError $e) {
            $this->assertSame(300, $e->chunksStored);
            $this->assertSame(12, $e->chunksFailed);
            $this->assertSame(312, $e->totalChunks);
            $this->assertTrue($e->retryable, 'retryable must come from the body flag');
            $this->assertTrue($e->retentionKnown);
            $this->assertSame(502, $e->statusCode);
            $this->assertStringContainsString('Partial upload: 300/312 chunks stored', $e->getMessage());
        }
    }

    public function testPartialUploadErrorRetryableDefaultsFalse(): void
    {
        // An older daemon (< 0.14.0) never sends `retryable`; the flag must read
        // false so callers never loop on an upload_id, and retention must read
        // unknown (not confirmed non-retention) so they never pay again on it.
        $mock = new MockHandler([
            $this->jsonResponse(502, [
                'error' => 'Partial upload: 300/312 chunks stored, 12 failed after retries',
                'code' => 'PARTIAL_UPLOAD',
                'chunks_stored' => 300,
                'chunks_failed' => 12,
                'total_chunks' => 312,
            ]),
        ]);
        $client = $this->createClient($mock);
        try {
            $client->finalizeUpload('up1', ['qh1' => 'tx1']);
            $this->fail('Expected PartialUploadError');
        } catch (PartialUploadError $e) {
            $this->assertFalse($e->retryable);
            $this->assertFalse($e->retentionKnown);
            $this->assertSame(300, $e->chunksStored);
            $this->assertSame(12, $e->chunksFailed);
            $this->assertSame(312, $e->totalChunks);
        }
    }

    public function testPartialUploadErrorIsCatchableAsNetworkError(): void
    {
        // PartialUploadError extends NetworkError (the 502 mapping), so code
        // written before the typed error keeps catching it.
        $mock = new MockHandler([
            $this->jsonResponse(502, [
                'error' => 'Partial upload: 1/2 chunks stored, 1 failed after retries',
                'code' => 'PARTIAL_UPLOAD',
                'chunks_stored' => 1,
                'chunks_failed' => 1,
                'total_chunks' => 2,
                'retryable' => true,
            ]),
        ]);
        $client = $this->createClient($mock);
        $this->expectException(NetworkError::class);
        $client->finalizeChunkUpload('chunk-1', ['qh1' => 'tx1']);
    }

    public function testPartialUploadErrorOnAsyncFinalize(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(502, [
                'error' => 'Partial upload: 5/8 chunks stored, 3 failed after retries',
                'code' => 'PARTIAL_UPLOAD',
                'chunks_stored' => 5,
                'chunks_failed' => 3,
                'total_chunks' => 8,
                'retryable' => true,
            ]),
        ]);
        $client = $this->createClient($mock);
        try {
            $client->finalizeUploadAsync('up1', ['qh1' => 'tx1'])->wait();
            $this->fail('Expected PartialUploadError');
        } catch (PartialUploadError $e) {
            $this->assertSame(5, $e->chunksStored);
            $this->assertSame(3, $e->chunksFailed);
            $this->assertSame(8, $e->totalChunks);
            $this->assertTrue($e->retryable);
        }
    }

    public function testPlain502StillMapsToNetworkError(): void
    {
        $mock = new MockHandler([
            $this->jsonResponse(502, ['error' => 'upstream unreachable', 'code' => 'NETWORK_ERROR']),
        ]);
        $client = $this->createClient($mock);
        try {
            $client->finalizeUpload('up1', []);
            $this->fail('Expected NetworkError');
        } catch (NetworkError $e) {
            $this->assertNotInstanceOf(PartialUploadError::class, $e);
        }
    }

    public function testErrorFactoryFromResponseKeepsStatusMappingForOtherCodes(): void
    {
        $this->assertInstanceOf(NotFoundError::class, ErrorFactory::fromResponse(404, 'gone', ['error' => 'gone', 'code' => 'NOT_FOUND']));
        $this->assertInstanceOf(NetworkError::class, ErrorFactory::fromResponse(502, 'down', null));
        $this->assertNotInstanceOf(PartialUploadError::class, ErrorFactory::fromResponse(502, 'down', null));

        $e = ErrorFactory::fromResponse(502, 'partial', ['code' => 'PARTIAL_UPLOAD', 'retryable' => 'yes']);
        $this->assertInstanceOf(PartialUploadError::class, $e);
        $this->assertFalse($e->retryable, 'only a JSON true counts as retryable');
        $this->assertFalse($e->retentionKnown, 'only a JSON boolean says whether anything was retained');
        $this->assertSame(0, $e->chunksStored);
        $this->assertSame(0, $e->chunksFailed);
        $this->assertSame(0, $e->totalChunks);
    }

    // --- Malformed error bodies ---
    //
    // The contract: only the string code "PARTIAL_UPLOAD" selects
    // PartialUploadError; a count is read only from a JSON non-negative
    // integer (anything else reads 0); `retryable` only from the JSON boolean
    // true; the message only from a string `error` (otherwise the raw body).
    // A malformed body never escapes as a TypeError; at worst it falls back
    // to the status-based error. Bodies are raw JSON so each literal reaches
    // json_decode() exactly as a daemon would send it.

    private function rawJsonResponse(int $status, string $json): Response
    {
        return new Response($status, ['Content-Type' => 'application/json'], $json);
    }

    /**
     * Run $call and return the AntdError it throws; a TypeError fails the
     * test by name instead of surfacing as a generic PHPUnit error.
     */
    private function catchAntdError(callable $call): AntdError
    {
        try {
            $call();
        } catch (AntdError $e) {
            return $e;
        } catch (\TypeError $e) {
            $this->fail('TypeError escaped the typed error contract: ' . $e->getMessage());
        }
        $this->fail('Expected an AntdError');
    }

    /** @return array<string, array{string}> JSON literals that are not a non-negative integer. */
    public static function malformedCountProvider(): array
    {
        return [
            'quoted number' => ['"1"'],
            'bool' => ['true'],
            'float' => ['1.5'],
            'negative' => ['-1'],
            'array' => ['["x"]'],
            'object' => ['{}'],
            'beyond int64' => ['18446744073709551616'],
        ];
    }

    /** @return array<string, array{string, string}> [field, literal] for every count field. */
    public static function malformedCountFieldProvider(): array
    {
        $cases = [];
        foreach (self::malformedCountProvider() as $label => [$literal]) {
            foreach (['chunks_stored', 'chunks_failed', 'total_chunks'] as $field) {
                $cases["{$field} {$label}"] = [$field, $literal];
            }
        }
        return $cases;
    }

    #[DataProvider('malformedCountFieldProvider')]
    public function testMalformedPartialUploadCountReadsZero(string $field, string $literal): void
    {
        $literals = ['chunks_stored' => '5', 'chunks_failed' => '3', 'total_chunks' => '8'];
        $literals[$field] = $literal;
        $json = sprintf(
            '{"error":"Partial upload: 5/8 chunks stored, 3 failed after retries","code":"PARTIAL_UPLOAD",'
            . '"chunks_stored":%s,"chunks_failed":%s,"total_chunks":%s,"retryable":true}',
            $literals['chunks_stored'],
            $literals['chunks_failed'],
            $literals['total_chunks'],
        );
        $client = $this->createClient(new MockHandler([$this->rawJsonResponse(502, $json)]));

        $e = $this->catchAntdError(fn() => $client->finalizeUpload('up1', ['qh1' => 'tx1']));

        $this->assertInstanceOf(PartialUploadError::class, $e);
        $expected = ['chunks_stored' => 5, 'chunks_failed' => 3, 'total_chunks' => 8];
        $expected[$field] = 0;
        $this->assertSame($expected['chunks_stored'], $e->chunksStored);
        $this->assertSame($expected['chunks_failed'], $e->chunksFailed);
        $this->assertSame($expected['total_chunks'], $e->totalChunks);
        $this->assertTrue($e->retryable, 'retryable is read from its own field');
        $this->assertStringContainsString('Partial upload: 5/8 chunks stored', $e->getMessage());
    }

    #[DataProvider('malformedCountProvider')]
    public function testErrorFactoryMalformedCountsReadZero(string $literal): void
    {
        $body = json_decode(
            sprintf('{"code":"PARTIAL_UPLOAD","chunks_stored":%1$s,"chunks_failed":%1$s,"total_chunks":%1$s}', $literal),
            true,
        );
        $this->assertIsArray($body);

        $e = ErrorFactory::fromResponse(502, 'partial', $body);

        $this->assertInstanceOf(PartialUploadError::class, $e);
        $this->assertSame(0, $e->chunksStored);
        $this->assertSame(0, $e->chunksFailed);
        $this->assertSame(0, $e->totalChunks);
    }

    public function testErrorFactoryKeepsNonNegativeIntegerCounts(): void
    {
        // The upper boundary comes from this platform's PHP_INT_MAX (int64 on
        // 64-bit builds, int32 on 32-bit ones), so it is valid everywhere.
        $body = json_decode(
            sprintf('{"code":"PARTIAL_UPLOAD","chunks_stored":0,"chunks_failed":7,"total_chunks":%d}', PHP_INT_MAX),
            true,
        );

        $e = ErrorFactory::fromResponse(502, 'partial', $body);

        $this->assertInstanceOf(PartialUploadError::class, $e);
        $this->assertSame(0, $e->chunksStored);
        $this->assertSame(7, $e->chunksFailed);
        $this->assertSame(PHP_INT_MAX, $e->totalChunks);
    }

    public function testErrorFactoryCountOnePastPhpIntMaxReadsZero(): void
    {
        // One past this platform's PHP_INT_MAX: json_decode() hands it back as a
        // float, which is not a JSON integer PHP can hold, so it reads 0.
        $max = (string) PHP_INT_MAX;
        $onePast = substr($max, 0, -1) . ((int) substr($max, -1) + 1);  // ...807 -> ...808, ...647 -> ...648
        $body = json_decode(
            sprintf('{"code":"PARTIAL_UPLOAD","chunks_stored":%1$s,"chunks_failed":%1$s,"total_chunks":%1$s}', $onePast),
            true,
        );
        $this->assertIsFloat($body['total_chunks'], 'the literal must overflow int on this platform');

        $e = ErrorFactory::fromResponse(502, 'partial', $body);

        $this->assertInstanceOf(PartialUploadError::class, $e);
        $this->assertSame(0, $e->chunksStored);
        $this->assertSame(0, $e->chunksFailed);
        $this->assertSame(0, $e->totalChunks);
    }

    /**
     * The `retryable` member as it appears in the body (null = absent), and
     * the [retryable, retentionKnown] it must produce.
     *
     * @return array<string, array{?string, bool, bool}>
     */
    public static function retryableFieldProvider(): array
    {
        return [
            'true: retained' => ['true', true, true],
            'false: confirmed not retained' => ['false', false, true],
            'missing (antd < 0.14.0): unknown' => [null, false, false],
            'null: unknown' => ['null', false, false],
            'quoted true: unknown' => ['"true"', false, false],
            'integer 1: unknown' => ['1', false, false],
        ];
    }

    #[DataProvider('retryableFieldProvider')]
    public function testRetryableAndRetentionKnownComeFromTheRetryableField(
        ?string $literal,
        bool $retryable,
        bool $retentionKnown,
    ): void {
        $json = sprintf(
            '{"error":"Partial upload: 1/2 chunks stored, 1 failed after retries","code":"PARTIAL_UPLOAD",'
            . '"chunks_stored":1,"chunks_failed":1,"total_chunks":2%s}',
            $literal === null ? '' : ',"retryable":' . $literal,
        );
        $client = $this->createClient(new MockHandler([$this->rawJsonResponse(502, $json)]));

        $e = $this->catchAntdError(fn() => $client->finalizeUpload('up1', ['qh1' => 'tx1']));

        $this->assertInstanceOf(PartialUploadError::class, $e);
        $this->assertSame($retryable, $e->retryable);
        $this->assertSame($retentionKnown, $e->retentionKnown);
        $this->assertSame(1, $e->chunksStored);
        $this->assertSame(1, $e->chunksFailed);
        $this->assertSame(2, $e->totalChunks);

        $direct = ErrorFactory::fromResponse(502, 'partial', json_decode($json, true));
        $this->assertInstanceOf(PartialUploadError::class, $direct);
        $this->assertSame($retryable, $direct->retryable);
        $this->assertSame($retentionKnown, $direct->retentionKnown);
    }

    public function testPartialUploadErrorConstructorKeepsRetryableImpliesRetentionKnown(): void
    {
        // Constructor calls written before retentionKnown existed keep working.
        $legacy = new PartialUploadError('m', 1, 1, 2, true);
        $this->assertTrue($legacy->retryable);
        $this->assertTrue($legacy->retentionKnown, 'retryable implies retentionKnown');

        $forced = new PartialUploadError('m', retryable: true, retentionKnown: false);
        $this->assertTrue($forced->retentionKnown, 'the invariant holds even when asked otherwise');

        $unknown = new PartialUploadError('m');
        $this->assertFalse($unknown->retryable);
        $this->assertFalse($unknown->retentionKnown);

        $notRetained = new PartialUploadError('m', 1, 1, 2, false, true);
        $this->assertFalse($notRetained->retryable);
        $this->assertTrue($notRetained->retentionKnown);
    }

    /** @return array<string, array{string}> */
    public static function nonStringCodeProvider(): array
    {
        return [
            'object' => ['{}'],
            'array' => ['[]'],
            'null' => ['null'],
            'number' => ['1'],
        ];
    }

    #[DataProvider('nonStringCodeProvider')]
    public function testNonStringCodeKeepsStatusMapping(string $literal): void
    {
        $json = sprintf(
            '{"error":"upstream unreachable","code":%s,"chunks_stored":1,"chunks_failed":1,"total_chunks":2,"retryable":true}',
            $literal,
        );
        $client = $this->createClient(new MockHandler([$this->rawJsonResponse(502, $json)]));

        $e = $this->catchAntdError(fn() => $client->finalizeUpload('up1', ['qh1' => 'tx1']));

        $this->assertInstanceOf(NetworkError::class, $e);
        $this->assertNotInstanceOf(PartialUploadError::class, $e);
        $this->assertSame(502, $e->statusCode);
        $this->assertStringContainsString('upstream unreachable', $e->getMessage());

        $direct = ErrorFactory::fromResponse(502, 'upstream unreachable', json_decode($json, true));
        $this->assertInstanceOf(NetworkError::class, $direct);
        $this->assertNotInstanceOf(PartialUploadError::class, $direct);
    }

    public function testTopLevelArrayBodyKeepsStatusMapping(): void
    {
        $client = $this->createClient(new MockHandler([$this->rawJsonResponse(502, '[]')]));

        $e = $this->catchAntdError(fn() => $client->finalizeUpload('up1', ['qh1' => 'tx1']));

        $this->assertInstanceOf(NetworkError::class, $e);
        $this->assertNotInstanceOf(PartialUploadError::class, $e);
        $this->assertStringContainsString('[]', $e->getMessage(), 'message falls back to the raw body');

        $direct = ErrorFactory::fromResponse(502, '[]', []);
        $this->assertInstanceOf(NetworkError::class, $direct);
        $this->assertNotInstanceOf(PartialUploadError::class, $direct);
    }

    /** @return array<string, array{string}> */
    public static function nonStringErrorProvider(): array
    {
        return [
            'object' => ['{}'],
            'number' => ['1'],
            'null' => ['null'],
        ];
    }

    #[DataProvider('nonStringErrorProvider')]
    public function testNonStringErrorOnPartialUploadUsesRawBody(string $literal): void
    {
        $json = sprintf(
            '{"error":%s,"code":"PARTIAL_UPLOAD","chunks_stored":1,"chunks_failed":1,"total_chunks":2,"retryable":true}',
            $literal,
        );
        $client = $this->createClient(new MockHandler([$this->rawJsonResponse(502, $json)]));

        $e = $this->catchAntdError(fn() => $client->finalizeUpload('up1', ['qh1' => 'tx1']));

        $this->assertInstanceOf(PartialUploadError::class, $e);
        $this->assertSame(1, $e->chunksStored);
        $this->assertSame(1, $e->chunksFailed);
        $this->assertSame(2, $e->totalChunks);
        $this->assertTrue($e->retryable);
        $this->assertStringContainsString($json, $e->getMessage());
    }

    /** @return array<string, array{int, class-string<AntdError>, string}> */
    public static function nonStringErrorStatusProvider(): array
    {
        $cases = [];
        foreach ([400 => BadRequestError::class, 502 => NetworkError::class] as $status => $class) {
            foreach (self::nonStringErrorProvider() as $label => [$literal]) {
                $cases["{$status} {$label}"] = [$status, $class, $literal];
            }
        }
        return $cases;
    }

    /**
     * @param class-string<AntdError> $class
     */
    #[DataProvider('nonStringErrorStatusProvider')]
    public function testNonStringErrorOnPlainStatusUsesRawBody(int $status, string $class, string $literal): void
    {
        $json = sprintf('{"error":%s}', $literal);
        $client = $this->createClient(new MockHandler([$this->rawJsonResponse($status, $json)]));

        $e = $this->catchAntdError(fn() => $client->health());

        $this->assertInstanceOf($class, $e);
        $this->assertNotInstanceOf(PartialUploadError::class, $e);
        $this->assertSame($status, $e->statusCode);
        $this->assertStringContainsString($json, $e->getMessage());
    }

    public function testNonStringErrorOnAsyncAndStreamPaths(): void
    {
        // errorFromResponse() backs all three request paths; prove the async
        // rejection handler and the streaming path degrade the same way.
        $json = '{"error":{},"code":"PARTIAL_UPLOAD","chunks_stored":1,"chunks_failed":1,"total_chunks":2,"retryable":true}';
        $client = $this->createClient(new MockHandler([$this->rawJsonResponse(502, $json)]));
        $e = $this->catchAntdError(fn() => $client->finalizeUploadAsync('up1', ['qh1' => 'tx1'])->wait());
        $this->assertInstanceOf(PartialUploadError::class, $e);
        $this->assertSame(1, $e->chunksFailed);

        $client = $this->createClient(new MockHandler([$this->rawJsonResponse(400, '{"error":["x"]}')]));
        $e = $this->catchAntdError(fn() => $client->dataStream('datamap'));
        $this->assertInstanceOf(BadRequestError::class, $e);
        $this->assertStringContainsString('{"error":["x"]}', $e->getMessage());
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
                'total_chunks' => 3,
                'already_stored_count' => 1,
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
        // already-stored preflight (added in antd 0.10.0)
        $this->assertSame(3, $result->totalChunks);
        $this->assertSame(1, $result->alreadyStoredCount);
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
