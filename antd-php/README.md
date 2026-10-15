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

### Pointers

A pointer is a small, owner-signed, mutable reference. Its address is derived from the owner's
key and never changes; what it points at (a chunk, such as public data's data map, or another
pointer) can be changed by the owner, and the owner can hand it over to another pointer for
good. The daemon holds the owner keys, loaded at startup with `antd --pointer-keys <file-or-dir>`
(files in the format `ant pointer keygen` writes), so every write names the pointer by its
address (`$owner`), never by a key. An owner the daemon holds no key for is a `BadRequestError`.
The pointer methods need the first antd release with pointers (after 0.15.0).

**Every write pays** (about the price of one chunk), and every attempt pays again. The client
never retries `pointerCreate`, `pointerUpdate`, `pointerTransfer` or `pointerFinalize`, and you
should not retry them automatically either. Reads are free to retry: a `CloseGroupShortfallError`
on a read usually clears once an update in flight settles.

**Counters are strings.** A pointer counter is an unsigned 64-bit integer and a final state (a
transfer) sits at 2^64 − 1, past PHP's signed `int`. The SDK keeps every counter as a validated,
canonical decimal string (digits only, within the u64 range; `PointerCounter::FINAL` is
`"18446744073709551615"`) and needs neither GMP nor BCMath. A counter that is not a decimal u64
string throws `\UnexpectedValueException`; it never reads as `0`.

| Method | Description |
|--------|-------------|
| `pointerKeys()` | Addresses of the pointers this daemon holds owner keys for, so can write |
| `pointerCreate(string $owner, string $target, ?PointerTargetKind $kind = null)` | Create a pointer, paid by the daemon wallet — returns `PointerWriteResult` (`address`, `stateId`, `counter`). `AlreadyExistsError` if it exists, refused before paying |
| `pointerUpdate(string $owner, string $target, ?PointerTargetKind $kind = null)` | Point a pointer at a new target, paid by the daemon wallet; creates it if it does not exist. `$kind` is `PointerTargetKind::Chunk` (the daemon's default) or `PointerTargetKind::Pointer` (a forwarding the owner can still change). `PointerFinalError` once transferred |
| `pointerTransfer(string $owner, string $recipient)` | Hand a pointer over for good to the recipient's pointer, which must exist. Irreversible. Returns `PointerTransferResult` with the close group's `finality` (null, with `finalityError`, if that check failed; the transfer still stands) |
| `pointerGet(string $address)` | Read a pointer — returns `PointerRecord` (`counter`, `target`, `kind`/`kindTag`, `isFinal`, `transferredTo`, the owner's public key). `NotFoundError` if there is none |
| `pointerResolve(string $address)` | Follow a chain of pointers (forwardings and transfers) to the target at its end — returns `PointerTarget` |
| `pointerFinality(string $address)` | Ask the whole close group where a pointer stands — returns `PointerFinality` with a `PointerFinalityStatus` of `Open`, `Settling`, `Unconfirmed`, `Final`, `Forked` or `Unknown` (a newer daemon's status; `rawStatus` keeps the string). Check `isFinal()` before relying on a transfer |
| `pointerController(string $address)` | Follow transfers to the pointer whose owner now decides — returns `PointerController` |
| `pointerPrepare(PointerPrepareRequest $request)` | External signer: the daemon signs `PointerPrepareRequest::create()`, `::update()` or `::transfer()` with its key and quotes it — returns `PointerPrepareResult` (wave-batch `payments` for `payForQuotes()`). Needs no daemon wallet. Other writes to the pointer throw `ConflictError` until it is finalized or expires |
| `pointerFinalize(string $uploadId, array $txHashes)` | External signer: store the prepared write once paid — returns `PointerFinalizeResult`. A write that falls short after payment throws `CloseGroupShortfallError` with `retryable === true`: repeat the same call (same `$uploadId`) to store it against the same payment |

Every pointer method has an `Async` variant too.

```php
use Autonomi\Antd\Models\PointerTargetKind;

$owner = $client->pointerKeys()[0];
$first = $client->dataPutPublic('version one')->address;
$second = $client->dataPutPublic('version two')->address;

$client->pointerCreate($owner, $first, PointerTargetKind::Chunk);   // pays
$client->pointerUpdate($owner, $second, PointerTargetKind::Chunk);  // pays again

$target = $client->pointerResolve($owner)->target;                  // === $second
echo $client->dataGetPublic($target), "\n";                          // "version two"
echo $client->pointerFinality($owner)->rawStatus, "\n";              // "open"
```

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
| `ForkError` | 409 | Version conflict; a pointer whose owner signed two final states with no majority on either (`code: "POINTER_FORKED"`) |
| `PointerFinalError` | 409 | The pointer was transferred or frozen; nothing can change it (`code: "POINTER_FINAL"`) |
| `ConflictError` | 409 | A pointer write while a prepared write to it awaits payment (`code: "CONFLICT"`) |
| `TooLargeError` | 413 | Payload too large |
| `InternalError` | 500 | Server error |
| `NetworkError` | 502 | Network unreachable |
| `PartialUploadError` | 502 | A finalize stored only part of the upload (`code: "PARTIAL_UPLOAD"`; extends `NetworkError`) |
| `ServiceUnavailableError` | 503 | The daemon lacks a dependency, such as a wallet |
| `CloseGroupShortfallError` | 503 | Too few of the close group answered or stored (`code: "CLOSE_GROUP_SHORTFALL"`); `retryable` is `true` only for a pointer finalize that kept the paid state |

The 409s and 503s above are told apart by the error body's `code`: `POINTER_FINAL`,
`POINTER_FORKED` and `CONFLICT` never read as `AlreadyExistsError`, and `CLOSE_GROUP_SHORTFALL`
never reads as `ServiceUnavailableError` (all three new classes extend `AntdError` directly).
`CLOSE_GROUP_SHORTFALL` is not only for pointers: a daemon with the pointer API reports a close
group that fell short on any call this way, where an older daemon sent a 500 (`InternalError`).

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
- `08-pointers.php` — Create, update, resolve and check the finality of a pointer
  (`ANTD_POINTER_OWNER=<address> php examples/08-pointers.php`; set `ANTD_BASE_URL` for a daemon
  other than `http://localhost:8082`). Each run pays for its pointer writes.

## Versioning and releases

Releases are cut from the monorepo: a `php-vX.Y.Z` tag on `ant-sdk` is verified,
split, and pushed to the mirror as `vX.Y.Z`, which Packagist picks up as the
package version. There is no `version` field in `composer.json` — Composer
derives it from the mirror's tags.

## License

Dual-licensed under either the [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE)
license, at your option.
