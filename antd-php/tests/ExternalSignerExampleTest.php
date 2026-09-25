<?php

declare(strict_types=1);

namespace Autonomi\Antd\Tests;

use Autonomi\Antd\AntdClient;
use Autonomi\Antd\Errors\PartialUploadError;
use Autonomi\Antd\Models\FinalizeUploadResult;
use GuzzleHttp\Client;
use GuzzleHttp\Handler\MockHandler;
use GuzzleHttp\HandlerStack;
use GuzzleHttp\Middleware;
use GuzzleHttp\Psr7\Response;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

// Defines finalizeWithRetry(); the example's main block only runs when the
// file is executed directly.
require_once __DIR__ . '/../examples/07-external-signer.php';

/**
 * finalizeWithRetry() from examples/07-external-signer.php, driven through a
 * real AntdClient over Guzzle's MockHandler. The helper may only repeat the
 * same finalize call: whenever it stops it rethrows the original
 * PartialUploadError, and it never re-prepares or pays.
 */
class ExternalSignerExampleTest extends TestCase
{
    /** @var list<array{request: \Psr\Http\Message\RequestInterface}> */
    private array $history = [];

    /** @var list<int> */
    private array $sleeps = [];

    private function client(Response ...$responses): AntdClient
    {
        $stack = HandlerStack::create(new MockHandler($responses));
        $stack->push(Middleware::history($this->history));
        return new AntdClient('http://localhost:8082', 300.0, new Client(['handler' => $stack]));
    }

    /** A PARTIAL_UPLOAD 502; $retryable is the raw JSON member value, or null to omit it. */
    private function partial(int $stored, int $failed, int $total, ?string $retryable): Response
    {
        $json = sprintf(
            '{"error":"Partial upload: %1$d/%3$d chunks stored, %2$d failed after retries","code":"PARTIAL_UPLOAD",'
            . '"chunks_stored":%1$d,"chunks_failed":%2$d,"total_chunks":%3$d%4$s}',
            $stored,
            $failed,
            $total,
            $retryable === null ? '' : ',"retryable":' . $retryable,
        );
        return new Response(502, ['Content-Type' => 'application/json'], $json);
    }

    private function finalized(int $chunks): Response
    {
        return new Response(200, ['Content-Type' => 'application/json'], (string) json_encode([
            'data_map' => 'dm',
            'data_map_address' => 'addr',
            'chunks_stored' => $chunks,
        ]));
    }

    private function retry(AntdClient $client, int $maxAttempts = 5): FinalizeUploadResult
    {
        return \finalizeWithRetry(
            $client,
            'up1',
            ['qh1' => 'tx1'],
            $maxAttempts,
            function (int $seconds): void {
                $this->sleeps[] = $seconds;
            },
        );
    }

    /** Run the helper and return the PartialUploadError it rethrows, exactly as thrown. */
    private function runExpectingPartialUpload(AntdClient $client, int $maxAttempts = 5): PartialUploadError
    {
        try {
            $this->retry($client, $maxAttempts);
        } catch (PartialUploadError $e) {
            $this->assertSame(PartialUploadError::class, $e::class, 'the typed error is rethrown, not wrapped');
            $this->assertNull($e->getPrevious());
            return $e;
        }
        $this->fail('Expected finalizeWithRetry() to rethrow PartialUploadError');
    }

    /** Every request was the same finalize call: nothing was prepared, paid or re-signed. */
    private function assertOnlyTheSameFinalize(int $calls): void
    {
        $this->assertCount($calls, $this->history);
        foreach ($this->history as $entry) {
            $request = $entry['request'];
            $this->assertSame('POST', $request->getMethod());
            $this->assertSame('/v1/upload/finalize', $request->getUri()->getPath());
            $body = json_decode((string) $request->getBody(), true);
            $this->assertSame('up1', $body['upload_id']);
            $this->assertSame(['qh1' => 'tx1'], $body['tx_hashes']);
        }
    }

    public function testRetriesTheSameFinalizeUntilComplete(): void
    {
        $this->expectOutputRegex('/retrying against the same payment/');
        $client = $this->client(
            $this->partial(5, 3, 8, 'true'),
            $this->partial(7, 1, 8, 'true'),
            $this->finalized(8),
        );

        $result = $this->retry($client);

        $this->assertSame(8, $result->chunksStored);
        $this->assertOnlyTheSameFinalize(3);
        $this->assertSame([2, 4], $this->sleeps);
    }

    public function testExhaustedAttemptsRethrowTheTypedError(): void
    {
        $this->expectOutputRegex('/finalize gave up after 3 attempt\(s\)/');
        $client = $this->client(
            $this->partial(1, 7, 8, 'true'),
            $this->partial(2, 6, 8, 'true'),
            $this->partial(3, 5, 8, 'true'),
            $this->finalized(8),  // never reached
        );

        $e = $this->runExpectingPartialUpload($client, maxAttempts: 3);

        $this->assertTrue($e->retryable);
        $this->assertSame(3, $e->chunksStored);
        $this->assertSame(5, $e->chunksFailed);
        $this->assertOnlyTheSameFinalize(3);
        $this->assertSame([2, 4], $this->sleeps);
    }

    public function testStalledRetryRethrowsTheTypedError(): void
    {
        $this->expectOutputRegex('/finalize stalled after 2 attempt\(s\)/');
        $client = $this->client(
            $this->partial(5, 3, 8, 'true'),
            $this->partial(5, 3, 8, 'true'),
            $this->finalized(8),  // never reached
        );

        $e = $this->runExpectingPartialUpload($client);

        $this->assertTrue($e->retryable);
        $this->assertSame(3, $e->chunksFailed);
        $this->assertOnlyTheSameFinalize(2);
        $this->assertSame([2], $this->sleeps);
    }

    public function testConfirmedNonRetentionRethrowsWithoutRetrying(): void
    {
        $this->expectOutputRegex('/retained nothing: re-prepare/');
        $client = $this->client(
            $this->partial(5, 3, 8, 'false'),
            $this->finalized(8),  // never reached
        );

        $e = $this->runExpectingPartialUpload($client);

        $this->assertFalse($e->retryable);
        $this->assertTrue($e->retentionKnown);
        $this->assertOnlyTheSameFinalize(1);
        $this->assertSame([], $this->sleeps);
    }

    /** @return array<string, array{?string}> */
    public static function unknownRetentionProvider(): array
    {
        return [
            'missing (antd < 0.14.0)' => [null],
            'null' => ['null'],
            'quoted true' => ['"true"'],
            'integer 1' => ['1'],
        ];
    }

    #[DataProvider('unknownRetentionProvider')]
    public function testUnknownRetentionStopsWithoutRetryingOrPaying(?string $retryable): void
    {
        $this->expectOutputRegex('/did not say whether it kept the paid attempt: stopping/');
        $client = $this->client(
            $this->partial(5, 3, 8, $retryable),
            $this->finalized(8),  // never reached
        );

        $e = $this->runExpectingPartialUpload($client);

        $this->assertFalse($e->retryable);
        $this->assertFalse($e->retentionKnown);
        $this->assertSame(5, $e->chunksStored);
        $this->assertSame(3, $e->chunksFailed);
        $this->assertOnlyTheSameFinalize(1);
        $this->assertSame([], $this->sleeps);
    }
}
