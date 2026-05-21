<?php

/**
 * Example 06: Store and retrieve private (encrypted) data.
 *
 * Prerequisites: antd daemon running with a funded wallet.
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Autonomi\Antd\AntdClient;

$client = new AntdClient();

// Store private (encrypted) data. The DataMap is returned to the caller;
// it is NOT stored on-network.
$result = $client->dataPut('my secret data');
echo "Private data stored\n";
echo "Data map: {$result->dataMap}\n";
echo "Chunks: {$result->chunksStored}, mode: {$result->paymentModeUsed}\n";

// Retrieve private data using the caller-held DataMap.
$data = $client->dataGet($result->dataMap);
echo "Retrieved: {$data}\n";
