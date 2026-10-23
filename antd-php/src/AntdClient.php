<?php

declare(strict_types=1);

namespace Autonomi\Antd;

use GuzzleHttp\Client;
use GuzzleHttp\Exception\GuzzleException;
use GuzzleHttp\Promise\PromiseInterface;
use Autonomi\Antd\Errors\AntdError;
use Autonomi\Antd\Errors\ErrorFactory;
use Autonomi\Antd\Errors\PartialUploadError;
use Autonomi\Antd\Models\DataPutPublicResult;
use Autonomi\Antd\Models\DataPutResult;
use Autonomi\Antd\Models\FilePutPublicResult;
use Autonomi\Antd\Models\FilePutResult;
use Autonomi\Antd\Models\FinalizeUploadResult;
use Autonomi\Antd\Models\HealthStatus;
use Autonomi\Antd\Models\PaymentInfo;
use Autonomi\Antd\Models\PaymentMode;
use Autonomi\Antd\Models\PointerController;
use Autonomi\Antd\Models\PointerCounter;
use Autonomi\Antd\Models\PointerFinalState;
use Autonomi\Antd\Models\PointerFinality;
use Autonomi\Antd\Models\PointerFinalityStatus;
use Autonomi\Antd\Models\PointerFinalizeResult;
use Autonomi\Antd\Models\PointerPrepareRequest;
use Autonomi\Antd\Models\PointerPrepareResult;
use Autonomi\Antd\Models\PointerRecord;
use Autonomi\Antd\Models\PointerTarget;
use Autonomi\Antd\Models\PointerTargetKind;
use Autonomi\Antd\Models\PointerTransferResult;
use Autonomi\Antd\Models\PointerWriteResult;
use Autonomi\Antd\Models\PrepareChunkResult;
use Autonomi\Antd\Models\PrepareUploadResult;
use Autonomi\Antd\Models\PutResult;
use Autonomi\Antd\Models\SignedQuoteEntry;
use Autonomi\Antd\Models\UploadCostEstimate;

/**
 * REST client for the antd daemon.
 *
 * Naming convention (post v1.0):
 *   - Unqualified verb (`dataPut`, `dataGet`, `filePut`, `fileGet`) = private —
 *     the DataMap is returned to the caller and NOT stored on-network.
 *   - `_public` suffix = public — the DataMap is stored on-network as an
 *     extra chunk; the call returns the shareable address.
 */
class AntdClient
{
    // buildManifest(), decodeManifest(), decodeManifestLink() and their Async variants.
    use ManifestMethods;

    private Client $http;
    private string $baseUrl;

    public function __construct(
        string $baseUrl = 'http://localhost:8082',
        float $timeout = 300.0,
        ?Client $httpClient = null,
    ) {
        $this->baseUrl = rtrim($baseUrl, '/');
        $this->http = $httpClient ?? new Client([
            'base_uri' => $this->baseUrl,
            'timeout' => $timeout,
        ]);
    }

    /**
     * Create a client using daemon port discovery.
     * Falls back to http://localhost:8082 if discovery fails.
     *
     * @param float $timeout Request timeout in seconds.
     * @param \GuzzleHttp\Client|null $httpClient Optional HTTP client.
     * @return array{0: self, 1: string} [$client, $url]
     */
    public static function autoDiscover(float $timeout = 300.0, ?Client $httpClient = null): array
    {
        $url = DaemonDiscovery::discoverDaemonUrl();
        if ($url === '') {
            $url = 'http://localhost:8082';
        }
        $client = new self($url, $timeout, $httpClient);
        return [$client, $url];
    }

    // --- Internal helpers ---

    /**
     * An optional string field: null when the key is absent, null or empty
     * (an older daemon, or gRPC's empty string), the value as given otherwise.
     *
     * @param array<mixed>|null $json
     */
    private static function optString(?array $json, string $key): ?string
    {
        $value = $json[$key] ?? null;
        return is_string($value) && $value !== '' ? $value : null;
    }

    private function b64Encode(string $data): string
    {
        return base64_encode($data);
    }

    private function b64Decode(string $data): string
    {
        $decoded = base64_decode($data, true);
        if ($decoded === false) {
            throw new \RuntimeException('Failed to decode base64 data');
        }
        return $decoded;
    }

    /**
     * Map a non-2xx daemon response onto a typed {@see AntdError}.
     *
     * The body is parsed for the daemon's `{"error": "...", "code": "..."}`
     * envelope. The message is the `error` string, falling back to the raw
     * body when the body is not JSON or `error` is missing or not a string:
     * handing an object, number or bool on as the `string $message` would
     * raise a TypeError under strict_types instead of a typed error.
     * The decoded body is handed to {@see ErrorFactory::fromResponse()} so
     * codes that carry structured detail (`PARTIAL_UPLOAD`: chunk counts and
     * the `retryable` flag) survive the mapping.
     */
    private static function errorFromResponse(\Psr\Http\Message\ResponseInterface $response): AntdError
    {
        $responseBody = (string) $response->getBody();
        $parsed = json_decode($responseBody, true);
        $message = is_array($parsed) && is_string($parsed['error'] ?? null)
            ? $parsed['error']
            : $responseBody;
        return ErrorFactory::fromResponse(
            $response->getStatusCode(),
            $message,
            is_array($parsed) ? $parsed : null,
        );
    }

    /**
     * @return array<string, mixed>|null
     * @throws AntdError
     */
    private function doJson(string $method, string $path, ?array $body = null): ?array
    {
        $options = [];
        if ($body !== null) {
            $options['json'] = $body;
        }

        try {
            $response = $this->http->request($method, $this->baseUrl . $path, $options);
        } catch (\GuzzleHttp\Exception\ClientException|\GuzzleHttp\Exception\ServerException $e) {
            throw self::errorFromResponse($e->getResponse());
        }

        $responseBody = (string) $response->getBody();
        if ($responseBody === '') {
            return null;
        }

        return json_decode($responseBody, true);
    }

    /**
     * Issue a streaming request and return the response body as a PSR-7 stream.
     *
     * The body is read lazily (Guzzle `stream: true`), so memory stays constant
     * regardless of payload size — the caller pulls bytes via
     * {@see \Psr\Http\Message\StreamInterface::read()} / `eof()`.
     *
     * On a non-2xx response the (short) error body is fully read and parsed for
     * a `{"error": "..."}` envelope, mirroring {@see doJson()}.
     *
     * @param array<string, mixed>|null $body JSON request body, or null.
     * @return \Psr\Http\Message\StreamInterface
     * @throws AntdError
     */
    private function doStream(string $method, string $path, ?array $body = null): \Psr\Http\Message\StreamInterface
    {
        $options = ['stream' => true];
        if ($body !== null) {
            $options['json'] = $body;
        }

        try {
            $response = $this->http->request($method, $this->baseUrl . $path, $options);
        } catch (\GuzzleHttp\Exception\ClientException|\GuzzleHttp\Exception\ServerException $e) {
            throw self::errorFromResponse($e->getResponse());
        }

        return $response->getBody();
    }

    /**
     * @throws AntdError
     */
    private function doHead(string $path): int
    {
        try {
            $response = $this->http->request('HEAD', $this->baseUrl . $path);
            return $response->getStatusCode();
        } catch (\GuzzleHttp\Exception\ClientException|\GuzzleHttp\Exception\ServerException $e) {
            return $e->getResponse()->getStatusCode();
        }
    }

    /**
     * Async variant of doJson — returns a promise that resolves to decoded JSON (array|null).
     *
     * @return PromiseInterface<array<string, mixed>|null>
     */
    private function doJsonAsync(string $method, string $path, ?array $body = null): PromiseInterface
    {
        $options = [];
        if ($body !== null) {
            $options['json'] = $body;
        }

        return $this->http->requestAsync($method, $this->baseUrl . $path, $options)->then(
            function (\Psr\Http\Message\ResponseInterface $response) {
                $responseBody = (string) $response->getBody();
                if ($responseBody === '') {
                    return null;
                }
                return json_decode($responseBody, true);
            },
            function (\Throwable $e) {
                if ($e instanceof \GuzzleHttp\Exception\ClientException
                    || $e instanceof \GuzzleHttp\Exception\ServerException
                ) {
                    throw self::errorFromResponse($e->getResponse());
                }
                throw $e;
            },
        );
    }

    /**
     * Async variant of doHead — returns a promise that resolves to the HTTP status code.
     *
     * @return PromiseInterface<int>
     */
    private function doHeadAsync(string $path): PromiseInterface
    {
        return $this->http->requestAsync('HEAD', $this->baseUrl . $path)->then(
            function (\Psr\Http\Message\ResponseInterface $response) {
                return $response->getStatusCode();
            },
            function (\Throwable $e) {
                if ($e instanceof \GuzzleHttp\Exception\ClientException
                    || $e instanceof \GuzzleHttp\Exception\ServerException
                ) {
                    return $e->getResponse()->getStatusCode();
                }
                throw $e;
            },
        );
    }

    // --- Health ---

    /**
     * Check the antd daemon status.
     */
    public function health(): HealthStatus
    {
        return self::healthStatusFromJson($this->doJson('GET', '/health'));
    }

    /**
     * Async: Check the antd daemon status.
     *
     * @return PromiseInterface<HealthStatus>
     */
    public function healthAsync(): PromiseInterface
    {
        return $this->doJsonAsync('GET', '/health')->then(
            fn(?array $json) => self::healthStatusFromJson($json),
        );
    }

    /**
     * Convert a /health JSON response to a typed HealthStatus. Diagnostic
     * fields default to '' / 0 when talking to a pre-0.4.0 daemon.
     *
     * @param array<string, mixed>|null $json
     */
    private static function healthStatusFromJson(?array $json): HealthStatus
    {
        $json ??= [];
        return new HealthStatus(
            ok: ($json['status'] ?? '') === 'ok',
            network: $json['network'] ?? '',
            version: $json['version'] ?? '',
            evmNetwork: $json['evm_network'] ?? '',
            uptimeSeconds: (int)($json['uptime_seconds'] ?? 0),
            buildCommit: $json['build_commit'] ?? '',
            paymentTokenAddress: $json['payment_token_address'] ?? '',
            paymentVaultAddress: $json['payment_vault_address'] ?? '',
        );
    }

    // --- Data ---

    /**
     * Store public immutable data on the network.
     */
    public function dataPutPublic(string $data, PaymentMode $paymentMode = PaymentMode::Auto): DataPutPublicResult
    {
        $body = ['data' => $this->b64Encode($data), 'payment_mode' => $paymentMode->value];
        $json = $this->doJson('POST', '/v1/data/public', $body);
        return new DataPutPublicResult(
            address: (string)($json['address'] ?? ''),
            chunksStored: (int)($json['chunks_stored'] ?? 0),
            paymentModeUsed: (string)($json['payment_mode_used'] ?? ''),
            sha256: self::optString($json, 'sha256'),
        );
    }

    /**
     * Async: Store public immutable data on the network.
     *
     * @return PromiseInterface<DataPutPublicResult>
     */
    public function dataPutPublicAsync(string $data, PaymentMode $paymentMode = PaymentMode::Auto): PromiseInterface
    {
        $body = ['data' => $this->b64Encode($data), 'payment_mode' => $paymentMode->value];
        return $this->doJsonAsync('POST', '/v1/data/public', $body)->then(
            fn(?array $json) => new DataPutPublicResult(
                address: (string)($json['address'] ?? ''),
                chunksStored: (int)($json['chunks_stored'] ?? 0),
                paymentModeUsed: (string)($json['payment_mode_used'] ?? ''),
                sha256: self::optString($json, 'sha256'),
            ),
        );
    }

    /**
     * Retrieve public data by address.
     */
    public function dataGetPublic(string $address): string
    {
        $json = $this->doJson('GET', '/v1/data/public/' . $address);
        return $this->b64Decode($json['data'] ?? '');
    }

    /**
     * Async: Retrieve public data by address.
     *
     * @return PromiseInterface<string>
     */
    public function dataGetPublicAsync(string $address): PromiseInterface
    {
        return $this->doJsonAsync('GET', '/v1/data/public/' . $address)->then(
            fn(?array $json) => $this->b64Decode($json['data'] ?? ''),
        );
    }

    /**
     * Stream public data by address, decrypted, with constant memory.
     *
     * Streaming counterpart to {@link dataGetPublic()}: instead of buffering the
     * full payload in memory, the returned PSR-7 stream yields the decrypted
     * bytes lazily as they arrive from the daemon. Read from it with
     * `read()` / `eof()`, copy it with `\GuzzleHttp\Psr7\Utils::copyToStream()`,
     * or cast to string with `(string) $stream` to buffer (defeats streaming).
     *
     * @return \Psr\Http\Message\StreamInterface
     * @throws AntdError
     */
    public function dataStreamPublic(string $address): \Psr\Http\Message\StreamInterface
    {
        return $this->doStream('GET', '/v1/data/public/' . $address . '/stream');
    }

    /**
     * Store private encrypted data on the network. The returned DataMap is
     * the caller's key to retrieve the data later via {@link dataGet()}.
     */
    public function dataPut(string $data, PaymentMode $paymentMode = PaymentMode::Auto): DataPutResult
    {
        $body = ['data' => $this->b64Encode($data), 'payment_mode' => $paymentMode->value];
        $json = $this->doJson('POST', '/v1/data', $body);
        return new DataPutResult(
            dataMap: (string)($json['data_map'] ?? ''),
            chunksStored: (int)($json['chunks_stored'] ?? 0),
            paymentModeUsed: (string)($json['payment_mode_used'] ?? ''),
            sha256: self::optString($json, 'sha256'),
        );
    }

    /**
     * Async: Store private encrypted data on the network.
     *
     * @return PromiseInterface<DataPutResult>
     */
    public function dataPutAsync(string $data, PaymentMode $paymentMode = PaymentMode::Auto): PromiseInterface
    {
        $body = ['data' => $this->b64Encode($data), 'payment_mode' => $paymentMode->value];
        return $this->doJsonAsync('POST', '/v1/data', $body)->then(
            fn(?array $json) => new DataPutResult(
                dataMap: (string)($json['data_map'] ?? ''),
                chunksStored: (int)($json['chunks_stored'] ?? 0),
                paymentModeUsed: (string)($json['payment_mode_used'] ?? ''),
                sha256: self::optString($json, 'sha256'),
            ),
        );
    }

    /**
     * Retrieve private data using a caller-held DataMap.
     */
    public function dataGet(string $dataMap): string
    {
        $json = $this->doJson('POST', '/v1/data/get', ['data_map' => $dataMap]);
        return $this->b64Decode($json['data'] ?? '');
    }

    /**
     * Async: Retrieve private data using a caller-held DataMap.
     *
     * @return PromiseInterface<string>
     */
    public function dataGetAsync(string $dataMap): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/data/get', ['data_map' => $dataMap])->then(
            fn(?array $json) => $this->b64Decode($json['data'] ?? ''),
        );
    }

    /**
     * Stream private data from a caller-held DataMap, decrypted, with constant
     * memory.
     *
     * Streaming counterpart to {@link dataGet()}: instead of buffering the full
     * payload in memory, the returned PSR-7 stream yields the decrypted bytes
     * lazily as they arrive from the daemon. Read from it with `read()` /
     * `eof()`, copy it with `\GuzzleHttp\Psr7\Utils::copyToStream()`, or cast to
     * string with `(string) $stream` to buffer (defeats streaming).
     *
     * @return \Psr\Http\Message\StreamInterface
     * @throws AntdError
     */
    public function dataStream(string $dataMap): \Psr\Http\Message\StreamInterface
    {
        return $this->doStream('POST', '/v1/data/stream', ['data_map' => $dataMap]);
    }

    /**
     * Pre-upload cost breakdown for the given bytes.
     */
    public function dataCost(string $data, PaymentMode $paymentMode = PaymentMode::Auto): UploadCostEstimate
    {
        $json = $this->doJson('POST', '/v1/data/cost', [
            'data' => $this->b64Encode($data),
            'payment_mode' => $paymentMode->value,
        ]);
        return new UploadCostEstimate(
            cost: $json['cost'] ?? '',
            fileSize: (int) ($json['file_size'] ?? 0),
            chunkCount: (int) ($json['chunk_count'] ?? 0),
            estimatedGasCostWei: $json['estimated_gas_cost_wei'] ?? '',
            paymentMode: $json['payment_mode'] ?? '',
        );
    }

    /**
     * Async: pre-upload cost breakdown for the given bytes.
     *
     * @return PromiseInterface<UploadCostEstimate>
     */
    public function dataCostAsync(string $data, PaymentMode $paymentMode = PaymentMode::Auto): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/data/cost', [
            'data' => $this->b64Encode($data),
            'payment_mode' => $paymentMode->value,
        ])->then(
            fn(?array $json) => new UploadCostEstimate(
                cost: $json['cost'] ?? '',
                fileSize: (int) ($json['file_size'] ?? 0),
                chunkCount: (int) ($json['chunk_count'] ?? 0),
                estimatedGasCostWei: $json['estimated_gas_cost_wei'] ?? '',
                paymentMode: $json['payment_mode'] ?? '',
            ),
        );
    }

    // --- Chunks ---

    /**
     * Store a raw chunk on the network.
     */
    public function chunkPut(string $data): PutResult
    {
        $json = $this->doJson('POST', '/v1/chunks', [
            'data' => $this->b64Encode($data),
        ]);
        return new PutResult(
            cost: $json['cost'] ?? '',
            address: $json['address'] ?? '',
        );
    }

    /**
     * Async: Store a raw chunk on the network.
     *
     * @return PromiseInterface<PutResult>
     */
    public function chunkPutAsync(string $data): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/chunks', [
            'data' => $this->b64Encode($data),
        ])->then(
            fn(?array $json) => new PutResult(
                cost: $json['cost'] ?? '',
                address: $json['address'] ?? '',
            ),
        );
    }

    /**
     * Retrieve a chunk by address.
     */
    public function chunkGet(string $address): string
    {
        $json = $this->doJson('GET', '/v1/chunks/' . $address);
        return $this->b64Decode($json['data'] ?? '');
    }

    /**
     * Async: Retrieve a chunk by address.
     *
     * @return PromiseInterface<string>
     */
    public function chunkGetAsync(string $address): PromiseInterface
    {
        return $this->doJsonAsync('GET', '/v1/chunks/' . $address)->then(
            fn(?array $json) => $this->b64Decode($json['data'] ?? ''),
        );
    }

    // --- Files ---

    /**
     * Upload a local file to the network *publicly*. The DataMap is stored
     * on-network; the returned address is the shareable retrieval handle.
     */
    public function filePutPublic(string $path, PaymentMode $paymentMode = PaymentMode::Auto): FilePutPublicResult
    {
        $body = ['path' => $path, 'payment_mode' => $paymentMode->value];
        $json = $this->doJson('POST', '/v1/files/public', $body);
        return self::parseFilePutPublicResult($json ?? []);
    }

    /**
     * Async: Upload a local file to the network publicly.
     *
     * @return PromiseInterface<FilePutPublicResult>
     */
    public function filePutPublicAsync(string $path, PaymentMode $paymentMode = PaymentMode::Auto): PromiseInterface
    {
        $body = ['path' => $path, 'payment_mode' => $paymentMode->value];
        return $this->doJsonAsync('POST', '/v1/files/public', $body)->then(
            fn(?array $json) => self::parseFilePutPublicResult($json ?? []),
        );
    }

    private static function parseFilePutPublicResult(array $json): FilePutPublicResult
    {
        return new FilePutPublicResult(
            address: (string)($json['address'] ?? ''),
            storageCostAtto: (string)($json['storage_cost_atto'] ?? ''),
            gasCostWei: (string)($json['gas_cost_wei'] ?? ''),
            chunksStored: (int)($json['chunks_stored'] ?? 0),
            paymentModeUsed: (string)($json['payment_mode_used'] ?? ''),
            sha256: self::optString($json, 'sha256'),
        );
    }

    /**
     * Download a public file from an on-network DataMap address.
     */
    public function fileGetPublic(string $address, string $destPath): void
    {
        $this->doJson('POST', '/v1/files/public/get', [
            'address' => $address,
            'dest_path' => $destPath,
        ]);
    }

    /**
     * Async: Download a public file from an on-network DataMap address.
     *
     * @return PromiseInterface<null>
     */
    public function fileGetPublicAsync(string $address, string $destPath): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/files/public/get', [
            'address' => $address,
            'dest_path' => $destPath,
        ])->then(fn() => null);
    }

    /**
     * Upload a local file to the network *privately*. The returned DataMap is
     * the caller's key to retrieve the file later via {@link fileGet()}. The
     * DataMap itself is NOT stored on-network.
     */
    public function filePut(string $path, PaymentMode $paymentMode = PaymentMode::Auto): FilePutResult
    {
        $body = ['path' => $path, 'payment_mode' => $paymentMode->value];
        $json = $this->doJson('POST', '/v1/files', $body);
        return self::parseFilePutResult($json ?? []);
    }

    /**
     * Async: Upload a local file to the network privately.
     *
     * @return PromiseInterface<FilePutResult>
     */
    public function filePutAsync(string $path, PaymentMode $paymentMode = PaymentMode::Auto): PromiseInterface
    {
        $body = ['path' => $path, 'payment_mode' => $paymentMode->value];
        return $this->doJsonAsync('POST', '/v1/files', $body)->then(
            fn(?array $json) => self::parseFilePutResult($json ?? []),
        );
    }

    private static function parseFilePutResult(array $json): FilePutResult
    {
        return new FilePutResult(
            dataMap: (string)($json['data_map'] ?? ''),
            storageCostAtto: (string)($json['storage_cost_atto'] ?? ''),
            gasCostWei: (string)($json['gas_cost_wei'] ?? ''),
            chunksStored: (int)($json['chunks_stored'] ?? 0),
            paymentModeUsed: (string)($json['payment_mode_used'] ?? ''),
            sha256: self::optString($json, 'sha256'),
        );
    }

    /**
     * Download a private file from a caller-held DataMap into `$destPath`.
     */
    public function fileGet(string $dataMap, string $destPath): void
    {
        $this->doJson('POST', '/v1/files/get', [
            'data_map' => $dataMap,
            'dest_path' => $destPath,
        ]);
    }

    /**
     * Async: Download a private file from a caller-held DataMap.
     *
     * @return PromiseInterface<null>
     */
    public function fileGetAsync(string $dataMap, string $destPath): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/files/get', [
            'data_map' => $dataMap,
            'dest_path' => $destPath,
        ])->then(fn() => null);
    }

    // --- Wallet ---

    /**
     * Get the wallet's public address.
     *
     * @return array{address: string}
     * @throws AntdError if no wallet is configured (HTTP 400)
     */
    public function walletAddress(): array
    {
        $json = $this->doJson('GET', '/v1/wallet/address');
        return ['address' => $json['address'] ?? ''];
    }

    /**
     * Async: Get the wallet's public address.
     *
     * @return PromiseInterface<array{address: string}>
     */
    public function walletAddressAsync(): PromiseInterface
    {
        return $this->doJsonAsync('GET', '/v1/wallet/address')->then(
            fn(?array $json) => ['address' => $json['address'] ?? ''],
        );
    }

    /**
     * Get the wallet's token and gas balances.
     *
     * @return array{balance: string, gas_balance: string}
     * @throws AntdError if no wallet is configured (HTTP 400)
     */
    public function walletBalance(): array
    {
        $json = $this->doJson('GET', '/v1/wallet/balance');
        return [
            'balance' => $json['balance'] ?? '',
            'gas_balance' => $json['gas_balance'] ?? '',
        ];
    }

    /**
     * Async: Get the wallet's token and gas balances.
     *
     * @return PromiseInterface<array{balance: string, gas_balance: string}>
     */
    public function walletBalanceAsync(): PromiseInterface
    {
        return $this->doJsonAsync('GET', '/v1/wallet/balance')->then(
            fn(?array $json) => [
                'balance' => $json['balance'] ?? '',
                'gas_balance' => $json['gas_balance'] ?? '',
            ],
        );
    }

    /**
     * Approve the wallet to spend tokens on payment contracts (one-time operation).
     *
     * @return bool
     * @throws AntdError if no wallet is configured (HTTP 400)
     */
    public function walletApprove(): bool
    {
        $json = $this->doJson('POST', '/v1/wallet/approve', []);
        return $json['approved'] ?? false;
    }

    /**
     * Async: Approve the wallet to spend tokens on payment contracts.
     *
     * @return PromiseInterface<bool>
     */
    public function walletApproveAsync(): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/wallet/approve', [])->then(
            fn(?array $json) => $json['approved'] ?? false,
        );
    }

    /**
     * Pre-upload cost breakdown for the file at `$path`.
     */
    public function fileCost(string $path, bool $isPublic, PaymentMode $paymentMode = PaymentMode::Auto): UploadCostEstimate
    {
        $json = $this->doJson('POST', '/v1/files/cost', [
            'path' => $path,
            'is_public' => $isPublic,
            'payment_mode' => $paymentMode->value,
        ]);
        return new UploadCostEstimate(
            cost: $json['cost'] ?? '',
            fileSize: (int) ($json['file_size'] ?? 0),
            chunkCount: (int) ($json['chunk_count'] ?? 0),
            estimatedGasCostWei: $json['estimated_gas_cost_wei'] ?? '',
            paymentMode: $json['payment_mode'] ?? '',
        );
    }

    /**
     * Async: Pre-upload cost breakdown for the file at `$path`.
     *
     * @return PromiseInterface<UploadCostEstimate>
     */
    public function fileCostAsync(string $path, bool $isPublic, PaymentMode $paymentMode = PaymentMode::Auto): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/files/cost', [
            'path' => $path,
            'is_public' => $isPublic,
            'payment_mode' => $paymentMode->value,
        ])->then(
            fn(?array $json) => new UploadCostEstimate(
                cost: $json['cost'] ?? '',
                fileSize: (int) ($json['file_size'] ?? 0),
                chunkCount: (int) ($json['chunk_count'] ?? 0),
                estimatedGasCostWei: $json['estimated_gas_cost_wei'] ?? '',
                paymentMode: $json['payment_mode'] ?? '',
            ),
        );
    }

    // --- External Signer (Two-Phase Upload) ---

    /**
     * @param array<string, mixed>|null $json
     */
    private static function parsePrepareUploadResult(?array $json): PrepareUploadResult
    {
        $json ??= [];
        $payments = [];
        foreach (($json['payments'] ?? []) as $p) {
            if (!is_array($p)) {
                continue;
            }
            $payments[] = new PaymentInfo(
                quoteHash: (string)($p['quote_hash'] ?? ''),
                rewardsAddress: (string)($p['rewards_address'] ?? ''),
                amount: (string)($p['amount'] ?? ''),
            );
        }
        return new PrepareUploadResult(
            uploadId: (string)($json['upload_id'] ?? ''),
            paymentType: (string)($json['payment_type'] ?? 'wave_batch'),
            payments: $payments,
            totalAmount: (string)($json['total_amount'] ?? ''),
            paymentVaultAddress: (string)($json['payment_vault_address'] ?? ''),
            paymentTokenAddress: (string)($json['payment_token_address'] ?? ''),
            rpcUrl: (string)($json['rpc_url'] ?? ''),
            totalChunks: (int)($json['total_chunks'] ?? 0),
            alreadyStoredCount: (int)($json['already_stored_count'] ?? 0),
        );
    }

    /**
     * @param array<string, mixed>|null $json
     */
    private static function parsePrepareChunkResult(?array $json): PrepareChunkResult
    {
        $json ??= [];
        $payments = [];
        foreach (($json['payments'] ?? []) as $p) {
            if (!is_array($p)) {
                continue;
            }
            $payments[] = new PaymentInfo(
                quoteHash: (string)($p['quote_hash'] ?? ''),
                rewardsAddress: (string)($p['rewards_address'] ?? ''),
                amount: (string)($p['amount'] ?? ''),
            );
        }
        return new PrepareChunkResult(
            address: (string)($json['address'] ?? ''),
            alreadyStored: (bool)($json['already_stored'] ?? false),
            uploadId: (string)($json['upload_id'] ?? ''),
            paymentType: (string)($json['payment_type'] ?? ''),
            payments: $payments,
            totalAmount: (string)($json['total_amount'] ?? ''),
            paymentVaultAddress: (string)($json['payment_vault_address'] ?? ''),
            paymentTokenAddress: (string)($json['payment_token_address'] ?? ''),
            rpcUrl: (string)($json['rpc_url'] ?? ''),
        );
    }

    /**
     * @param array<string, mixed>|null $json
     */
    private static function parseFinalizeUploadResult(?array $json): FinalizeUploadResult
    {
        $json ??= [];
        return new FinalizeUploadResult(
            dataMap: (string)($json['data_map'] ?? ''),
            address: (string)($json['address'] ?? ''),
            dataMapAddress: (string)($json['data_map_address'] ?? ''),
            chunksStored: (int)($json['chunks_stored'] ?? 0),
            sha256: self::optString($json, 'sha256'),
        );
    }

    /**
     * Prepare a file upload for external signing.
     *
     * @param string $path Filesystem path to the file the daemon should encrypt.
     * @param string|null $visibility Pass "public" to bundle the DataMap chunk
     *     into the same external-signer payment batch; "private" or omit for
     *     the existing private-only behaviour.
     */
    public function prepareUpload(string $path, ?string $visibility = null): PrepareUploadResult
    {
        $body = ['path' => $path];
        if ($visibility !== null) {
            $body['visibility'] = $visibility;
        }
        $json = $this->doJson('POST', '/v1/upload/prepare', $body);
        return self::parsePrepareUploadResult($json);
    }

    /**
     * Async: Prepare a file upload for external signing.
     *
     * @return PromiseInterface<PrepareUploadResult>
     */
    public function prepareUploadAsync(string $path, ?string $visibility = null): PromiseInterface
    {
        $body = ['path' => $path];
        if ($visibility !== null) {
            $body['visibility'] = $visibility;
        }
        return $this->doJsonAsync('POST', '/v1/upload/prepare', $body)->then(
            fn(?array $json) => self::parsePrepareUploadResult($json),
        );
    }

    /**
     * Convenience wrapper: prepare a *public* file upload for external signing.
     * Equivalent to prepareUpload($path, 'public'). Requires antd >= 0.6.1.
     */
    public function prepareUploadPublic(string $path): PrepareUploadResult
    {
        return $this->prepareUpload($path, 'public');
    }

    /**
     * Async: Convenience wrapper: prepare a *public* file upload for external signing.
     *
     * @return PromiseInterface<PrepareUploadResult>
     */
    public function prepareUploadPublicAsync(string $path): PromiseInterface
    {
        return $this->prepareUploadAsync($path, 'public');
    }

    /**
     * Prepare a data upload for external signing.
     * Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
     */
    public function prepareDataUpload(string $data, ?string $visibility = null): PrepareUploadResult
    {
        $body = ['data' => $this->b64Encode($data)];
        if ($visibility !== null) {
            $body['visibility'] = $visibility;
        }
        $json = $this->doJson('POST', '/v1/data/prepare', $body);
        return self::parsePrepareUploadResult($json);
    }

    /**
     * Async: Prepare a data upload for external signing.
     *
     * @return PromiseInterface<PrepareUploadResult>
     */
    public function prepareDataUploadAsync(string $data, ?string $visibility = null): PromiseInterface
    {
        $body = ['data' => $this->b64Encode($data)];
        if ($visibility !== null) {
            $body['visibility'] = $visibility;
        }
        return $this->doJsonAsync('POST', '/v1/data/prepare', $body)->then(
            fn(?array $json) => self::parsePrepareUploadResult($json),
        );
    }

    /**
     * Finalize an upload after an external signer has submitted payment transactions.
     *
     * When some chunks stay unstored after the daemon's own retries this
     * throws {@see PartialUploadError} (HTTP 502, `code: "PARTIAL_UPLOAD"`)
     * with `chunksStored` / `chunksFailed` / `totalChunks` and the
     * `retryable` / `retentionKnown` flags. The payment persists and the
     * stored chunks stay on the network:
     *
     *  - `retryable` (antd >= 0.14.0): the daemon kept the paid attempt under
     *    the same `upload_id`. Call this method again with the same arguments
     *    to store the remainder against the same payment; no re-prepare, no
     *    second signature, no double payment. Bound that loop (cap the
     *    attempts; a `chunksFailed` that stops shrinking is stuck).
     *  - `retentionKnown && !retryable`: the daemon confirmed nothing was
     *    retained. Re-prepare the same content; already-stored chunks are
     *    skipped.
     *  - `!retentionKnown` (e.g. antd < 0.14.0, which never sends the flag):
     *    retention is unknown and the daemon may still hold the paid attempt.
     *    Stop automatic recovery, keep `$uploadId` and `$txHashes`, and
     *    reconcile before re-preparing or paying again; never pay again on
     *    this signal alone.
     *
     * See docs/external-signer-flow.md, "6. Retry a partial store", and
     * `finalizeWithRetry()` in examples/07-external-signer.php.
     *
     * @param string $uploadId The upload ID from prepareUpload.
     * @param array<string, string> $txHashes Map of quote_hash to tx_hash.
     * @throws PartialUploadError when only part of the upload was stored.
     */
    public function finalizeUpload(string $uploadId, array $txHashes): FinalizeUploadResult
    {
        $json = $this->doJson('POST', '/v1/upload/finalize', [
            'upload_id' => $uploadId,
            'tx_hashes' => (object) $txHashes,
        ]);
        return self::parseFinalizeUploadResult($json);
    }

    /**
     * Async: Finalize an upload after an external signer has submitted payment transactions.
     *
     * Rejects with {@see PartialUploadError} on a partial store; see
     * {@see finalizeUpload()} for the retry contract.
     *
     * @param string $uploadId The upload ID from prepareUpload.
     * @param array<string, string> $txHashes Map of quote_hash to tx_hash.
     * @return PromiseInterface<FinalizeUploadResult>
     */
    public function finalizeUploadAsync(string $uploadId, array $txHashes): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/upload/finalize', [
            'upload_id' => $uploadId,
            'tx_hashes' => (object) $txHashes,
        ])->then(
            fn(?array $json) => self::parseFinalizeUploadResult($json),
        );
    }

    // --- Single-Chunk External Signer (antd >= 0.7.0) ---

    /**
     * Prepare a single chunk for external-signer publish via POST /v1/chunks/prepare.
     */
    public function prepareChunkUpload(string $data): PrepareChunkResult
    {
        $json = $this->doJson('POST', '/v1/chunks/prepare', [
            'data' => $this->b64Encode($data),
        ]);
        return self::parsePrepareChunkResult($json);
    }

    /**
     * Async: Prepare a single chunk for external-signer publish.
     *
     * @return PromiseInterface<PrepareChunkResult>
     */
    public function prepareChunkUploadAsync(string $data): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/chunks/prepare', [
            'data' => $this->b64Encode($data),
        ])->then(
            fn(?array $json) => self::parsePrepareChunkResult($json),
        );
    }

    /**
     * Submit a prepared chunk to the network after external payment via
     * POST /v1/chunks/finalize.
     *
     * A store that misses quorum after the daemon's retries throws
     * {@see PartialUploadError}; when `retryable` is `true` (antd >= 0.14.0)
     * the paid attempt was retained and calling this method again with the
     * same arguments retries against the same payment. `retryable === false`
     * with `retentionKnown === false` means retention is unknown, not that
     * nothing was retained. See {@see finalizeUpload()} for the full contract.
     *
     * @param string $uploadId The upload ID from prepareChunkUpload().
     * @param array<string, string> $txHashes Map of quote_hash to tx_hash.
     * @throws PartialUploadError when the chunk was paid for but not stored.
     */
    public function finalizeChunkUpload(string $uploadId, array $txHashes): string
    {
        $json = $this->doJson('POST', '/v1/chunks/finalize', [
            'upload_id' => $uploadId,
            'tx_hashes' => (object) $txHashes,
        ]);
        return (string)($json['address'] ?? '');
    }

    /**
     * Async: Submit a prepared chunk to the network after external payment.
     *
     * Rejects with {@see PartialUploadError} on a partial store; see
     * {@see finalizeUpload()} for the retry contract.
     *
     * @param string $uploadId The upload ID from prepareChunkUpload().
     * @param array<string, string> $txHashes Map of quote_hash to tx_hash.
     * @return PromiseInterface<string>
     */
    public function finalizeChunkUploadAsync(string $uploadId, array $txHashes): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/chunks/finalize', [
            'upload_id' => $uploadId,
            'tx_hashes' => (object) $txHashes,
        ])->then(
            fn(?array $json) => (string)($json['address'] ?? ''),
        );
    }

    // --- Pointers ---
    //
    // A pointer is a small, owner-signed, mutable reference. Its address is
    // derived from the owner's key and never changes; what it points at (a
    // chunk, such as public data's data map, or another pointer) can be
    // changed by the owner, and the owner can hand it over to another pointer
    // for good. The daemon signs with owner keys it loaded at startup
    // (`antd --pointer-keys`), so a write names the pointer by its address
    // (`$owner`) and no key crosses the API. pointerKeys() lists the pointers
    // the daemon can write.
    //
    // Every write pays (about the price of one chunk) and every attempt pays
    // again, so this client never retries pointerCreate(), pointerUpdate(),
    // pointerTransfer() or pointerFinalize(), and callers should not retry
    // them automatically either. Reads are free to retry; a
    // CloseGroupShortfallError on a read usually clears once an update in
    // flight settles.
    //
    // Counters are canonical decimal strings, not ints: a final state sits at
    // 2^64 - 1, past PHP's signed int (see PointerCounter).

    /**
     * The addresses of the pointers this daemon holds owner keys for
     * (`GET /v1/pointers/keys`). Only these can be written through it.
     *
     * @return list<string>
     */
    public function pointerKeys(): array
    {
        return self::parsePointerKeys($this->doJson('GET', '/v1/pointers/keys'));
    }

    /**
     * Async: the addresses of the pointers this daemon holds owner keys for.
     *
     * @return PromiseInterface<list<string>>
     */
    public function pointerKeysAsync(): PromiseInterface
    {
        return $this->doJsonAsync('GET', '/v1/pointers/keys')->then(
            fn(?array $json) => self::parsePointerKeys($json),
        );
    }

    /**
     * Create the pointer at `$owner`, pointing at `$target`, paid by the
     * daemon wallet (`POST /v1/pointers`). `$owner` is the pointer's address;
     * the daemon must hold its key ({@see pointerKeys()}), or the call is a
     * {@see \Autonomi\Antd\Errors\BadRequestError}. A null `$kind` leaves the
     * daemon's default, {@see PointerTargetKind::Chunk}.
     *
     * Pays for the write. Not retried automatically: every attempt pays again.
     *
     * @throws \Autonomi\Antd\Errors\AlreadyExistsError if the pointer exists, before paying; use pointerUpdate().
     * @throws \Autonomi\Antd\Errors\ConflictError while a prepared write to the pointer awaits payment.
     */
    public function pointerCreate(string $owner, string $target, ?PointerTargetKind $kind = null): PointerWriteResult
    {
        return self::parsePointerWrite(
            $this->doJson('POST', '/v1/pointers', self::pointerWriteBody($owner, $target, $kind)),
        );
    }

    /**
     * Async: create a pointer, paid by the daemon wallet. Pays; not retried.
     *
     * @return PromiseInterface<PointerWriteResult>
     */
    public function pointerCreateAsync(string $owner, string $target, ?PointerTargetKind $kind = null): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/pointers', self::pointerWriteBody($owner, $target, $kind))->then(
            fn(?array $json) => self::parsePointerWrite($json),
        );
    }

    /**
     * Point the pointer at `$owner` at `$target`, paid by the daemon wallet
     * (`POST /v1/pointers/update`). A pointer that does not exist yet is
     * created at counter "0". A null `$kind` leaves the daemon's default,
     * {@see PointerTargetKind::Chunk}.
     *
     * Pays for the write. Not retried automatically: every attempt pays again.
     *
     * @throws \Autonomi\Antd\Errors\PointerFinalError if the pointer was handed over or frozen, usually before paying.
     * @throws \Autonomi\Antd\Errors\ConflictError while a prepared write to the pointer awaits payment (refused before
     *         paying), or if the update lost to a newer state while in flight (possibly after paying). Read the pointer
     *         before writing again.
     */
    public function pointerUpdate(string $owner, string $target, ?PointerTargetKind $kind = null): PointerWriteResult
    {
        return self::parsePointerWrite(
            $this->doJson('POST', '/v1/pointers/update', self::pointerWriteBody($owner, $target, $kind)),
        );
    }

    /**
     * Async: point a pointer at a new target, paid by the daemon wallet.
     * Pays; not retried.
     *
     * @return PromiseInterface<PointerWriteResult>
     */
    public function pointerUpdateAsync(string $owner, string $target, ?PointerTargetKind $kind = null): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/pointers/update', self::pointerWriteBody($owner, $target, $kind))->then(
            fn(?array $json) => self::parsePointerWrite($json),
        );
    }

    /**
     * Hand the pointer at `$owner` over to the pointer at `$recipient`, for
     * good, paid by the daemon wallet (`POST /v1/pointers/transfer`). Readers
     * of `$owner`'s address are redirected to the recipient's pointer, which
     * only its owner can move. Irreversible once stored.
     *
     * Refused before paying if `$recipient` does not exist or leads back
     * ({@see \Autonomi\Antd\Errors\BadRequestError}), and usually if the
     * pointer is already final ({@see \Autonomi\Antd\Errors\PointerFinalError}).
     * A {@see \Autonomi\Antd\Errors\CloseGroupShortfallError} means too few of
     * the close group answered or stored it. That can happen before paying (the
     * transfer checks every peer first) or after, so check the pointer with
     * {@see pointerFinality()} before paying again.
     *
     * Pays for the write. Not retried automatically: every attempt pays again.
     */
    public function pointerTransfer(string $owner, string $recipient): PointerTransferResult
    {
        return self::parsePointerTransfer($this->doJson('POST', '/v1/pointers/transfer', [
            'owner' => $owner,
            'recipient' => $recipient,
        ]));
    }

    /**
     * Async: hand a pointer over for good, paid by the daemon wallet.
     * Pays; not retried.
     *
     * @return PromiseInterface<PointerTransferResult>
     */
    public function pointerTransferAsync(string $owner, string $recipient): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/pointers/transfer', [
            'owner' => $owner,
            'recipient' => $recipient,
        ])->then(
            fn(?array $json) => self::parsePointerTransfer($json),
        );
    }

    /**
     * Read the pointer at `$address` (`GET /v1/pointers/{address}`).
     *
     * @throws \Autonomi\Antd\Errors\NotFoundError if there is no pointer there.
     * @throws \UnexpectedValueException if the daemon's counter is not a decimal u64.
     */
    public function pointerGet(string $address): PointerRecord
    {
        return self::parsePointerRecord($this->doJson('GET', self::pointerPath($address)));
    }

    /**
     * Async: read the pointer at `$address`.
     *
     * @return PromiseInterface<PointerRecord>
     */
    public function pointerGetAsync(string $address): PromiseInterface
    {
        return $this->doJsonAsync('GET', self::pointerPath($address))->then(
            fn(?array $json) => self::parsePointerRecord($json),
        );
    }

    /**
     * Follow a chain of pointers from `$address` to the target at its end
     * (`GET /v1/pointers/{address}/resolve`), through forwardings and
     * transfers alike.
     *
     * @throws \Autonomi\Antd\Errors\NotFoundError if a pointer on the chain does not exist.
     */
    public function pointerResolve(string $address): PointerTarget
    {
        return self::parsePointerTarget($this->doJson('GET', self::pointerPath($address, 'resolve')));
    }

    /**
     * Async: follow a chain of pointers to the target at its end.
     *
     * @return PromiseInterface<PointerTarget>
     */
    public function pointerResolveAsync(string $address): PromiseInterface
    {
        return $this->doJsonAsync('GET', self::pointerPath($address, 'resolve'))->then(
            fn(?array $json) => self::parsePointerTarget($json),
        );
    }

    /**
     * Ask the whole close group where the pointer at `$address` stands
     * (`GET /v1/pointers/{address}/finality`). Check this before relying on a
     * transfer: only {@see PointerFinalityStatus::Final}
     * ({@see PointerFinality::isFinal()}) means it is beyond dispute.
     */
    public function pointerFinality(string $address): PointerFinality
    {
        return self::parsePointerFinality($this->doJson('GET', self::pointerPath($address, 'finality')) ?? []);
    }

    /**
     * Async: ask the whole close group where a pointer stands.
     *
     * @return PromiseInterface<PointerFinality>
     */
    public function pointerFinalityAsync(string $address): PromiseInterface
    {
        return $this->doJsonAsync('GET', self::pointerPath($address, 'finality'))->then(
            fn(?array $json) => self::parsePointerFinality($json ?? []),
        );
    }

    /**
     * Follow the transfers of the pointer at `$address` to the pointer whose
     * owner now decides what it resolves to
     * (`GET /v1/pointers/{address}/controller`).
     */
    public function pointerController(string $address): PointerController
    {
        return self::parsePointerController($this->doJson('GET', self::pointerPath($address, 'controller')));
    }

    /**
     * Async: follow transfers to the pointer whose owner now decides.
     *
     * @return PromiseInterface<PointerController>
     */
    public function pointerControllerAsync(string $address): PromiseInterface
    {
        return $this->doJsonAsync('GET', self::pointerPath($address, 'controller'))->then(
            fn(?array $json) => self::parsePointerController($json),
        );
    }

    /**
     * Have the daemon sign a pointer write with its loaded owner key and
     * quote it for an external signer (`POST /v1/pointers/prepare`). Pay
     * {@see PointerPrepareResult::$payments} with `payForQuotes()`, then call
     * {@see pointerFinalize()}. Needs no daemon wallet, and pays nothing
     * itself.
     *
     * Every check the daemon-wallet methods make before paying is made here,
     * before anything is quoted. While the prepared write awaits payment,
     * other writes to the pointer throw
     * {@see \Autonomi\Antd\Errors\ConflictError} until it is finalized or
     * expires (one hour).
     *
     * Set {@see PointerPrepareRequest::$includeSignedQuotes} to also get the
     * full signed quotes in {@see PointerPrepareResult::$signedQuotes}.
     */
    public function pointerPrepare(PointerPrepareRequest $request): PointerPrepareResult
    {
        return self::parsePointerPrepare($this->doJson('POST', '/v1/pointers/prepare', $request->toArray()));
    }

    /**
     * Async: sign and quote a pointer write for an external signer.
     *
     * @return PromiseInterface<PointerPrepareResult>
     */
    public function pointerPrepareAsync(PointerPrepareRequest $request): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/pointers/prepare', $request->toArray())->then(
            fn(?array $json) => self::parsePointerPrepare($json),
        );
    }

    /**
     * Store a prepared pointer write once its external signer has paid
     * (`POST /v1/pointers/finalize`).
     *
     * A write that falls short after payment throws
     * {@see \Autonomi\Antd\Errors\CloseGroupShortfallError} with `retryable`
     * set: the daemon kept the paid state under the same `$uploadId`, so
     * calling this method again with the same `$uploadId` stores it against
     * the same payment (`$txHashes` is then ignored). Bound that loop; the
     * session expires with the daemon's one-hour pending TTL. This client
     * never repeats the call itself. A finalize without the payment's hashes
     * is a {@see \Autonomi\Antd\Errors\BadRequestError} and keeps the
     * session, so it can be corrected.
     *
     * @param string $uploadId The upload ID from pointerPrepare().
     * @param array<string, string> $txHashes Map of quote_hash to the payForQuotes() tx_hash.
     */
    public function pointerFinalize(string $uploadId, array $txHashes): PointerFinalizeResult
    {
        return self::parsePointerFinalize($this->doJson('POST', '/v1/pointers/finalize', [
            'upload_id' => $uploadId,
            'tx_hashes' => (object) $txHashes,
        ]));
    }

    /**
     * Async: store a prepared pointer write once paid. Not retried; see
     * {@see pointerFinalize()} for the same-payment retry contract.
     *
     * @param string $uploadId The upload ID from pointerPrepare().
     * @param array<string, string> $txHashes Map of quote_hash to the payForQuotes() tx_hash.
     * @return PromiseInterface<PointerFinalizeResult>
     */
    public function pointerFinalizeAsync(string $uploadId, array $txHashes): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/pointers/finalize', [
            'upload_id' => $uploadId,
            'tx_hashes' => (object) $txHashes,
        ])->then(
            fn(?array $json) => self::parsePointerFinalize($json),
        );
    }

    // --- Pointer parsing helpers ---
    //
    // Fields are read strictly: a value of the wrong JSON type reads as the
    // field's empty value ('' / 0 / false / null), except a counter, which
    // must be a decimal u64 string or the call throws.

    private static function pointerPath(string $address, string $suffix = ''): string
    {
        return '/v1/pointers/' . rawurlencode($address) . ($suffix === '' ? '' : '/' . $suffix);
    }

    /** @return array<string, string> */
    private static function pointerWriteBody(string $owner, string $target, ?PointerTargetKind $kind): array
    {
        $body = ['owner' => $owner, 'target' => $target];
        if ($kind !== null) {
            $body['kind'] = $kind->value;
        }
        return $body;
    }

    /** @param array<mixed> $json */
    private static function ptrStr(array $json, string $key): string
    {
        $value = $json[$key] ?? null;
        return is_string($value) ? $value : '';
    }

    /**
     * An optional string: null when absent, null (REST's unset) or empty.
     *
     * @param array<mixed> $json
     */
    private static function ptrOptStr(array $json, string $key): ?string
    {
        $value = $json[$key] ?? null;
        return is_string($value) && $value !== '' ? $value : null;
    }

    /** @param array<mixed> $json */
    private static function ptrUint(array $json, string $key): int
    {
        $value = $json[$key] ?? null;
        return is_int($value) && $value >= 0 ? $value : 0;
    }

    /**
     * The raw target kind tag, or 255 (no kind) when it is missing or not a
     * u8, so a garbled tag never reads as a chunk.
     *
     * @param array<mixed> $json
     */
    private static function ptrKindTag(array $json): int
    {
        $value = $json['kind_tag'] ?? null;
        return is_int($value) && $value >= 0 && $value <= 255 ? $value : 255;
    }

    /** @param array<mixed> $json */
    private static function ptrCounter(array $json, string $key): string
    {
        return PointerCounter::parse($json[$key] ?? null, $key);
    }

    /**
     * @param array<mixed>|null $json
     * @return list<string>
     */
    private static function parsePointerKeys(?array $json): array
    {
        $keys = [];
        $entries = $json['keys'] ?? null;
        foreach (is_array($entries) ? $entries : [] as $entry) {
            if (is_array($entry) && is_string($entry['address'] ?? null)) {
                $keys[] = $entry['address'];
            }
        }
        return $keys;
    }

    /** @param array<mixed>|null $json */
    private static function parsePointerWrite(?array $json): PointerWriteResult
    {
        $json ??= [];
        return new PointerWriteResult(
            address: self::ptrStr($json, 'address'),
            stateId: self::ptrStr($json, 'state_id'),
            counter: self::ptrCounter($json, 'counter'),
        );
    }

    /** @param array<mixed>|null $json */
    private static function parsePointerRecord(?array $json): PointerRecord
    {
        $json ??= [];
        return new PointerRecord(
            address: self::ptrStr($json, 'address'),
            owner: self::ptrStr($json, 'owner'),
            counter: self::ptrCounter($json, 'counter'),
            kind: self::ptrStr($json, 'kind'),
            kindTag: self::ptrKindTag($json),
            target: self::ptrStr($json, 'target'),
            stateId: self::ptrStr($json, 'state_id'),
            isFinal: ($json['is_final'] ?? null) === true,
            transferredTo: self::ptrOptStr($json, 'transferred_to'),
        );
    }

    /** @param array<mixed>|null $json */
    private static function parsePointerTarget(?array $json): PointerTarget
    {
        $json ??= [];
        return new PointerTarget(
            kind: self::ptrStr($json, 'kind'),
            kindTag: self::ptrKindTag($json),
            target: self::ptrStr($json, 'target'),
        );
    }

    /** @param array<mixed> $json */
    private static function parsePointerFinalState(array $json): PointerFinalState
    {
        return new PointerFinalState(
            stateId: self::ptrStr($json, 'state_id'),
            kind: self::ptrStr($json, 'kind'),
            kindTag: self::ptrKindTag($json),
            target: self::ptrStr($json, 'target'),
            holders: self::ptrUint($json, 'holders'),
            transferredTo: self::ptrOptStr($json, 'transferred_to'),
        );
    }

    /**
     * Parse a finality answer. Its `counter` is optional (null, absent or
     * "" when no state is corroborated), but a present one must be a decimal
     * u64 string, like every other counter.
     *
     * @param array<mixed> $json
     */
    private static function parsePointerFinality(array $json): PointerFinality
    {
        $counter = $json['counter'] ?? null;
        $states = [];
        $rawStates = $json['states'] ?? null;
        foreach (is_array($rawStates) ? $rawStates : [] as $state) {
            if (is_array($state)) {
                $states[] = self::parsePointerFinalState($state);
            }
        }
        $state = $json['state'] ?? null;
        $majority = $json['majority'] ?? null;
        $rawStatus = self::ptrStr($json, 'status');
        return new PointerFinality(
            address: self::ptrStr($json, 'address'),
            group: self::ptrUint($json, 'group'),
            answered: self::ptrUint($json, 'answered'),
            status: PointerFinalityStatus::fromWire($rawStatus),
            rawStatus: $rawStatus,
            counter: $counter === null || $counter === '' ? null : PointerCounter::parse($counter, 'counter'),
            state: is_array($state) ? self::parsePointerFinalState($state) : null,
            states: $states,
            majority: is_array($majority) ? self::parsePointerFinalState($majority) : null,
            transferredTo: self::ptrOptStr($json, 'transferred_to'),
        );
    }

    /** @param array<mixed>|null $json */
    private static function parsePointerController(?array $json): PointerController
    {
        $json ??= [];
        $transfers = [];
        $raw = $json['transfers'] ?? null;
        foreach (is_array($raw) ? $raw : [] as $address) {
            if (is_string($address)) {
                $transfers[] = $address;
            }
        }
        return new PointerController(
            pointer: self::ptrStr($json, 'pointer'),
            transfers: $transfers,
            frozen: ($json['frozen'] ?? null) === true,
        );
    }

    /** @param array<mixed>|null $json */
    private static function parsePointerTransfer(?array $json): PointerTransferResult
    {
        $json ??= [];
        $finality = $json['finality'] ?? null;
        return new PointerTransferResult(
            address: self::ptrStr($json, 'address'),
            stateId: self::ptrStr($json, 'state_id'),
            finality: is_array($finality) ? self::parsePointerFinality($finality) : null,
            finalityError: self::ptrOptStr($json, 'finality_error'),
        );
    }

    /** @param array<mixed>|null $json */
    private static function parsePointerPrepare(?array $json): PointerPrepareResult
    {
        $json ??= [];
        $payments = [];
        $raw = $json['payments'] ?? null;
        foreach (is_array($raw) ? $raw : [] as $p) {
            if (is_array($p)) {
                $payments[] = new PaymentInfo(
                    quoteHash: self::ptrStr($p, 'quote_hash'),
                    rewardsAddress: self::ptrStr($p, 'rewards_address'),
                    amount: self::ptrStr($p, 'amount'),
                );
            }
        }
        $signedQuotes = [];
        $rawQuotes = $json['signed_quotes'] ?? null;
        foreach (is_array($rawQuotes) ? $rawQuotes : [] as $q) {
            if (is_array($q)) {
                $sidecar = self::ptrOptStr($q, 'commitment_sidecar');
                $signedQuotes[] = new SignedQuoteEntry(
                    quoteHash: self::ptrStr($q, 'quote_hash'),
                    quote: self::ptrStr($q, 'quote'),
                    commitmentSidecar: $sidecar === '' ? null : $sidecar,
                );
            }
        }
        return new PointerPrepareResult(
            uploadId: self::ptrStr($json, 'upload_id'),
            op: self::ptrStr($json, 'op'),
            address: self::ptrStr($json, 'address'),
            stateId: self::ptrStr($json, 'state_id'),
            counter: self::ptrCounter($json, 'counter'),
            paymentType: self::ptrStr($json, 'payment_type'),
            payments: $payments,
            totalAmount: self::ptrStr($json, 'total_amount'),
            paymentVaultAddress: self::ptrStr($json, 'payment_vault_address'),
            paymentTokenAddress: self::ptrStr($json, 'payment_token_address'),
            rpcUrl: self::ptrStr($json, 'rpc_url'),
            signedQuotes: $signedQuotes,
        );
    }

    /** @param array<mixed>|null $json */
    private static function parsePointerFinalize(?array $json): PointerFinalizeResult
    {
        $json ??= [];
        $finality = $json['finality'] ?? null;
        return new PointerFinalizeResult(
            address: self::ptrStr($json, 'address'),
            stateId: self::ptrStr($json, 'state_id'),
            counter: self::ptrCounter($json, 'counter'),
            finality: is_array($finality) ? self::parsePointerFinality($finality) : null,
        );
    }
}
