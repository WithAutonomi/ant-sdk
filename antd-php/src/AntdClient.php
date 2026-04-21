<?php

declare(strict_types=1);

namespace Autonomi\Antd;

use GuzzleHttp\Client;
use GuzzleHttp\Exception\GuzzleException;
use GuzzleHttp\Promise\PromiseInterface;
use Autonomi\Antd\Errors\AntdError;
use Autonomi\Antd\Errors\ErrorFactory;
use Autonomi\Antd\Models\FileUploadResult;
use Autonomi\Antd\Models\HealthStatus;
use Autonomi\Antd\Models\PutResult;
use Autonomi\Antd\Models\UploadCostEstimate;

/**
 * REST client for the antd daemon.
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
        $json = $this->doJson('GET', '/health');
        return new HealthStatus(
            ok: ($json['status'] ?? '') === 'ok',
            network: $json['network'] ?? '',
        );
    }

    /**
     * Async: Check the antd daemon status.
     *
     * @return PromiseInterface<HealthStatus>
     */
    public function healthAsync(): PromiseInterface
    {
        return $this->doJsonAsync('GET', '/health')->then(
            fn(?array $json) => new HealthStatus(
                ok: ($json['status'] ?? '') === 'ok',
                network: $json['network'] ?? '',
            ),
        );
    }

    // --- Data ---

    /**
     * Store public immutable data on the network.
     */
    public function dataPutPublic(string $data, ?string $paymentMode = null): PutResult
    {
        $body = ['data' => $this->b64Encode($data)];
        if ($paymentMode !== null) {
            $body['payment_mode'] = $paymentMode;
        }
        $json = $this->doJson('POST', '/v1/data/public', $body);
        return new PutResult(
            cost: $json['cost'] ?? '',
            address: $json['address'] ?? '',
        );
    }

    /**
     * Async: Store public immutable data on the network.
     *
     * @return PromiseInterface<PutResult>
     */
    public function dataPutPublicAsync(string $data, ?string $paymentMode = null): PromiseInterface
    {
        $body = ['data' => $this->b64Encode($data)];
        if ($paymentMode !== null) {
            $body['payment_mode'] = $paymentMode;
        }
        return $this->doJsonAsync('POST', '/v1/data/public', $body)->then(
            fn(?array $json) => new PutResult(
                cost: $json['cost'] ?? '',
                address: $json['address'] ?? '',
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
     * Store private encrypted data on the network.
     */
    public function dataPutPrivate(string $data, ?string $paymentMode = null): PutResult
    {
        $body = ['data' => $this->b64Encode($data)];
        if ($paymentMode !== null) {
            $body['payment_mode'] = $paymentMode;
        }
        $json = $this->doJson('POST', '/v1/data/private', $body);
        return new PutResult(
            cost: $json['cost'] ?? '',
            address: $json['data_map'] ?? '',
        );
    }

    /**
     * Async: Store private encrypted data on the network.
     *
     * @return PromiseInterface<PutResult>
     */
    public function dataPutPrivateAsync(string $data, ?string $paymentMode = null): PromiseInterface
    {
        $body = ['data' => $this->b64Encode($data)];
        if ($paymentMode !== null) {
            $body['payment_mode'] = $paymentMode;
        }
        return $this->doJsonAsync('POST', '/v1/data/private', $body)->then(
            fn(?array $json) => new PutResult(
                cost: $json['cost'] ?? '',
                address: $json['data_map'] ?? '',
            ),
        );
    }

    /**
     * Retrieve private data using a data map.
     */
    public function dataGetPrivate(string $dataMap): string
    {
        $json = $this->doJson('GET', '/v1/data/private?data_map=' . urlencode($dataMap));
        return $this->b64Decode($json['data'] ?? '');
    }

    /**
     * Async: Retrieve private data using a data map.
     *
     * @return PromiseInterface<string>
     */
    public function dataGetPrivateAsync(string $dataMap): PromiseInterface
    {
        return $this->doJsonAsync('GET', '/v1/data/private?data_map=' . urlencode($dataMap))->then(
            fn(?array $json) => $this->b64Decode($json['data'] ?? ''),
        );
    }

    /**
     * Pre-upload cost breakdown for the given bytes.
     */
    public function dataCost(string $data): UploadCostEstimate
    {
        $json = $this->doJson('POST', '/v1/data/cost', [
            'data' => $this->b64Encode($data),
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
    public function dataCostAsync(string $data): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/data/cost', [
            'data' => $this->b64Encode($data),
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
     * Upload a local file to the network.
     */
    public function fileUploadPublic(string $path, ?string $paymentMode = null): FileUploadResult
    {
        $body = ['path' => $path];
        if ($paymentMode !== null) {
            $body['payment_mode'] = $paymentMode;
        }
        $json = $this->doJson('POST', '/v1/files/upload/public', $body);
        return self::parseFileUploadResult($json);
    }

    /**
     * Async: Upload a local file to the network.
     *
     * @return PromiseInterface<FileUploadResult>
     */
    public function fileUploadPublicAsync(string $path, ?string $paymentMode = null): PromiseInterface
    {
        $body = ['path' => $path];
        if ($paymentMode !== null) {
            $body['payment_mode'] = $paymentMode;
        }
        return $this->doJsonAsync('POST', '/v1/files/upload/public', $body)->then(
            fn(?array $json) => self::parseFileUploadResult($json ?? []),
        );
    }

    private static function parseFileUploadResult(array $json): FileUploadResult
    {
        return new FileUploadResult(
            address: (string)($json['address'] ?? ''),
            storageCostAtto: (string)($json['storage_cost_atto'] ?? ''),
            gasCostWei: (string)($json['gas_cost_wei'] ?? ''),
            chunksStored: (int)($json['chunks_stored'] ?? 0),
            paymentModeUsed: (string)($json['payment_mode_used'] ?? ''),
        );
    }

    /**
     * Download a file from the network to a local path.
     */
    public function fileDownloadPublic(string $address, string $destPath): void
    {
        $this->doJson('POST', '/v1/files/download/public', [
            'address' => $address,
            'dest_path' => $destPath,
        ]);
    }

    /**
     * Async: Download a file from the network to a local path.
     *
     * @return PromiseInterface<null>
     */
    public function fileDownloadPublicAsync(string $address, string $destPath): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/files/download/public', [
            'address' => $address,
            'dest_path' => $destPath,
        ])->then(fn() => null);
    }

    /**
     * Upload a local directory to the network.
     */
    public function dirUploadPublic(string $path, ?string $paymentMode = null): FileUploadResult
    {
        $body = ['path' => $path];
        if ($paymentMode !== null) {
            $body['payment_mode'] = $paymentMode;
        }
        $json = $this->doJson('POST', '/v1/dirs/upload/public', $body);
        return self::parseFileUploadResult($json);
    }

    /**
     * Async: Upload a local directory to the network.
     *
     * @return PromiseInterface<FileUploadResult>
     */
    public function dirUploadPublicAsync(string $path, ?string $paymentMode = null): PromiseInterface
    {
        $body = ['path' => $path];
        if ($paymentMode !== null) {
            $body['payment_mode'] = $paymentMode;
        }
        return $this->doJsonAsync('POST', '/v1/dirs/upload/public', $body)->then(
            fn(?array $json) => self::parseFileUploadResult($json ?? []),
        );
    }

    /**
     * Download a directory from the network to a local path.
     */
    public function dirDownloadPublic(string $address, string $destPath): void
    {
        $this->doJson('POST', '/v1/dirs/download/public', [
            'address' => $address,
            'dest_path' => $destPath,
        ]);
    }

    /**
     * Async: Download a directory from the network to a local path.
     *
     * @return PromiseInterface<null>
     */
    public function dirDownloadPublicAsync(string $address, string $destPath): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/dirs/download/public', [
            'address' => $address,
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
     * Async: Approve the wallet to spend tokens on payment contracts (one-time operation).
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
     * Estimate the cost of uploading a file.
     */
    public function fileCost(string $path, bool $isPublic): UploadCostEstimate
    {
        $json = $this->doJson('POST', '/v1/cost/file', [
            'path' => $path,
            'is_public' => $isPublic,
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
     * Async: Estimate the cost of uploading a file.
     *
     * @return PromiseInterface<string>
     */
    public function fileCostAsync(string $path, bool $isPublic): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/cost/file', [
            'path' => $path,
            'is_public' => $isPublic,
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
     * Prepare a file upload for external signing.
     *
     * @return array{upload_id: string, payments: array, total_amount: string, payment_vault_address: string, payment_token_address: string, rpc_url: string}
     */
    public function prepareUpload(string $path): array
    {
        $json = $this->doJson('POST', '/v1/upload/prepare', ['path' => $path]);
        return [
            'upload_id' => $json['upload_id'] ?? '',
            'payments' => $json['payments'] ?? [],
            'total_amount' => $json['total_amount'] ?? '',
            'payment_vault_address' => $json['payment_vault_address'] ?? '',
            'payment_token_address' => $json['payment_token_address'] ?? '',
            'rpc_url' => $json['rpc_url'] ?? '',
        ];
    }

    /**
     * Async: Prepare a file upload for external signing.
     *
     * @return PromiseInterface<array>
     */
    public function prepareUploadAsync(string $path): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/upload/prepare', ['path' => $path])->then(
            fn(?array $json) => [
                'upload_id' => $json['upload_id'] ?? '',
                'payments' => $json['payments'] ?? [],
                'total_amount' => $json['total_amount'] ?? '',
                'payment_vault_address' => $json['payment_vault_address'] ?? '',
                'payment_token_address' => $json['payment_token_address'] ?? '',
                'rpc_url' => $json['rpc_url'] ?? '',
            ],
        );
    }

    /**
     * Prepare a data upload for external signing.
     * Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
     *
     * @param string $data Raw bytes to upload.
     * @return array{upload_id: string, payments: array, total_amount: string, payment_vault_address: string, payment_token_address: string, rpc_url: string}
     */
    public function prepareDataUpload(string $data): array
    {
        $json = $this->doJson('POST', '/v1/data/prepare', ['data' => $this->b64Encode($data)]);
        return [
            'upload_id' => $json['upload_id'] ?? '',
            'payments' => $json['payments'] ?? [],
            'total_amount' => $json['total_amount'] ?? '',
            'payment_vault_address' => $json['payment_vault_address'] ?? '',
            'payment_token_address' => $json['payment_token_address'] ?? '',
            'rpc_url' => $json['rpc_url'] ?? '',
        ];
    }

    /**
     * Async: Prepare a data upload for external signing.
     *
     * @param string $data Raw bytes to upload.
     * @return PromiseInterface<array>
     */
    public function prepareDataUploadAsync(string $data): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/data/prepare', ['data' => $this->b64Encode($data)])->then(
            fn(?array $json) => [
                'upload_id' => $json['upload_id'] ?? '',
                'payments' => $json['payments'] ?? [],
                'total_amount' => $json['total_amount'] ?? '',
                'payment_vault_address' => $json['payment_vault_address'] ?? '',
                'payment_token_address' => $json['payment_token_address'] ?? '',
                'rpc_url' => $json['rpc_url'] ?? '',
            ],
        );
    }

    /**
     * Finalize an upload after an external signer has submitted payment transactions.
     *
     * @param string $uploadId The upload ID from prepareUpload.
     * @param array<string, string> $txHashes Map of quote_hash to tx_hash.
     * @return array{address: string, chunks_stored: int}
     */
    public function finalizeUpload(string $uploadId, array $txHashes): array
    {
        $json = $this->doJson('POST', '/v1/upload/finalize', [
            'upload_id' => $uploadId,
            'tx_hashes' => $txHashes,
        ]);
        return [
            'address' => $json['address'] ?? '',
            'chunks_stored' => (int) ($json['chunks_stored'] ?? 0),
        ];
    }

    /**
     * Async: Finalize an upload after an external signer has submitted payment transactions.
     *
     * @param string $uploadId The upload ID from prepareUpload.
     * @param array<string, string> $txHashes Map of quote_hash to tx_hash.
     * @return PromiseInterface<array{address: string, chunks_stored: int}>
     */
    public function finalizeUploadAsync(string $uploadId, array $txHashes): PromiseInterface
    {
        return $this->doJsonAsync('POST', '/v1/upload/finalize', [
            'upload_id' => $uploadId,
            'tx_hashes' => $txHashes,
        ])->then(
            fn(?array $json) => [
                'address' => $json['address'] ?? '',
                'chunks_stored' => (int) ($json['chunks_stored'] ?? 0),
            ],
        );
    }
}
