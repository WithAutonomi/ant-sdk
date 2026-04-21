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
$result = $client->dataPutPrivate("secret message");
$dataMap = $result->address;  // Keep this secret!

// Retrieve (decrypt)
$data = $client->dataGetPrivate($dataMap);
echo $data;
```

## Files

```php
// Upload a file
$result = $client->fileUploadPublic("/path/to/file.txt");
echo "File address: {$result->address}\n";

// Download a file
$client->fileDownloadPublic($result->address, "/path/to/output.txt");

// Upload a directory
$result = $client->dirUploadPublic("/path/to/directory");

// Download a directory
$client->dirDownloadPublic($result->address, "/path/to/output_dir");

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
$est = $client->fileCost("/path/to/file.txt");
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
