# antd-php

PHP SDK for the [antd](../antd/) daemon — the gateway to the Autonomi decentralized network.

## Installation

```bash
composer require autonomi/antd
```

## Quick Start

```php
<?php

require_once 'vendor/autoload.php';

use Autonomi\Antd\AntdClient;

$client = new AntdClient();

// Check daemon health
$health = $client->health();
echo "OK: " . ($health->ok ? 'true' : 'false') . ", Network: {$health->network}\n";

// Store data
$result = $client->dataPutPublic('Hello, Autonomi!');
echo "Stored at {$result->address} (cost: {$result->cost} atto)\n";

// Retrieve data
$data = $client->dataGetPublic($result->address);
echo "Retrieved: {$data}\n";
```

## Prerequisites

The antd daemon must be running. Start it with:

```bash
ant dev start
```

## Configuration

```php
// Default: http://localhost:8080, 300 second timeout
$client = new AntdClient();

// Custom URL
$client = new AntdClient('http://custom-host:9090');

// Custom timeout (in seconds)
$client = new AntdClient('http://localhost:8080', 30.0);

// Custom Guzzle HTTP client
$client = new AntdClient('http://localhost:8080', 300.0, $myGuzzleClient);
```

## API Reference

### Health
| Method | Description |
|--------|-------------|
| `health()` | Check daemon status |

### Data (Immutable)
| Method | Description |
|--------|-------------|
| `dataPutPublic(string $data)` | Store public data |
| `dataGetPublic(string $address)` | Retrieve public data |
| `dataPutPrivate(string $data)` | Store encrypted private data |
| `dataGetPrivate(string $dataMap)` | Retrieve private data |
| `dataCost(string $data)` | Estimate storage cost |

### Chunks
| Method | Description |
|--------|-------------|
| `chunkPut(string $data)` | Store a raw chunk |
| `chunkGet(string $address)` | Retrieve a chunk |

### Graph Entries (DAG Nodes)
| Method | Description |
|--------|-------------|
| `graphEntryPut(string $ownerSecretKey, array $parents, string $content, array $descendants)` | Create entry |
| `graphEntryGet(string $address)` | Read entry |
| `graphEntryExists(string $address)` | Check if exists |
| `graphEntryCost(string $publicKey)` | Estimate creation cost |

### Files & Directories
| Method | Description |
|--------|-------------|
| `fileUploadPublic(string $path)` | Upload a file |
| `fileDownloadPublic(string $address, string $destPath)` | Download a file |
| `dirUploadPublic(string $path)` | Upload a directory |
| `dirDownloadPublic(string $address, string $destPath)` | Download a directory |
| `archiveGetPublic(string $address)` | Get archive manifest |
| `archivePutPublic(Archive $archive)` | Create archive manifest |
| `fileCost(string $path, bool $isPublic, bool $includeArchive)` | Estimate upload cost |

## Error Handling

All errors extend `AntdError` (which extends `\RuntimeException`) and can be caught by type:

```php
use Autonomi\Antd\Errors\NotFoundError;
use Autonomi\Antd\Errors\PaymentError;

try {
    $data = $client->dataGetPublic($address);
} catch (NotFoundError $e) {
    echo "Data not found on network\n";
} catch (PaymentError $e) {
    echo "Insufficient funds\n";
}
```

| Error Type | HTTP Status | When |
|-----------|-------------|------|
| `BadRequestError` | 400 | Invalid parameters |
| `PaymentError` | 402 | Insufficient funds |
| `NotFoundError` | 404 | Resource not found |
| `AlreadyExistsError` | 409 | Resource exists |
| `ForkError` | 409 | Version conflict |
| `TooLargeError` | 413 | Payload too large |
| `InternalError` | 500 | Server error |
| `NetworkError` | 502 | Network unreachable |

## Examples

See the [examples/](examples/) directory:

- `01-connect.php` — Health check
- `02-data.php` — Public data storage and retrieval
- `03-chunks.php` — Raw chunk operations
- `04-files.php` — File and directory upload/download
- `05-graph.php` — Graph entry (DAG node) operations
- `06-private-data.php` — Private encrypted data
