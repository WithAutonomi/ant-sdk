<?php

/**
 * Example 09: Manifests — one `.ant` file or `ant://` link for a set of files.
 *
 * Uploads two small pieces of public data, builds a manifest that names them
 * `notes/one.txt` and `notes/two.txt` under the root name `example`, prints
 * its link and entries, then decodes the link with `resolve` to read each
 * entry's exact size back from the network.
 *
 * Prerequisites:
 *   - antd running with a funded wallet (the two uploads pay; building and
 *     decoding the manifest upload and pay for nothing)
 *   - ANTD_BASE_URL (optional): the daemon's REST base URL, default
 *     http://localhost:8082
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Autonomi\Antd\AntdClient;
use Autonomi\Antd\Models\BuildManifestOptions;
use Autonomi\Antd\Models\ManifestEntryInput;

$url = getenv('ANTD_BASE_URL') ?: 'http://localhost:8082';
$client = new AntdClient($url);

// 1. Two pieces of public data for the manifest to describe (each pays).
$payloads = [
    'notes/one.txt' => 'Manifest entry one: hello, Autonomi!',
    'notes/two.txt' => 'Manifest entry two: hello again, Autonomi!',
];
$entries = [];
foreach ($payloads as $path => $payload) {
    $address = $client->dataPutPublic($payload)->address;
    echo "Uploaded {$path}: {$address}\n";
    $entries[] = new ManifestEntryInput(path: $path, address: $address);
}

// 2. Build the manifest. Free: nothing is uploaded or paid for.
$built = $client->buildManifest($entries, new BuildManifestOptions(name: 'example'));
echo "Manifest: " . strlen($built->manifest) . " bytes\n";
if ($built->link === null) {
    // Too long for a link (over 1,500 bytes): share the .ant bytes instead.
    throw new RuntimeException('The manifest is too large for an ant:// link!');
}
echo "Link: {$built->link}\n";
foreach ($built->entries as $entry) {
    echo "  {$entry->effectiveName} -> {$entry->contentAddress} ({$entry->kind})\n";
}

// 3. Decode the link, resolving each entry's DataMap for its exact size.
$decoded = $client->decodeManifestLink($built->link, true);
echo "Decoded {$decoded->source} '" . ($decoded->name ?? '') . "' with " . count($decoded->entries) . " entries\n";
foreach ($decoded->entries as $entry) {
    $size = $entry->exactSize !== null ? "{$entry->exactSize} bytes" : 'size unknown';
    echo "  {$entry->effectiveName}: {$size}" . ($entry->error !== null ? " (error: {$entry->error})" : '') . "\n";
    if ($entry->exactSize !== strlen($payloads[$entry->effectiveName] ?? '')) {
        throw new RuntimeException("{$entry->effectiveName} does not resolve to the uploaded size!");
    }
}

echo "Manifest round-trip OK!\n";
