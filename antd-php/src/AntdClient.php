<?php

declare(strict_types=1);

namespace Autonomi\Antd;

use GuzzleHttp\Client;
use GuzzleHttp\Exception\GuzzleException;
use Autonomi\Antd\Errors\AntdError;
use Autonomi\Antd\Errors\ErrorFactory;
use Autonomi\Antd\Models\Archive;
use Autonomi\Antd\Models\ArchiveEntry;
use Autonomi\Antd\Models\GraphDescendant;
use Autonomi\Antd\Models\GraphEntry;
use Autonomi\Antd\Models\HealthStatus;
use Autonomi\Antd\Models\PutResult;

/**
 * REST client for the antd daemon.
 */
class AntdClient
{
    private Client $http;
    private string $baseUrl;

    public function __construct(
        string $baseUrl = 'http://localhost:8080',
        float $timeout = 300.0,
        ?Client $httpClient = null,
    ) {
        $this->baseUrl = rtrim($baseUrl, '/');
        $this->http = $httpClient ?? new Client([
            'base_uri' => $this->baseUrl,
            'timeout' => $timeout,
        ]);
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

    // --- Data ---

    /**
     * Store public immutable data on the network.
     */
    public function dataPutPublic(string $data): PutResult
    {
        $json = $this->doJson('POST', '/v1/data/public', [
            'data' => $this->b64Encode($data),
        ]);
        return new PutResult(
            cost: $json['cost'] ?? '',
            address: $json['address'] ?? '',
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
     * Store private encrypted data on the network.
     */
    public function dataPutPrivate(string $data): PutResult
    {
        $json = $this->doJson('POST', '/v1/data/private', [
            'data' => $this->b64Encode($data),
        ]);
        return new PutResult(
            cost: $json['cost'] ?? '',
            address: $json['data_map'] ?? '',
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
     * Estimate the cost of storing data.
     */
    public function dataCost(string $data): string
    {
        $json = $this->doJson('POST', '/v1/data/cost', [
            'data' => $this->b64Encode($data),
        ]);
        return $json['cost'] ?? '';
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
     * Retrieve a chunk by address.
     */
    public function chunkGet(string $address): string
    {
        $json = $this->doJson('GET', '/v1/chunks/' . $address);
        return $this->b64Decode($json['data'] ?? '');
    }

    // --- Graph ---

    /**
     * Create a new graph entry (DAG node).
     *
     * @param string $ownerSecretKey
     * @param string[] $parents
     * @param string $content
     * @param GraphDescendant[] $descendants
     */
    public function graphEntryPut(
        string $ownerSecretKey,
        array $parents,
        string $content,
        array $descendants,
    ): PutResult {
        $descs = array_map(
            fn(GraphDescendant $d) => ['public_key' => $d->publicKey, 'content' => $d->content],
            $descendants,
        );
        $json = $this->doJson('POST', '/v1/graph', [
            'owner_secret_key' => $ownerSecretKey,
            'parents' => $parents,
            'content' => $content,
            'descendants' => $descs,
        ]);
        return new PutResult(
            cost: $json['cost'] ?? '',
            address: $json['address'] ?? '',
        );
    }

    /**
     * Retrieve a graph entry by address.
     */
    public function graphEntryGet(string $address): GraphEntry
    {
        $json = $this->doJson('GET', '/v1/graph/' . $address);
        $descendants = [];
        foreach ($json['descendants'] ?? [] as $d) {
            $descendants[] = new GraphDescendant(
                publicKey: $d['public_key'] ?? '',
                content: $d['content'] ?? '',
            );
        }
        return new GraphEntry(
            owner: $json['owner'] ?? '',
            parents: $json['parents'] ?? [],
            content: $json['content'] ?? '',
            descendants: $descendants,
        );
    }

    /**
     * Check if a graph entry exists at the given address.
     */
    public function graphEntryExists(string $address): bool
    {
        $code = $this->doHead('/v1/graph/' . $address);
        if ($code === 404) {
            return false;
        }
        if ($code >= 300) {
            throw ErrorFactory::fromHttpStatus($code, 'graph entry exists check failed');
        }
        return true;
    }

    /**
     * Estimate the cost of creating a graph entry.
     */
    public function graphEntryCost(string $publicKey): string
    {
        $json = $this->doJson('POST', '/v1/graph/cost', [
            'public_key' => $publicKey,
        ]);
        return $json['cost'] ?? '';
    }

    // --- Files ---

    /**
     * Upload a local file to the network.
     */
    public function fileUploadPublic(string $path): PutResult
    {
        $json = $this->doJson('POST', '/v1/files/upload/public', [
            'path' => $path,
        ]);
        return new PutResult(
            cost: $json['cost'] ?? '',
            address: $json['address'] ?? '',
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
     * Upload a local directory to the network.
     */
    public function dirUploadPublic(string $path): PutResult
    {
        $json = $this->doJson('POST', '/v1/dirs/upload/public', [
            'path' => $path,
        ]);
        return new PutResult(
            cost: $json['cost'] ?? '',
            address: $json['address'] ?? '',
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
     * Retrieve an archive manifest by address.
     */
    public function archiveGetPublic(string $address): Archive
    {
        $json = $this->doJson('GET', '/v1/archives/public/' . $address);
        $entries = [];
        foreach ($json['entries'] ?? [] as $e) {
            $entries[] = new ArchiveEntry(
                path: $e['path'] ?? '',
                address: $e['address'] ?? '',
                created: (int) ($e['created'] ?? 0),
                modified: (int) ($e['modified'] ?? 0),
                size: (int) ($e['size'] ?? 0),
            );
        }
        return new Archive(entries: $entries);
    }

    /**
     * Create an archive manifest on the network.
     */
    public function archivePutPublic(Archive $archive): PutResult
    {
        $entries = array_map(
            fn(ArchiveEntry $e) => [
                'path' => $e->path,
                'address' => $e->address,
                'created' => $e->created,
                'modified' => $e->modified,
                'size' => $e->size,
            ],
            $archive->entries,
        );
        $json = $this->doJson('POST', '/v1/archives/public', [
            'entries' => $entries,
        ]);
        return new PutResult(
            cost: $json['cost'] ?? '',
            address: $json['address'] ?? '',
        );
    }

    /**
     * Estimate the cost of uploading a file.
     */
    public function fileCost(string $path, bool $isPublic, bool $includeArchive): string
    {
        $json = $this->doJson('POST', '/v1/cost/file', [
            'path' => $path,
            'is_public' => $isPublic,
            'include_archive' => $includeArchive,
        ]);
        return $json['cost'] ?? '';
    }
}
