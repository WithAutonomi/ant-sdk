<?php

/**
 * Example 03: Store and retrieve raw chunks.
 *
 * Prerequisites: antd daemon running with a funded wallet.
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Autonomi\Antd\AntdClient;

$client = new AntdClient();

// Store a chunk
$result = $client->chunkPut('raw chunk data');
echo "Chunk stored at: {$result->address} (cost: {$result->cost} atto)\n";

// Retrieve the chunk
$data = $client->chunkGet($result->address);
echo "Retrieved chunk: {$data}\n";
