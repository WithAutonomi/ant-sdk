<?php

/**
 * Example 08: Pointers — a mutable, owner-signed reference to public data.
 *
 * Uploads two small pieces of public data, creates a pointer at the first,
 * updates it to the second, reads it back (get + resolve, then the bytes
 * through the pointer) and prints where the close group says it stands.
 *
 * Prerequisites:
 *   - antd running with a wallet and an owner key loaded at startup with
 *     `antd --pointer-keys <file-or-dir>` (key files from `ant pointer keygen`)
 *   - ANTD_POINTER_OWNER: the address of a pointer the daemon holds the key
 *     for (one of `$client->pointerKeys()`)
 *   - ANTD_BASE_URL (optional): the daemon's REST base URL, default
 *     http://localhost:8082
 *
 * Every pointer write pays (about the price of one chunk), and every attempt
 * pays again, so this example never retries a write.
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Autonomi\Antd\AntdClient;
use Autonomi\Antd\Errors\AlreadyExistsError;
use Autonomi\Antd\Models\PointerTargetKind;

/** The daemon accepts a 0x prefix but always returns bare hex. */
function normaliseAddress(string $address): string
{
    $address = strtolower(trim($address));
    return str_starts_with($address, '0x') ? substr($address, 2) : $address;
}

$owner = normaliseAddress((string) getenv('ANTD_POINTER_OWNER'));
if ($owner === '') {
    fwrite(STDERR, "Set ANTD_POINTER_OWNER to the address of a pointer the daemon holds the key for.\n");
    exit(1);
}
$url = getenv('ANTD_BASE_URL') ?: 'http://localhost:8082';
$client = new AntdClient($url);

$keys = array_map('normaliseAddress', $client->pointerKeys());
if (!in_array($owner, $keys, true)) {
    fwrite(STDERR, "The daemon at {$url} holds no key for {$owner} (it holds " . count($keys) . ").\n");
    exit(1);
}

// 1. Two pieces of public data for the pointer to point at.
$first = $client->dataPutPublic('Pointer target one: hello, Autonomi!')->address;
$second = $client->dataPutPublic('Pointer target two: hello again, Autonomi!')->address;
echo "First target:  {$first}\n";
echo "Second target: {$second}\n";

// 2. Create the pointer at the first. Each write pays once; nothing retries.
try {
    $created = $client->pointerCreate($owner, $first, PointerTargetKind::Chunk);
    echo "Created pointer {$created->address} at counter {$created->counter}\n";
} catch (AlreadyExistsError) {
    // Refused before paying: this owner was written by an earlier run.
    $moved = $client->pointerUpdate($owner, $first, PointerTargetKind::Chunk);
    echo "Pointer {$moved->address} already existed; pointed it at the first target (counter {$moved->counter})\n";
}

// 3. Update it to the second.
$updated = $client->pointerUpdate($owner, $second, PointerTargetKind::Chunk);
echo "Updated pointer to the second target, counter {$updated->counter}\n";

// 4. Read it back.
$record = $client->pointerGet($owner);
echo "Get: counter {$record->counter}, kind {$record->kind}, target {$record->target}, final "
   . ($record->isFinal ? 'yes' : 'no') . "\n";
$resolved = $client->pointerResolve($owner);
echo "Resolves to: {$resolved->target} ({$resolved->kind})\n";
$data = $client->dataGetPublic($resolved->target);
echo "Data through the pointer: {$data}\n";
if ($resolved->target !== $second || $data !== 'Pointer target two: hello again, Autonomi!') {
    throw new RuntimeException('The pointer does not lead to the second target!');
}

// 5. Where the close group says it stands.
$finality = $client->pointerFinality($owner);
echo "Finality: {$finality->rawStatus} ({$finality->answered}/{$finality->group} peers answered"
   . ($finality->counter !== null ? ", counter {$finality->counter}" : '') . ")\n";

echo "Pointer round-trip OK!\n";
