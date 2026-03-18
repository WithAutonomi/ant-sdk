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
echo "File uploaded at: {$result->address} (cost: {$result->cost} atto)\n";

// Download the file
$client->fileDownloadPublic($result->address, '/tmp/downloaded.txt');
echo "File downloaded to /tmp/downloaded.txt\n";

// Upload a directory
$dirResult = $client->dirUploadPublic('/tmp/mydir');
echo "Directory uploaded at: {$dirResult->address} (cost: {$dirResult->cost} atto)\n";

// Download the directory
$client->dirDownloadPublic($dirResult->address, '/tmp/downloaded_dir');
echo "Directory downloaded to /tmp/downloaded_dir\n";

// Get archive manifest
$archive = $client->archiveGetPublic($result->address);
echo "Archive entries: " . count($archive->entries) . "\n";
foreach ($archive->entries as $entry) {
    echo "  {$entry->path} -> {$entry->address} ({$entry->size} bytes)\n";
}
