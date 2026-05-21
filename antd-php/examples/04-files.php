<?php

/**
 * Example 04: Upload and download files publicly, with round-trip assertions.
 *
 * Prerequisites: antd daemon running with a funded wallet.
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Autonomi\Antd\AntdClient;

function rrmdir(string $dir): void {
    if (!is_dir($dir)) {
        if (file_exists($dir)) {
            unlink($dir);
        }
        return;
    }
    foreach (scandir($dir) as $entry) {
        if ($entry === '.' || $entry === '..') continue;
        $path = $dir . DIRECTORY_SEPARATOR . $entry;
        is_dir($path) ? rrmdir($path) : unlink($path);
    }
    rmdir($dir);
}

$tmp = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'antd-php-04-files';
rrmdir($tmp);
mkdir($tmp, 0o700, true);

$fileContent = "Hello from a file on Autonomi!";

$srcFile = $tmp . '/hello.txt';
file_put_contents($srcFile, $fileContent);

$client = new AntdClient();

$cost = $client->fileCost($srcFile, true);
echo "Estimated cost: {$cost->cost} atto ({$cost->chunkCount} chunks)\n";

$result = $client->filePutPublic($srcFile);
echo "File uploaded at: {$result->address}\n";
echo "  storage: {$result->storageCostAtto} atto, gas: {$result->gasCostWei} wei\n";
echo "  chunks: {$result->chunksStored}, mode: {$result->paymentModeUsed}\n";

$dstFile = $tmp . '/hello.txt.downloaded';
$client->fileGetPublic($result->address, $dstFile);
echo "File downloaded to {$dstFile}\n";

if (file_get_contents($dstFile) !== $fileContent) {
    rrmdir($tmp);
    fwrite(STDERR, "round-trip mismatch on hello.txt\n");
    exit(1);
}

rrmdir($tmp);
echo "File upload/download OK!\n";
