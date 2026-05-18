<?php

/**
 * Example 04: Upload and download files and directories, with round-trip assertions.
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
$dirFileContent = "File inside an uploaded directory.";

$srcFile = $tmp . '/hello.txt';
file_put_contents($srcFile, $fileContent);

$srcDir = $tmp . '/mydir';
mkdir($srcDir, 0o700, true);
file_put_contents($srcDir . '/file_in_dir.txt', $dirFileContent);

$client = new AntdClient();

$cost = $client->fileCost($srcFile, true, false);
echo "Estimated cost: {$cost} atto\n";

$result = $client->fileUploadPublic($srcFile);
echo "File uploaded at: {$result->address}\n";
echo "  storage: {$result->storageCostAtto} atto, gas: {$result->gasCostWei} wei\n";
echo "  chunks: {$result->chunksStored}, mode: {$result->paymentModeUsed}\n";

$dstFile = $tmp . '/hello.txt.downloaded';
$client->fileDownloadPublic($result->address, $dstFile);
echo "File downloaded to {$dstFile}\n";

if (file_get_contents($dstFile) !== $fileContent) {
    rrmdir($tmp);
    fwrite(STDERR, "round-trip mismatch on hello.txt\n");
    exit(1);
}

$dirResult = $client->dirUploadPublic($srcDir);
echo "Directory uploaded at: {$dirResult->address}\n";
echo "  storage: {$dirResult->storageCostAtto} atto, gas: {$dirResult->gasCostWei} wei\n";
echo "  chunks: {$dirResult->chunksStored}, mode: {$dirResult->paymentModeUsed}\n";

$dstDir = $tmp . '/mydir_copy';
$client->dirDownloadPublic($dirResult->address, $dstDir);
echo "Directory downloaded to {$dstDir}\n";

if (file_get_contents($dstDir . '/file_in_dir.txt') !== $dirFileContent) {
    rrmdir($tmp);
    fwrite(STDERR, "directory round-trip mismatch on file_in_dir.txt\n");
    exit(1);
}

rrmdir($tmp);
echo "File and directory upload/download OK!\n";
