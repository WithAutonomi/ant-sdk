<?php

declare(strict_types=1);

namespace Autonomi\Antd;

use GuzzleHttp\Client;
use GuzzleHttp\Exception\GuzzleException;
use GuzzleHttp\Promise\PromiseInterface;
use Autonomi\Antd\Errors\AntdError;
use Autonomi\Antd\Errors\ErrorFactory;
use Autonomi\Antd\Models\DataPutPublicResult;
use Autonomi\Antd\Models\DataPutResult;
use Autonomi\Antd\Models\FilePutPublicResult;
use Autonomi\Antd\Models\FilePutResult;
use Autonomi\Antd\Models\FinalizeUploadResult;
use Autonomi\Antd\Models\HealthStatus;
use Autonomi\Antd\Models\PaymentInfo;
use Autonomi\Antd\Models\PaymentMode;
use Autonomi\Antd\Models\PrepareChunkResult;
use Autonomi\Antd\Models\PrepareUploadResult;
use Autonomi\Antd\Models\PutResult;
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
            $response = $e->getResponse();
            $statusCode = $response->getStatusCode();
            $responseBody = (string) $response->getBody();
            $message = $responseBody;
            $parsed = json_decode($responseBody, true);
            if (is_array($parsed) && isset($parsed['error'])) {
                $message = $parsed['error'];
            }
            throw ErrorFactory::fromHttpStatus($statusCode, $message);
        }

        $responseBody = (string) $response->getBody();
        if ($responseBody === '') {
            return null;
        }

        return json_decode($responseBody, true);
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
                    $response = $e->getResponse();
                    $statusCode = $response->getStatusCode();
                    $responseBody = (string) $response->getBody();
                    $message = $responseBody;
                    $parsed = json_decode($responseBody, true);
                    if (is_array($parsed) && isset($parsed['error'])) {
                        $message = $parsed['error'];
                    }
                    throw ErrorFactory::fromHttpStatus($statusCode, $message);
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
     * @param string $uploadId The upload ID from prepareUpload.
     * @param array<string, string> $txHashes Map of quote_hash to tx_hash.
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
     * @param string $uploadId The upload ID from prepareChunkUpload().
     * @param array<string, string> $txHashes Map of quote_hash to tx_hash.
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
}
