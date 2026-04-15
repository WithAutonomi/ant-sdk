<?php

/**
 * Example 04: Upload and download files and directories.
 *
 * Prerequisites: antd daemon running with a funded wallet.
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Autonomi\Antd\AntdClient;

$client = new AntdClient();

// Estimate file upload cost
$cost = $client->fileCost('/tmp/test.txt', true, false);
echo "Estimated cost: {$cost} atto\n";

// Upload a file
$result = $client->fileUploadPublic('/tmp/test.txt');
echo "File uploaded at: {$result->address}\n";
echo "  storage: {$result->storageCostAtto} atto, gas: {$result->gasCostWei} wei\n";
echo "  chunks: {$result->chunksStored}, mode: {$result->paymentModeUsed}\n";

// Download the file
$client->fileDownloadPublic($result->address, '/tmp/downloaded.txt');
echo "File downloaded to /tmp/downloaded.txt\n";

// Upload a directory
$dirResult = $client->dirUploadPublic('/tmp/mydir');
echo "Directory uploaded at: {$dirResult->address}\n";
echo "  storage: {$dirResult->storageCostAtto} atto, gas: {$dirResult->gasCostWei} wei\n";
echo "  chunks: {$dirResult->chunksStored}, mode: {$dirResult->paymentModeUsed}\n";

// Download the directory
$client->dirDownloadPublic($dirResult->address, '/tmp/downloaded_dir');
echo "Directory downloaded to /tmp/downloaded_dir\n";

