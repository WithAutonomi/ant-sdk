<?php

/**
 * Example 06: Store and retrieve private (encrypted) data.
 *
 * Prerequisites: antd daemon running with a funded wallet.
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Autonomi\Antd\AntdClient;

$client = new AntdClient();

// Store private data (encrypted on the network)
$result = $client->dataPutPrivate('my secret data');
echo "Private data stored (cost: {$result->cost} atto)\n";
echo "Data map: {$result->address}\n";

// Retrieve private data using the data map
$data = $client->dataGetPrivate($result->address);
echo "Retrieved: {$data}\n";
