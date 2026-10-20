# PHP Quickstart

A comprehensive guide to using the Autonomi network with the PHP SDK.

## Setup

```bash
# Install via Composer
composer require autonomi/antd

# Start local testnet
ant dev start
```

## Connecting

```php
<?php

use Autonomi\Antd\AntdClient;

// REST transport (default)
$client = new AntdClient();

// Custom endpoint
$client = new AntdClient(transport: 'rest', baseUrl: 'http://localhost:8082');

// gRPC transport
$client = new AntdClient(transport: 'grpc', target: 'localhost:50051');
```

## Health Check

```php
$status = $client->health();
echo "Healthy: " . ($status->ok ? 'true' : 'false') . "\n";
echo "Network: {$status->network}\n";  // "local", "default", or "alpha"
```

## Public Data

Store and retrieve arbitrary bytes on the network.

```php
// Store
$result = $client->dataPutPublic("Hello, Autonomi!");
echo "Address: {$result->address}\n";
echo "Cost: {$result->cost} atto tokens\n";

// Retrieve
$data = $client->dataGetPublic($result->address);
echo $data;  // "Hello, Autonomi!"

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
$est = $client->dataCost("some data");
echo "Estimate: {$est->fileSize} bytes in {$est->chunkCount} chunks, {$est->cost} atto, gas {$est->estimatedGasCostWei} wei, mode {$est->paymentMode}\n";
```

## Private Data

Encrypted data -- only accessible with the data map.

```php
// Store (self-encrypting)
$result = $client->dataPut("secret message");
$dataMap = $result->dataMap;  // Keep this secret!

// Retrieve (decrypt)
$data = $client->dataGet($dataMap);
echo $data;
```

## Files

```php
// Upload a file
$result = $client->filePutPublic("/path/to/file.txt");
echo "File address: {$result->address}\n";

// Download a file
$client->fileGetPublic($result->address, "/path/to/output.txt");

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
$est = $client->fileCost("/path/to/file.txt");
```

## Pointers

A pointer is an owner-signed address you can move to new data. antd signs with the owner keys it loaded at startup (`antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`), so `owner` is the pointer's address, never a key. Every create, update and transfer pays (about the price of one chunk) and is never retried; reads are free. A transfer hands the pointer over to another pointer for good. Needs antd 0.16.0 or later (the first release with pointers). Walk-through: [Tutorial: Point at a Public File and Update It](tutorial-pointers.md).

```php
$owner = $client->pointerKeys()[0];                        // a pointer antd can write

$v1 = $client->dataPutPublic("version 1")->address;
$v2 = $client->dataPutPublic("version 2")->address;

$client->pointerCreate($owner, $v1);                       // pays; counter "0"
$client->pointerUpdate($owner, $v2);                       // pays again; counter "1"
$target = $client->pointerResolve($owner)->target;         // === $v2 (free)

echo $client->pointerFinality($owner)->rawStatus, "\n";    // "open"
```

Counters are validated decimal strings, because a final pointer sits at 2^64 − 1, past PHP's `int`. `pointerTransfer`, `pointerGet`, `pointerController`, `pointerPrepare` and `pointerFinalize` complete the set (REST only), each with an `Async` variant.

Runnable example: `antd-php/examples/08-pointers.php`. Set `ANTD_POINTER_OWNER` to an address the daemon holds a key for, one it has not written yet (each run creates the pointer and pays for its writes), and `ANTD_BASE_URL` for a daemon other than `http://localhost:8082`:

```bash
cd antd-php
ANTD_POINTER_OWNER=<address> php examples/08-pointers.php
```

## Error Handling

```php
use Autonomi\Antd\Exceptions\AntdException;
use Autonomi\Antd\Exceptions\NotFoundException;
use Autonomi\Antd\Exceptions\PaymentException;
use Autonomi\Antd\Exceptions\NetworkException;

try {
    $client->dataGetPublic("nonexistent");
} catch (NotFoundException $e) {
    echo "Not found: {$e->getMessage()}\n";
} catch (PaymentException $e) {
    echo "Payment issue: {$e->getMessage()}\n";
} catch (NetworkException $e) {
    echo "Network unreachable: {$e->getMessage()}\n";
} catch (AntdException $e) {
    echo "Error ({$e->getStatusCode()}): {$e->getMessage()}\n";
}
```

Exception hierarchy:

| Exception | HTTP Code | When |
|-----------|-----------|------|
| `BadRequestException` | 400 | Invalid parameters |
| `PaymentException` | 402 | Insufficient funds |
| `NotFoundException` | 404 | Resource not found |
| `AlreadyExistsException` | 409 | Duplicate creation |
| `ForkException` | 409 | Version conflict |
| `TooLargeException` | 413 | Payload too large |
| `InternalException` | 500 | Server error |
| `NetworkException` | 502 | Network unreachable |

## Manifests

A manifest describes a set of files as one `ant://manifest/` link, or as a `.ant` file when the link would be too long. Each entry is either a public file's address or an embedded DataMap (the manifest is then the key to a private file), with an optional path. Building and decoding upload and pay for nothing: upload the files first, then describe them. Needs antd 0.16.0 or later. Walk-through: [Tutorial: Share a Set of Files as One Link](tutorial-manifests.md).

```php
use Autonomi\Antd\Models\BuildManifestOptions;
use Autonomi\Antd\Models\ManifestEntryInput;

$public = $client->dataPutPublic('first file')->address;    // pays
$private = $client->dataPut('second file')->dataMap;        // pays

$built = $client->buildManifest([                           // free
    new ManifestEntryInput(path: 'notes/one.txt', address: $public),
    new ManifestEntryInput(path: 'notes/two.txt', dataMap: $private),
], new BuildManifestOptions(name: 'notes'));
echo $built->link, "\n";                                    // null if over 1,500 bytes: share $built->manifest instead

foreach ($client->decodeManifest($built->manifest, resolve: true)->entries as $entry) {
    echo "{$entry->effectiveName}: {$entry->exactSize} bytes\n";
}
```

`decodeManifestLink($link, resolve: true)` takes a link instead. The `.ant` bytes are a plain PHP string, and every manifest method has an `Async` variant.

Runnable example: `antd-php/examples/09-manifests.php`. Its two uploads pay; the manifest calls do not.

```bash
cd antd-php
ANTD_BASE_URL=http://localhost:8082 php examples/09-manifests.php
```

## Examples

```bash
# Run individual examples
ant dev example connect -l php
ant dev example data -l php
ant dev example all -l php

# Or directly
php antd-php/examples/01_connect.php
php antd-php/examples/02_data.php
```

See `antd-php/examples/` for the complete set of examples.
