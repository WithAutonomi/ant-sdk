<?php

/**
 * Example 02: Store and retrieve public data, with cost estimation.
 *
 * Prerequisite: antd daemon running on local testnet.
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Autonomi\Antd\AntdClient;

$client = new AntdClient();

$payload = 'Hello, Autonomi!';

// Estimate cost before storing
$est = $client->dataCost($payload);
echo "Estimate: {$est->fileSize} bytes in {$est->chunkCount} chunks, "
   . "storage {$est->cost} atto, gas {$est->estimatedGasCostWei} wei, "
   . "mode {$est->paymentMode}\n";

// Store public data
$result = $client->dataPutPublic($payload);
echo "Stored at address: {$result->address}\n";
echo "Chunks stored: {$result->chunksStored}, payment mode: {$result->paymentModeUsed}\n";

// Retrieve it back
$data = $client->dataGetPublic($result->address);
echo "Retrieved: {$data}\n";

if ($data !== $payload) {
    throw new RuntimeException('Round-trip mismatch!');
}
echo "Public data round-trip OK!\n";
