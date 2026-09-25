# antd-php

PHP SDK for the [antd](https://github.com/WithAutonomi/ant-sdk/tree/main/antd) daemon — the gateway to the Autonomi decentralized network.

> **Source of truth:** this SDK is developed in the [ant-sdk monorepo](https://github.com/WithAutonomi/ant-sdk/tree/main/antd-php).
> [`WithAutonomi/antd-php`](https://github.com/WithAutonomi/antd-php) is a **read-only mirror** of that
> directory, kept in sync by CI so [Packagist](https://packagist.org/packages/autonomi/antd) can index it.
> Open issues and pull requests against `ant-sdk`; anything pushed to the mirror is overwritten.

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
echo "Stored at {$result->address} (chunks: {$result->chunksStored})\n";

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
// Default: http://localhost:8082, 300 second timeout
$client = new AntdClient();

// Custom URL
$client = new AntdClient('http://custom-host:9090');

// Custom timeout (in seconds)
$client = new AntdClient('http://localhost:8082', 30.0);

// Custom Guzzle HTTP client
$client = new AntdClient('http://localhost:8082', 300.0, $myGuzzleClient);
```

## API Reference

### Health
| Method | Description |
|--------|-------------|
| `health()` | Check daemon status |

### Data (Immutable)
| Method | Description |
|--------|-------------|
| `dataPutPublic(string $data, string $paymentMode = 'auto')` | Store public data — returns `DataPutPublicResult` (DataMap stored on-network) |
| `dataGetPublic(string $address)` | Retrieve public data by address |
| `dataPut(string $data, string $paymentMode = 'auto')` | Store encrypted private data — returns `DataPutResult` (DataMap returned to caller) |
| `dataGet(string $dataMap)` | Retrieve private data using a caller-held DataMap |
| `dataCost(string $data, string $paymentMode = 'auto')` | Estimate storage cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

### Chunks
| Method | Description |
|--------|-------------|
| `chunkPut(string $data)` | Store a raw chunk |
| `chunkGet(string $address)` | Retrieve a chunk |

### Files
| Method | Description |
|--------|-------------|
| `filePut(string $path, string $paymentMode = 'auto')` | Upload a file privately — returns `FilePutResult` (DataMap returned to caller) |
| `fileGet(string $dataMap, string $destPath)` | Download a private file using a caller-held DataMap |
| `filePutPublic(string $path, string $paymentMode = 'auto')` | Upload a file publicly — returns `FilePutPublicResult` (DataMap stored on-network) |
| `fileGetPublic(string $address, string $destPath)` | Download a public file by address |
| `fileCost(string $path, bool $isPublic, string $paymentMode = 'auto')` | Estimate upload cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

## Async Usage

Every method has an `Async` variant that returns a `GuzzleHttp\Promise\PromiseInterface` instead of blocking. This lets you fire off multiple requests concurrently and wait for results when you need them.

### Basic promise usage

```php
use Autonomi\Antd\AntdClient;

$client = new AntdClient();

// Fire an async request — returns immediately
$promise = $client->dataPutPublicAsync('Hello, async Autonomi!');

// Block until the result is available
$result = $promise->wait();
echo "Stored at {$result->address}\n";
```

### Chaining with then() / otherwise()

```php
$client->dataGetPublicAsync($address)
    ->then(function (string $data) {
        echo "Retrieved: {$data}\n";
    })
    ->otherwise(function (\Throwable $e) {
        echo "Error: {$e->getMessage()}\n";
    })
    ->wait();
```

### Concurrent requests

```php
use GuzzleHttp\Promise\Utils;

// Launch several uploads in parallel
$promises = [
    'a' => $client->dataPutPublicAsync('chunk-a'),
    'b' => $client->dataPutPublicAsync('chunk-b'),
    'c' => $client->dataPutPublicAsync('chunk-c'),
];

// Wait for all to complete — returns ['a' => PutResult, 'b' => PutResult, ...]
$results = Utils::unwrap($promises);

foreach ($results as $key => $result) {
    echo "{$key}: stored at {$result->address}\n";
}
```

### Settling without throwing

```php
use GuzzleHttp\Promise\Utils;

// settle() never throws — it returns the state of every promise
$outcomes = Utils::settle($promises)->wait();

foreach ($outcomes as $key => $outcome) {
    if ($outcome['state'] === 'fulfilled') {
        echo "{$key}: {$outcome['value']->address}\n";
    } else {
        echo "{$key}: failed — {$outcome['reason']->getMessage()}\n";
    }
}
```

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
| `PartialUploadError` | 502 | A finalize stored only part of the upload (`code: "PARTIAL_UPLOAD"`; extends `NetworkError`) |

### Partial uploads

An external-signer finalize (`finalizeUpload`, `finalizeChunkUpload`) can fail *after* the
payment settled: some chunks store, others miss quorum after the daemon's own retries. The
SDK throws `PartialUploadError` with `chunksStored` / `chunksFailed` / `totalChunks` and two
flags, `retryable` and `retentionKnown` (`retryable` implies `retentionKnown`). The on-chain
payment persists and the stored chunks stay on the network; what to do next depends on the
flags:

- **`retryable`** (antd ≥ 0.14.0): the daemon kept the paid attempt under the same
  `upload_id`. Call the **same** finalize method again with the same `upload_id` and tx hashes
  to store the remainder against the same payment — no re-prepare, no second signature, no
  double payment. Bound that loop: a persistent failure throws on every call, so cap the
  attempts and treat a `chunksFailed` that stops shrinking as stuck.
- **`retentionKnown && !retryable`**: the daemon confirmed nothing was retained (a
  daemon-wallet upload, or a merkle finalize with deliberately unpaid batches). Re-prepare the
  same content — already-stored chunks are skipped.
- **`!retentionKnown`**: retention is unknown. The daemon may still hold the paid attempt (it
  records the resume handle before it returns the error), so stop automatic recovery, keep the
  `upload_id` and the original tx hashes, and reconcile before re-preparing or paying again.
  Never pay again on this signal alone. Daemons older than 0.14.0 never send `retryable`, so
  their partial uploads read as unknown.

```php
use Autonomi\Antd\Errors\PartialUploadError;

try {
    $result = $client->finalizeUpload($prep->uploadId, $txHashes);
} catch (PartialUploadError $e) {
    if ($e->retryable) {
        // Same upload_id, same payment: retry finalizeUpload() with the same
        // arguments (bounded — see finalizeWithRetry() in examples/07-external-signer.php).
    } elseif ($e->retentionKnown) {
        // The daemon confirmed nothing was retained: re-prepare the same content.
    } else {
        // Retention unknown: keep $prep->uploadId and $txHashes and reconcile
        // before re-preparing or paying again. Never pay again on this alone.
    }
}
```

The body is read strictly: a count comes only from a non-negative JSON integer (anything else
reads `0`), `retryable` is `true` only for the JSON boolean `true`, `retentionKnown` is `true`
only when `retryable` is a JSON boolean (missing, `null` or any other type reads as unknown),
and a `code` other than the string `"PARTIAL_UPLOAD"` keeps the plain `NetworkError`. A
malformed error body never escapes as a PHP `TypeError`; the message falls back to the raw body
when `error` is not a string.

`PartialUploadError` extends `NetworkError`, so a pre-existing `catch (NetworkError $e)` still
catches it; catch the subclass first when you need the counts. The full contract is in
[docs/external-signer-flow.md](https://github.com/WithAutonomi/ant-sdk/blob/main/docs/external-signer-flow.md)
under "6. Retry a partial store".

## Examples

See the [examples/](examples/) directory:

- `01-connect.php` — Health check
- `02-data.php` — Public data storage and retrieval
- `03-chunks.php` — Raw chunk operations
- `04-files.php` — File and directory upload/download
- `06-private-data.php` — Private encrypted data
- `07-external-signer.php` — External-signer flow with a bounded partial-upload retry

## Versioning and releases

Releases are cut from the monorepo: a `php-vX.Y.Z` tag on `ant-sdk` is verified,
split, and pushed to the mirror as `vX.Y.Z`, which Packagist picks up as the
package version. There is no `version` field in `composer.json` — Composer
derives it from the mirror's tags.

## License

Dual-licensed under either the [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE)
license, at your option.
