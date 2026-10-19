# antd_client (antd-dart)

Dart SDK for the [antd](https://github.com/WithAutonomi/ant-sdk/tree/main/antd) daemon — the gateway to the Autonomi decentralized network.

Published on pub.dev as [`antd_client`](https://pub.dev/packages/antd_client).

## Installation

```bash
dart pub add antd_client
```

Or add to your `pubspec.yaml`:

```yaml
dependencies:
  antd_client: ^0.2.0
```

## Compatibility

This package talks to a running antd daemon; it does not join the network itself. Dart 3.0+. Tested against antd 0.13.x; the `retryable` field behind `PartialUploadError.retryable` / `retentionKnown` is sent by antd 0.14.0 and later (over REST, partial uploads from older daemons read as retention unknown). The [pointer methods](#pointers) need the antd release after 0.15.0, the first with pointers. Both the REST client (`AntdClient`) and the gRPC client (`GrpcAntdClient`) are included; the gRPC stubs are pre-generated, so `protoc` is only needed if you regenerate them.

## Quick Start

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:antd_client/antd_client.dart';

void main() async {
  final client = AntdClient();

  try {
    // Check daemon health
    final health = await client.health();
    print('OK: ${health.ok}, Network: ${health.network}');

    // Store data
    final result = await client.dataPutPublic(
      Uint8List.fromList(utf8.encode('Hello, Autonomi!')),
    );
    print('Stored at ${result.address} (chunks: ${result.chunksStored})');

    // Retrieve data
    final data = await client.dataGetPublic(result.address);
    print('Retrieved: ${utf8.decode(data)}');
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
```

## Payment Mode

All `*put*` and `*cost*` operations accept a `PaymentMode` parameter that
controls how on-chain payments for stored chunks are bundled:

| Mode | Behavior |
|---|---|
| `PaymentMode.auto` (default) | Daemon picks merkle for large uploads, single for small. |
| `PaymentMode.merkle` | One on-chain transaction with a merkle proof covering all chunks. Cheaper for large uploads. Requires ≥2 chunks. |
| `PaymentMode.single` | N transactions, one per chunk. Works for any chunk count. |

```dart
final result = await client.filePut('/tmp/big.bin', paymentMode: PaymentMode.merkle);
```

## gRPC Transport

The SDK includes a `GrpcAntdClient` class that provides the same async
methods as the REST `AntdClient`, but communicates over gRPC.

### Setup

Add the gRPC dependencies (already included in `pubspec.yaml`):

```yaml
dependencies:
  grpc: ^4.0.1
  protobuf: ^4.1.0
```

The Dart protobuf/gRPC stubs in `lib/src/generated/` are committed. After
changing the proto definitions, regenerate them and commit the result (CI
fails when they drift):

```bash
# Install the Dart protoc plugin (pin to 22.3.0 — the script checks it; newer
# plugins emit code targeting protobuf 6+, which conflicts with web3dart's
# transitive deps).
dart pub global activate protoc_plugin 22.3.0

# Generate stubs into lib/src/generated/
./tool/generate_proto.sh
```

### Usage

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:antd_client/src/grpc_client.dart';

void main() async {
  final client = GrpcAntdClient.withChannel();

  // Or custom host/port:
  // final client = GrpcAntdClient(host: 'my-host', port: 50051);

  try {
    final health = await client.health();
    print('OK: ${health.ok}, Network: ${health.network}');

    final result = await client.dataPutPublic(
      Uint8List.fromList(utf8.encode('Hello via gRPC!')),
    );
    print('Stored at ${result.address}');

    final data = await client.dataGetPublic(result.address);
    print('Retrieved: ${utf8.decode(data)}');
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    await client.close();
  }
}
```

The `GrpcAntdClient` throws the same `AntdError` hierarchy as the REST client,
translating gRPC status codes to the appropriate error subclass.

> **Note:** Wallet operations (address, balance, approve) are REST-only. The gRPC `PutDataResponse` / `PutPublicDataResponse` messages only carry the address/dataMap; `chunksStored` / `paymentModeUsed` are populated by REST only.

## Prerequisites

The antd daemon must be running. Start it with:

```bash
ant dev start
```

## Configuration

```dart
// Default: http://localhost:8082, 5 minute timeout
final client = AntdClient();

// Custom URL
final client = AntdClient(baseUrl: 'http://custom-host:9090');

// Custom timeout
final client = AntdClient(timeout: Duration(seconds: 30));

// Custom HTTP client (e.g. for testing)
final client = AntdClient(httpClient: myHttpClient);
```

## API Reference

All methods return `Future<T>` and can throw `AntdError` subclasses.

The unqualified verb (`dataPut`, `filePut`, `dataGet`, `fileGet`) is the
**private** variant — DataMaps are returned to the caller and not stored
on-network. The `*Public` variants store the DataMap on-network and return
a shareable address.

### Health
| Method | Description |
|--------|-------------|
| `health()` | Check daemon status |

### Data
| Method | Description |
|--------|-------------|
| `dataPutPublic(data, {paymentMode})` | Store public data — returns `DataPutPublicResult` (DataMap stored on-network) |
| `dataGetPublic(address)` | Retrieve public data by address |
| `dataPut(data, {paymentMode})` | Store encrypted private data — returns `DataPutResult` (DataMap returned to caller) |
| `dataGet(dataMap)` | Retrieve private data using a caller-held DataMap |
| `dataCost(data, {paymentMode})` | Estimate storage cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

### Chunks
| Method | Description |
|--------|-------------|
| `chunkPut(data)` | Store a raw chunk |
| `chunkGet(address)` | Retrieve a chunk |
| `prepareChunkUpload(data)` | External-signer prepare step |
| `finalizeChunkUpload(uploadId, txHashes)` | External-signer finalize step |

### Files
| Method | Description |
|--------|-------------|
| `filePut(path, {paymentMode})` | Upload a file privately — returns `FilePutResult` (DataMap returned to caller) |
| `fileGet(dataMap, destPath)` | Download a private file using a caller-held DataMap |
| `filePutPublic(path, {paymentMode})` | Upload a file publicly — returns `FilePutPublicResult` (DataMap stored on-network) |
| `fileGetPublic(address, destPath)` | Download a public file by address |
| `fileCost(path, {isPublic, paymentMode})` | Estimate upload cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

### Pointers

A pointer is a small, owner-signed, mutable reference. Its address is derived from the owner's key and never changes; what it points at (a chunk, such as a public file's data map, or another pointer) can be updated by the owner, who can also hand the pointer over to another pointer for good. The daemon holds the owner keys, loaded at startup with `antd --pointer-keys <file-or-dir>` (files in the format `ant pointer keygen` writes), so every write names the pointer by its address (`owner`), never by a key. Both `AntdClient` and `GrpcAntdClient` have these methods.

**Every write pays** (about the price of one chunk), **and every attempt pays again.** The SDK never retries a request, and you should not retry `pointerCreate`, `pointerUpdate`, `pointerTransfer` or `pointerFinalize` automatically either; the one exception is a `pointerFinalize` that throws a `CloseGroupShortfallError` with `retryable` set (see below). Reads are free to retry: a read during an update or churn can throw `CloseGroupShortfallError`, which usually clears once it settles.

Counters are `BigInt`s, parsed strictly from the daemon's decimal strings: a final state (after a transfer) sits at `pointerFinalCounter`, 2^64 − 1, past a Dart `int` (and past 2^53 on the web). A malformed counter throws `InternalError` rather than reading as zero. Fields the daemon leaves unset (REST `null`, gRPC `""` or an absent message) are `null`. The daemon accepts addresses with a `0x` prefix but always returns bare hex, so normalise before comparing.

| Method | Description |
|--------|-------------|
| `pointerKeys()` | Addresses of the pointers this daemon holds owner keys for, so can write |
| `pointerCreate(owner, target, {kind})` | Create a pointer, paid by the daemon wallet — returns `PointerWriteResult` (`address`, `stateId`, `counter`). `AlreadyExistsError` if it exists, refused before paying. `kind` is `PointerKind.chunk` (default) or `PointerKind.pointer` (a forwarding the owner can still change) |
| `pointerUpdate(owner, target, {kind})` | Point a pointer at a new target, paid by the daemon wallet; creates it if it does not exist. `PointerFinalError` once it was handed over or frozen |
| `pointerTransfer(owner, recipient)` | Hand a pointer over for good to the recipient's pointer, which must exist: readers of the address are redirected there and the old key can change nothing. Irreversible. Returns `PointerTransferResult` with the close group's `finality` (or `finalityError` when that check failed; the transfer stands either way) |
| `pointerGet(address)` | Read a pointer — returns `PointerRecord` (`counter`, `target`, `kind`/`kindTag`, `isFinal`, `transferredTo`, the owner's public key). `NotFoundError` if there is none |
| `pointerResolve(address)` | Follow a chain of pointers (forwardings and transfers) to the target at its end — returns `PointerTarget` |
| `pointerFinality(address)` | Ask the whole close group where a pointer stands — returns `PointerFinality`, whose `status` is a sealed `PointerFinalityStatus`: `PointerOpen`, `PointerSettling`, `PointerUnconfirmed`, `PointerFinal`, `PointerForked`, or `PointerFinalityUnknown` for a status a newer daemon adds. Check `isFinal` before relying on a transfer |
| `pointerController(address)` | Follow transfers to the pointer whose owner now decides — returns `PointerController` |
| `pointerPrepare(request)` | External signer: the daemon signs a `PointerPrepareRequest.create`, `.update` or `.transfer` with its key and quotes it — returns `PointerPrepareResult` (wave-batch `payments` for `payForQuotes()`; `signedQuotes` when the request sets `includeSignedQuotes`). Needs no daemon wallet. Other writes to the pointer throw `ConflictError` until it is finalized or expires (one hour) |
| `pointerFinalize(uploadId, txHashes)` | External signer: store the prepared write once paid — returns `PointerFinalizeResult`. A write that falls short after payment throws `CloseGroupShortfallError` with `retryable: true`: the daemon kept the paid state, so repeat the same call (bounded) to store it against the same payment |

```dart
final client = AntdClient();
final owner = (await client.pointerKeys()).first;
final data = await client.dataPutPublic(Uint8List.fromList(utf8.encode('v1')));

await client.pointerCreate(owner, data.address); // pays: never retry blindly
final record = await client.pointerGet(owner);
print('${record.target} at counter ${record.counter}');

final finality = await client.pointerFinality(owner);
switch (finality.status) {
  case PointerOpen():
    print('the owner can still move it');
  case PointerFinal():
    print('final, handed over to ${finality.transferredTo}');
  case PointerSettling() || PointerUnconfirmed() || PointerForked():
    print('not settled: ${finality.status}');
  case PointerFinalityUnknown(:final wire):
    print('a status from a newer daemon: $wire');
}
```

See [`example/09_pointers.dart`](example/09_pointers.dart) for a full round trip.

### Manifests

A manifest (ADR-0006) is a `.ant` file that names a set of files: each entry has an optional path and size and either an embedded DataMap (a private upload; the manifest is the key to it) or a public file's DataMap address. A small one also fits in an `ant://manifest/...` link. The daemon builds and decodes them, so you never handle the format yourself. **Nothing is uploaded or paid for:** a manifest describes data that is already stored. The methods need the antd release after 0.15.0, and both `AntdClient` and `GrpcAntdClient` have them.

| Method | Description |
|--------|-------------|
| `buildManifest(entries, {name, torrentInfoHashes, embedRoots})` | Build a manifest from `ManifestEntryInput`s — returns `BuiltManifest` (`manifest`, the raw `.ant` bytes; `link`, `null` when it would pass 1,500 bytes; `entries` in encoded order). `embedRoots` (default `true`) resolves each shrunk DataMap and embeds its root when that is at most 64 KiB, so readers skip the fetch; `false` embeds DataMaps exactly as given |
| `decodeManifest(bytes, {resolve})` | Decode `.ant` bytes — returns `DecodedManifest` (`source`, `name`, `torrentInfoHashV1` / `V2`, `entries`) |
| `decodeManifestLink(link, {resolve})` | Decode an `ant://manifest/` link, a file link or a bare 64-hex address (`source: "file_link"`: one public entry with no path) |

Each `ManifestEntryInput` sets exactly one of `dataMap` (hex, as the upload methods return it) or `address` (hex); an entry with both or neither throws `ArgumentError` before anything is sent. The daemon checks the rest, including the portable path rules, and reports every bad entry by index (`entries[i]: ...`) in a `BadRequestError` (gRPC `INVALID_ARGUMENT`).

Each `ManifestEntryInfo` has `effectiveName` (the path, or the content address when there is none), `path`, `size` (the creator's claim), `kind` (`"embedded"` or `"public"`), `contentAddress`, `dataMap` (decode only, `null` for public entries), `exactSize` and `error`. Sizes are `int?`: unset is `null`, never 0. With `resolve: true` the daemon fetches each entry's DataMap to report `exactSize` and confirm it is on the network (content chunks are not fetched); an entry that fails to resolve carries the reason in `error` instead of failing the call. Resolving and `embedRoots` read from the network, so those calls can time out, and retrying them is safe.

The `.ant` bytes are always raw `Uint8List`s in this API; REST carries them as base64 and gRPC as bytes, and the clients convert. grpc-dart has no message size limit, so manifests up to the format's 64 MiB need no channel settings.

```dart
final client = AntdClient();
final one = await client.dataPutPublic(Uint8List.fromList(utf8.encode('one')));
final two = await client.dataPutPublic(Uint8List.fromList(utf8.encode('two')));

final built = await client.buildManifest([
  ManifestEntryInput(path: 'notes/one.txt', address: one.address),
  ManifestEntryInput(path: 'notes/two.txt', address: two.address),
], name: 'notes'); // free: nothing is uploaded
print(built.link);

final decoded = await client.decodeManifestLink(built.link!, resolve: true);
for (final e in decoded.entries) {
  print('${e.effectiveName}: ${e.exactSize ?? e.error}');
}
```

See [`example/10_manifests.dart`](example/10_manifests.dart) for a full round trip.

## Error Handling

All errors extend `AntdError` which implements `Exception`:

```dart
try {
  final data = await client.dataGetPublic(address);
} on NotFoundError catch (e) {
  print('Data not found on network');
} on PaymentError catch (e) {
  print('Insufficient funds');
} on AntdError catch (e) {
  print('Error ${e.statusCode}: ${e.message}');
}
```

| Error Type | HTTP Status | When |
|-----------|-------------|------|
| `BadRequestError` | 400 | Invalid parameters |
| `PaymentError` | 402 | Insufficient funds |
| `NotFoundError` | 404 | Resource not found |
| `AlreadyExistsError` | 409 | Resource exists |
| `ForkError` | 409 | Version conflict; for pointers (`code: POINTER_FORKED` / gRPC `FAILED_PRECONDITION`) the owner signed two final states and no majority holds either |
| `PointerFinalError` | 409 (`code: POINTER_FINAL`) / gRPC `FAILED_PRECONDITION` | The pointer is transferred or frozen; nothing can change it |
| `ConflictError` | 409 (`code: CONFLICT`) / gRPC `ABORTED` | A pointer write while a prepared write to it awaits payment, or an update that lost to a newer state |
| `TooLargeError` | 413 | Payload too large |
| `InternalError` | 500 | Server error |
| `NetworkError` | 502 | Network unreachable |
| `PartialUploadError` | 502 (`code: PARTIAL_UPLOAD`) | Finalize stored some chunks, others stayed unstored — see below |
| `ServiceUnavailableError` | 503 | Wallet not configured |
| `CloseGroupShortfallError` | 503 (`code: CLOSE_GROUP_SHORTFALL`) / gRPC `UNAVAILABLE` | Too few of the close group answered or stored; `retryable` is `true` only for a pointer finalize that kept the paid state. A `ServiceUnavailableError` subclass |

The pointer codes share a status with older errors, so the SDK maps them by the daemon's code: over REST the error body's `code`, over gRPC the `x-antd-error-code` trailer, trusted only when it agrees with the status code (a `FAILED_PRECONDITION` without it is still a `PaymentError`, an `UNAVAILABLE` without it a `NetworkError`). Over gRPC, `CloseGroupShortfallError.retryable` comes from the message's closing `(paid attempt retained...)` hint. A daemon with the pointer API reports a close group that fell short on any call, a chunk store say, as `CLOSE_GROUP_SHORTFALL`; older daemons sent a 500, read as `InternalError`.

### Partial uploads

A `finalizeUpload` / `finalizeMerkleUpload` / `finalizeChunkUpload` call can fail *after* the wallet has paid: some chunks store, others miss quorum after the daemon's own retries. That is a `PartialUploadError` (a `NetworkError` subclass, so existing `on NetworkError` clauses still catch it) carrying `chunksStored`, `chunksFailed`, `totalChunks` and two flags, `retryable` and `retentionKnown`. The on-chain payment persists and the stored chunks stay on the network.

- **`retryable`** (antd ≥ 0.14.0) — the daemon kept the paid attempt under the same `upload_id`. Call the **same** finalize method again with the same `upload_id` and payment artefacts to store the remainder against the same payment: no re-prepare, no second signature, no double payment. Bound that loop — a persistent failure throws this error on every call, so cap the attempts and treat a `chunksFailed` that stops shrinking as stuck. The retained attempt expires with the daemon's pending-upload TTL.
- **`retentionKnown && !retryable`** — the daemon confirmed that nothing was retained (for example a merkle finalize with deliberately unpaid batches). Re-prepare the same content: already-stored chunks are skipped, so the retry pays only for the remainder.
- **`!retentionKnown`** — retention is unknown: the SDK could not read whether the daemon kept the attempt (a REST body without a boolean `retryable`, which includes every daemon before 0.14.0, or a gRPC message whose counts did not parse or whose closing retention hint is missing, truncated or unrecognised). The daemon may still hold the paid attempt, because it records the resume handle before it returns the error. Stop automatic recovery, keep the `upload_id` and the original payment artefacts, and reconcile before re-preparing or paying again. Never pay again on this signal alone.

```dart
try {
  await client.finalizeUpload(uploadId, txHashes);
} on PartialUploadError catch (e) {
  if (e.retryable) {
    // same upload_id, same payment — see finalizeWithRetry in example/finalize_with_retry.dart
  } else if (e.retentionKnown) {
    // nothing retained: re-prepare the same content; only the remainder is paid for
  } else {
    // retention unknown: stop, keep upload_id + payment artefacts, reconcile before paying again
  }
}
```

Over gRPC the error arrives as status `ABORTED` whose message starts with `Partial upload:`; the counts and flags are parsed from that message (`Partial upload: <stored>/<total> chunks stored, <failed> failed after retries: <reason> (<hint>)`). `retentionKnown` is `true` only when all three counts parse and the message ends with one of the daemon's two hints: `(paid attempt retained...)` sets `retryable`, and `(stored chunks persist; re-prepare the same content...)` means the daemon confirmed nothing was retained (daemons before 0.14.0 write only this one). Counts that do not parse read as zero with both flags `false`. Readable counts with a missing, truncated or unrecognised hint, or text after it, keep the counts, but both flags stay `false`. In both cases retention is unknown: stop and reconcile, do not re-prepare. Any other `ABORTED` is not a partial upload and surfaces as a plain `AntdError`. See `finalizeWithRetry` in [`example/finalize_with_retry.dart`](example/finalize_with_retry.dart) (used by `07_external_signer.dart`) for a bounded retry loop that stops at once when retention is unknown and rethrows the `PartialUploadError` unchanged whenever it gives up, and [`docs/external-signer-flow.md`](../docs/external-signer-flow.md) §6 for the daemon contract.

## Examples

See the [example/](example/) directory:

- `01_connect` — Health check
- `02_data` — Public data storage and retrieval
- `03_chunks` — Raw chunk operations
- `04_files` — File upload/download (public)
- `06_private_data` — Private encrypted data storage
- `07_external_signer` — File + chunk upload via external signer
- `09_pointers` — Create, update, read and resolve a pointer (`ANTD_POINTER_OWNER`; `ANTD_BASE_URL` for a non-default daemon)
- `10_manifests` — Build a manifest of two public uploads and decode its link (`ANTD_BASE_URL` for a non-default daemon)
