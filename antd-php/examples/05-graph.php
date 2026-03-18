<?php

/**
 * Example 05: Create and read graph entries (DAG nodes).
 *
 * Prerequisites: antd daemon running with a funded wallet.
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Autonomi\Antd\AntdClient;

$client = new AntdClient();

// Estimate cost
$cost = $client->graphEntryCost('your_public_key_hex');
echo "Estimated cost: {$cost} atto\n";

// Create a graph entry
$result = $client->graphEntryPut('your_secret_key_hex', [], 'content_hex', []);
echo "Graph entry at: {$result->address} (cost: {$result->cost} atto)\n";

// Check existence
$exists = $client->graphEntryExists($result->address);
echo "Exists: " . ($exists ? 'true' : 'false') . "\n";

// Read the graph entry
$entry = $client->graphEntryGet($result->address);
echo "Owner: {$entry->owner}\n";
echo "Content: {$entry->content}\n";
echo "Parents: " . count($entry->parents) . "\n";
echo "Descendants: " . count($entry->descendants) . "\n";
