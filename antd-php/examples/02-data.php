<?php

/**
 * Example 02: Store and retrieve public data.
 *
 * Prerequisites: antd daemon running with a funded wallet.
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Autonomi\Antd\AntdClient;

$client = new AntdClient();

// Estimate cost
$cost = $client->dataCost('Hello, Autonomi!');
echo "Estimated cost: {$cost} atto\n";

// Store public data
$result = $client->dataPutPublic('Hello, Autonomi!');
echo "Stored at: {$result->address} (cost: {$result->cost} atto)\n";

// Retrieve public data
$data = $client->dataGetPublic($result->address);
echo "Retrieved: {$data}\n";
