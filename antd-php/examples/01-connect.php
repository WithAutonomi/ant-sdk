<?php

/**
 * Example 01: Connect to antd and check health.
 *
 * Prerequisites: antd daemon running (ant dev start)
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Autonomi\Antd\AntdClient;

$client = new AntdClient('http://localhost:8082');

$health = $client->health();
echo "OK: " . ($health->ok ? 'true' : 'false') . "\n";
echo "Network: {$health->network}\n";
