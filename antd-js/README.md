# antd-js

JavaScript/TypeScript SDK for the [Autonomi](https://autonomi.com) decentralized network via the **antd** daemon.

## Installation

```bash
npm install @withautonomi/antd
```

Requires **Node.js 18+** (uses native `fetch`).

## Quick Start

```typescript
import { createClient } from "@withautonomi/antd";

const client = createClient(); // default: http://localhost:8082

// Check daemon health
const status = await client.health();
console.log(`Network: ${status.network}`);

// Store and retrieve data
const result = await client.dataPutPublic(Buffer.from("Hello, Autonomi!"));
console.log(`Address: ${result.address}`);

const data = await client.dataGetPublic(result.address);
console.log(data.toString()); // "Hello, Autonomi!"
```

## Client Options

```typescript
import { createClient, RestClient } from "@withautonomi/antd";

// Factory function
const client = createClient();
const client = createClient({ baseUrl: "http://remote:8082" });
const client = createClient({ timeout: 60_000 });

// Direct constructor
const client = new RestClient({ baseUrl: "http://localhost:8082", timeout: 300_000 });
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `baseUrl` | `string` | `"http://localhost:8082"` | antd daemon URL |
| `timeout` | `number` | `300000` | Request timeout (ms) |

## API Reference

All methods are `async` and return Promises.

### Health

| Method | Returns | Description |
|--------|---------|-------------|
| `health()` | `HealthStatus` | Check daemon health — also reports antd version, EVM network, uptime, build commit, and payment contract addresses (antd ≥ 0.4.0) |

### Data

| Method | Returns | Description |
|--------|---------|-------------|
| `dataPutPublic(data, { paymentMode? })` | `DataPutPublicResult` | Store public data — DataMap stored on-network |
| `dataGetPublic(address)` | `Buffer` | Retrieve public data by address |
| `dataPut(data, { paymentMode? })` | `DataPutResult` | Store private (encrypted) data — DataMap returned to caller |
| `dataGet(dataMap)` | `Buffer` | Retrieve private data using a caller-held DataMap |
| `dataCost(data, { paymentMode? })` | `UploadCostEstimate` | Estimate storage cost — size, chunks, gas, payment mode |

### Chunks

| Method | Returns | Description |
|--------|---------|-------------|
| `chunkPut(data)` | `PutResult` | Store raw chunk |
| `chunkGet(address)` | `Buffer` | Retrieve chunk by address |

### Files

| Method | Returns | Description |
|--------|---------|-------------|
| `filePut(path, { paymentMode? })` | `FilePutResult` | Upload a file privately — DataMap returned to caller |
| `fileGet(dataMap, destPath)` | `void` | Download a private file using a caller-held DataMap |
| `filePutPublic(path, { paymentMode? })` | `FilePutPublicResult` | Upload a file publicly — DataMap stored on-network |
| `fileGetPublic(address, destPath)` | `void` | Download a public file by address |
| `fileCost(path, isPublic?, { paymentMode? })` | `UploadCostEstimate` | Estimate upload cost — size, chunks, gas, payment mode |

### Manifests

A manifest ([ADR-0006](https://github.com/WithAutonomi/ant-client/blob/main/docs/adr/ADR-0006-file-manifests-and-links.md)) is a `.ant` file, or an `ant://manifest/` link, that describes a set of files: each entry has an optional path and size, and either an embedded DataMap (the manifest is then the key to that file) or a public file's DataMap address. The daemon builds and decodes manifests through ant-core, so the same inputs give the `ant` CLI's exact bytes. Needs antd 0.16.0 or later. See `examples/09-manifests.ts`.

**Nothing is uploaded or paid for**, and the daemon needs no wallet. Building (with `embedRoots`) and decoding with `resolve` read from the network, so they can time out; they are safe to retry.

| Method | Returns | Description |
|--------|---------|-------------|
| `buildManifest(entries, { name?, torrentInfoHashes?, embedRoots? })` | `BuiltManifest` | Build a manifest from DataMaps and public addresses you already hold. Each entry sets exactly one of `dataMap` (hex, embedded) or `address` (hex, public), plus an optional `path` and `size`. `embedRoots` (default `true`) resolves a shrunk DataMap and embeds its root when it is at most 64 KiB |
| `decodeManifest(manifest, resolve?)` | `DecodedManifest` | Decode `.ant` bytes. With `resolve` (default `false`) each entry's DataMap is fetched to report `exactSize`; content chunks are not fetched |
| `decodeManifestLink(link, resolve?)` | `DecodedManifest` | Decode an `ant://manifest/` link, an `ant://` file link or a bare 64-hex address (a file link reads as one public entry with no path, `source: "file_link"`) |

The `.ant` bytes are a `Buffer` both ways (`decodeManifest` also takes a plain `Uint8Array`); the base64 the REST API carries never reaches you. Sizes are `number`. Every unset value is `null`, never `0` or `""`: `size` when none was recorded, `exactSize` until it is known, `link` when it would exceed 1,500 bytes, `dataMap` on public entries and on every built entry. An entry with both sources or neither, or a size that is not a non-negative integer, throws `BadRequestError` before anything is sent; the daemon's own 400 for an invalid entry (a path such as `../x`, a malformed DataMap) is a `BadRequestError` whose message names each `entries[i]`. With `resolve`, one entry that cannot be resolved has its `error` set; the call still succeeds.

```typescript
import { createClient } from "@withautonomi/antd";

const client = createClient();
const one = await client.dataPutPublic(Buffer.from("first"));
const two = await client.dataPutPublic(Buffer.from("second"));

const built = await client.buildManifest(
  [
    { path: "notes/one.txt", address: one.address },
    { path: "notes/two.txt", address: two.address },
  ],
  { name: "example" },
);
console.log(built.link); // ant://manifest/...  (null if over 1,500 bytes)

const decoded = await client.decodeManifestLink(built.link!, true);
for (const e of decoded.entries) console.log(e.effectiveName, e.exactSize); // notes/one.txt 5 ...
```

```typescript
interface ManifestEntryInput { path?: string; size?: number | null; dataMap?: string; address?: string }
interface BuildManifestOptions { name?: string; torrentInfoHashes?: string[]; embedRoots?: boolean }
interface ManifestEntryInfo { effectiveName: string; path: string | null; size: number | null; kind: string /* "embedded" | "public" */; contentAddress: string; dataMap: string | null; exactSize: number | null; error: string | null }
interface BuiltManifest { manifest: Buffer; link: string | null; entries: ManifestEntryInfo[] /* sorted by effective name */ }
interface DecodedManifest { source: string /* "manifest" | "file_link" */; name: string | null; torrentInfoHashV1: string | null; torrentInfoHashV2: string | null; entries: ManifestEntryInfo[] }
```

### External Signer

Two-phase upload — daemon prepares the payment intent, caller signs + submits the payForQuotes tx, daemon finalizes once the chain confirms. See `examples/07-external-signer.ts`.

| Method | Returns | Description |
|--------|---------|-------------|
| `prepareUpload(path, { visibility? })` | `PrepareUploadResult` | Prepare a file upload for external signing |
| `prepareUploadPublic(path)` | `PrepareUploadResult` | Convenience for `prepareUpload(path, { visibility: "public" })` |
| `prepareDataUpload(data)` | `PrepareUploadResult` | Prepare a data upload for external signing |
| `prepareChunkUpload(data)` | `PrepareChunkResult` | Prepare a single chunk for external-signer publish |
| `finalizeUpload(uploadId, txHashes)` | `FinalizeUploadResult` | Submit a prepared upload after external payment. `data_map_address` populated when prepare used `visibility: "public"` |
| `finalizeChunkUpload(uploadId, txHashes)` | `string` | Submit a prepared chunk after external payment; returns the chunk address |

A finalize where some chunks stayed unstored after the daemon's retries throws `PartialUploadError` with `chunksStored` / `chunksFailed` / `totalChunks` and two flags, `retryable` and `retentionKnown` (`retryable` implies `retentionKnown`). The payment persists and stored chunks stay on the network. Three cases:

- `retryable` (antd ≥ 0.14.0): the daemon kept the paid attempt under the same `uploadId`. Call the **same** finalize method again with the same `uploadId` and payment artefacts to store the remainder against the same payment: no re-prepare, no second signature, no double payment. Bound that loop (cap the attempts; a `chunksFailed` that stops shrinking means stuck).
- `retentionKnown && !retryable`: the daemon confirmed nothing was retained (e.g. a merkle finalize with deliberately unpaid batches). Re-prepare the same content; stored chunks are skipped, so the new payment covers only the chunks still missing.
- `!retentionKnown`: retention is unknown, and the daemon may still hold the paid attempt. Stop automatic recovery, keep the `uploadId` and the original payment artefacts, and reconcile before re-preparing or paying again. Never pay again on this signal alone. Daemons older than 0.14.0 never send `retryable`, so their partials read as unknown.

See `finalizeWithRetry` in `examples/finalize-with-retry.ts` (used by `examples/07-external-signer.ts`) and [`docs/external-signer-flow.md` §6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment).

### Pointers

A pointer is a small, owner-signed, mutable reference (antd 0.16.0 or later, the first release with pointers). Its address is derived from its owner's key and never changes. What it points at (a chunk, such as a public file's data map, or another pointer) can be updated by the owner, and the owner can hand the pointer over to another pointer for good. The daemon signs with owner keys it loaded at startup (`antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`), so writes name the pointer by its address (`owner`) and no key ever crosses the API. See `examples/08-pointers.ts`.

**Every write pays, and every attempt pays again.** A create, update or transfer costs about the price of one chunk, paid by the daemon wallet. The client never retries a request, and you should not retry `pointerCreate`, `pointerUpdate`, `pointerTransfer` or `pointerFinalize` automatically either. Reads are free to retry: a `CloseGroupShortfallError` on a read usually clears once an update in flight settles.

| Method | Returns | Description |
|--------|---------|-------------|
| `pointerKeys()` | `string[]` | Addresses of the pointers this daemon can write |
| `pointerCreate(owner, target, kind?)` | `PointerWriteResult` | Create a pointer, paid by the daemon wallet. `kind` is `PointerKind.Chunk` (default) or `PointerKind.Pointer`. `AlreadyExistsError` if it exists, before paying |
| `pointerUpdate(owner, target, kind?)` | `PointerWriteResult` | Point a pointer at a new target, creating it if needed. `PointerFinalError` if it was handed over or frozen |
| `pointerTransfer(owner, recipient)` | `PointerTransferResult` | Hand a pointer over to the recipient's pointer (which must exist), irreversibly; carries the close group's `finality` |
| `pointerGet(address)` | `PointerRecord` | Read a pointer: `counter`, `target`, `kind` / `kindTag`, `isFinal`, `transferredTo`, the owner's public key. `NotFoundError` if none |
| `pointerResolve(address)` | `PointerTarget` | Follow a chain of pointers (at most 16 hops) to its target |
| `pointerFinality(address)` | `PointerFinality` | Ask the whole close group where a pointer stands. Only `status === "final"` means a transfer is beyond dispute |
| `pointerController(address)` | `PointerController` | Follow transfers to the pointer whose owner now decides |
| `pointerPrepare(owner, op, { includeSignedQuotes? })` | `PointerPrepareResult` | External signer: the daemon signs `{ op: "create" \| "update", target, kind? }` or `{ op: "transfer", recipient }` and quotes it (wave-batch `payments` for `payForQuotes()`). Needs no daemon wallet. Other writes to the pointer throw `ConflictError` until it is finalized or expires (one hour) |
| `pointerFinalize(uploadId, txHashes)` | `PointerFinalizeResult` | External signer: store the prepared write once paid. A `CloseGroupShortfallError` with `retryable` means the daemon kept the paid state: repeat the same call (bounded) to store it against the same payment |

Counters (`counter` on every result, `PointerFinality.counter`) are `bigint`, parsed from the daemon's decimal strings: a final state sits at `POINTER_FINAL_COUNTER` (2^64 − 1), past what a `number` holds exactly. A malformed counter throws `InternalError` rather than reading as 0. Unset optional values (`transferredTo`, `PointerFinality.counter` / `state` / `majority`, a transfer's `finality`) are `null`. `PointerFinality.status` is `"open"`, `"settling"`, `"unconfirmed"`, `"final"`, `"forked"`, or `"unknown"` for a status a newer daemon adds, with the daemon's string in `rawStatus`. The daemon accepts a `0x` prefix on addresses but always returns bare hex, so normalise before comparing.

```typescript
import { createClient } from "@withautonomi/antd";

const client = createClient();
const owner = (await client.pointerKeys())[0];
const v1 = await client.dataPutPublic(Buffer.from("version 1"));
const v2 = await client.dataPutPublic(Buffer.from("version 2"));

await client.pointerCreate(owner, v1.address); // counter 0n (pays)
await client.pointerUpdate(owner, v2.address); // counter 1n (pays again)
const { target } = await client.pointerResolve(owner); // v2.address
const finality = await client.pointerFinality(owner); // finality.status === "open"
```

## Models

```typescript
interface HealthStatus {
  ok: boolean;
  network: string;
  version: string;
  evmNetwork: string;
  uptimeSeconds: number;
  buildCommit: string;
  paymentTokenAddress: string;
  paymentVaultAddress: string;
}

// Result of chunkPut only
interface PutResult { cost: string; address: string }

// Data put results (DataMap shape)
interface DataPutResult { dataMap: string; chunksStored: number; paymentModeUsed: string }
interface DataPutPublicResult { address: string; chunksStored: number; paymentModeUsed: string }

// File put results
interface FilePutResult { dataMap: string; storageCostAtto: string; gasCostWei: string; chunksStored: number; paymentModeUsed: string }
interface FilePutPublicResult { address: string; storageCostAtto: string; gasCostWei: string; chunksStored: number; paymentModeUsed: string }

// Cost estimate
interface UploadCostEstimate { cost: string; fileSize: number; chunkCount: number; estimatedGasCostWei: string; paymentMode: string }

// Pointers (counters are bigint; unset values are null)
interface PointerWriteResult { address: string; stateId: string; counter: bigint }
interface PointerRecord { address: string; owner: string; counter: bigint; kind: string; kindTag: number; target: string; stateId: string; isFinal: boolean; transferredTo: string | null }
interface PointerTarget { kind: string; kindTag: number; target: string }
type PointerFinalityStatus = "open" | "settling" | "unconfirmed" | "final" | "forked" | "unknown";
interface PointerFinalState { stateId: string; kind: string; kindTag: number; target: string; holders: number; transferredTo: string | null }
interface PointerFinality { address: string; group: number; answered: number; status: PointerFinalityStatus; rawStatus: string; counter: bigint | null; state: PointerFinalState | null; states: PointerFinalState[]; majority: PointerFinalState | null; transferredTo: string | null }
interface PointerController { pointer: string; transfers: string[]; frozen: boolean }
interface PointerTransferResult { address: string; stateId: string; finality: PointerFinality | null; finalityError: string | null }
interface PointerPrepareResult { uploadId: string; op: string; address: string; stateId: string; counter: bigint; paymentType: string; payments: PaymentInfo[]; totalAmount: string; paymentVaultAddress: string; paymentTokenAddress: string; rpcUrl: string; signedQuotes: SignedQuoteEntry[] }
interface PointerFinalizeResult { address: string; stateId: string; counter: bigint; finality: PointerFinality | null }
```

## Errors

All errors extend `AntdError`, which extends `Error` and includes a `statusCode` property.

| Error Class | HTTP Status | Description |
|-------------|-------------|-------------|
| `AntdError` | any | Base error class |
| `BadRequestError` | 400 | Invalid request |
| `PaymentError` | 402 | Insufficient wallet funds |
| `NotFoundError` | 404 | Resource not found |
| `AlreadyExistsError` | 409 | Resource already exists |
| `ForkError` | 409 | Version conflict / fork; also a pointer whose owner signed two final states with no majority (`code: "POINTER_FORKED"`) |
| `PointerFinalError` | 409 (`code: "POINTER_FINAL"`) | The pointer was handed over or frozen; nothing can change it. Usually refused before paying, but a write already paid for when the network refused it keeps that payment |
| `ConflictError` | 409 (`code: "CONFLICT"`) | A pointer write while a prepared write to it awaits payment, or an update that lost to a newer state |
| `TooLargeError` | 413 | Data exceeds size limit |
| `InternalError` | 500 | Internal server error |
| `NetworkError` | 502 | Cannot reach network |
| `PartialUploadError` | 502 | Finalize stored only some chunks (`code: "PARTIAL_UPLOAD"`); carries `chunksStored`, `chunksFailed`, `totalChunks`, `retryable`, `retentionKnown`. Extends `NetworkError` |
| `ServiceUnavailableError` | 503 | Service unavailable, e.g. wallet not configured |
| `CloseGroupShortfallError` | 503 (`code: "CLOSE_GROUP_SHORTFALL"`) | Too few of the close group answered or stored. Reads are free to retry; `retryable` is `true` only for a pointer finalize that kept the paid state. Extends `AntdError`, not `ServiceUnavailableError` |

The pointer classes are mapped from the error body's `code`, so the 409s no longer read as `AlreadyExistsError` (create's `ALREADY_EXISTS` still does). A daemon with the pointer API also reports a close group that fell short on any call (a chunk store, say) as `CloseGroupShortfallError`, where an older daemon sent a 500 (`InternalError`).

```typescript
import { createClient, NotFoundError } from "@withautonomi/antd";

const client = createClient();
try {
  await client.dataGetPublic("nonexistent");
} catch (err) {
  if (err instanceof NotFoundError) {
    console.log("Data not found on network");
  }
}
```

`PartialUploadError` extends `NetworkError` (a 502 mapped to `NetworkError` before the daemon exposed the structured code), so check for it first:

```typescript
import { PartialUploadError } from "@withautonomi/antd";

try {
  await client.finalizeUpload(uploadId, txHashes);
} catch (err) {
  if (err instanceof PartialUploadError) {
    // Payment persists; stored chunks stay on the network.
    if (err.retryable) {
      // The daemon kept the paid attempt: repeat the SAME finalize call with
      // the same uploadId + txHashes (bounded; see the example).
    } else if (err.retentionKnown) {
      // The daemon confirmed nothing was retained: re-prepare the same
      // content; stored chunks are skipped, so the new payment covers only
      // the chunks still missing.
    } else {
      // Retention unknown (e.g. antd < 0.14.0): the daemon may still hold
      // the paid attempt. Stop, keep uploadId + txHashes, and reconcile
      // before re-preparing or paying again.
    }
  }
}
```

## Examples

The `examples/` directory contains 8 runnable scripts covering all major features, plus a retry helper:

| Example | Description |
|---------|-------------|
| `01-connect.ts` | Health check |
| `02-data.ts` | Public data store/retrieve |
| `03-chunks.ts` | Raw chunk operations |
| `04-files.ts` | File upload/download |
| `06-private-data.ts` | Private encrypted data |
| `07-external-signer.ts` | External-signer file + chunk upload (anvil signer) |
| `08-pointers.ts` | Pointer create, update, resolve and finality (needs `ANTD_POINTER_OWNER`) |
| `09-manifests.ts` | Build a manifest of two public uploads, then decode its link with exact sizes |
| `finalize-with-retry.ts` | Bounded same-`uploadId` finalize retry used by `07` (imported, not run directly) |

Run examples with [tsx](https://github.com/privatenumber/tsx):

```bash
npx tsx examples/01-connect.ts
ANTD_POINTER_OWNER=<hex> ANTD_BASE_URL=http://127.0.0.1:8082 npx tsx examples/08-pointers.ts
```

## License

See repository root for license information.
