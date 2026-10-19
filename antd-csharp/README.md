# antd-csharp — C# SDK for Autonomi

C# SDK for the antd daemon. Provides an async client with both REST and gRPC transports targeting .NET 8.

## Installation

```bash
dotnet add package Autonomi.Antd
```

## Compatibility

This package talks to a running [antd](https://github.com/WithAutonomi/ant-sdk/tree/main/antd) daemon; it does not join the network itself. Targets .NET 8. Tested against antd 0.12.x; the pointer methods need the antd release after 0.15.0, the first with pointers. The gRPC transport uses `Grpc.Net.Client`, which is a package dependency, so both transports work out of the box. For a daemon-less client see [`Autonomi.Ffi`](https://www.nuget.org/packages/Autonomi.Ffi).

## Prerequisites

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- antd daemon running (see root [README](https://github.com/WithAutonomi/ant-sdk#readme))

## Building

```bash
cd antd-csharp

# Build all projects (SDK, examples, tests)
dotnet build Antd.sln

# Or build individual projects
dotnet build Antd.Sdk/Antd.Sdk.csproj
```

## Quick Start

```csharp
using System.Text;
using Antd.Sdk;

using var client = AntdClient.CreateRest();

// Health check
var status = await client.HealthAsync();
Console.WriteLine($"{status.Network} — healthy: {status.Ok}");

// Store and retrieve data
var result = await client.DataPutPublicAsync(
    Encoding.UTF8.GetBytes("Hello, Autonomi!")
);
Console.WriteLine($"Address: {result.Address}, chunks: {result.ChunksStored}");

var data = await client.DataGetPublicAsync(result.Address);
Console.WriteLine(Encoding.UTF8.GetString(data));
```

## Client Creation

```csharp
using Antd.Sdk;

// REST transport (default)
using var client = AntdClient.CreateRest(
    baseUrl: "http://localhost:8082",
    timeout: TimeSpan.FromSeconds(30)
);

// gRPC transport (wallet operations and payment_mode are REST-only)
using var grpcClient = AntdClient.CreateGrpc(
    target: "http://localhost:50051"
);

// Factory method (transport string)
using var auto = AntdClient.Create(transport: "rest");
```

## API Reference

All methods are async and return `Task<T>`. The client implements `IDisposable`.

### Health

| Method | Returns | Description |
|--------|---------|-------------|
| `HealthAsync()` | `HealthStatus` | Check daemon health — also reports antd version, EVM network, uptime, build commit, and payment contract addresses (antd ≥ 0.4.0) |

### Data

| Method | Returns | Description |
|--------|---------|-------------|
| `DataPutPublicAsync(byte[] data, PaymentMode mode = Auto)` | `DataPutPublicResult` | Store public data — DataMap stored on-network |
| `DataGetPublicAsync(string address)` | `byte[]` | Retrieve public data by address |
| `DataPutAsync(byte[] data, PaymentMode mode = Auto)` | `DataPutResult` | Store private (encrypted) data — DataMap returned to caller |
| `DataGetAsync(string dataMap)` | `byte[]` | Retrieve private data using a caller-held DataMap |
| `DataCostAsync(byte[] data, PaymentMode mode = Auto)` | `UploadCostEstimate` | Estimate storage cost — size, chunks, gas, payment mode |

### Chunks

| Method | Returns | Description |
|--------|---------|-------------|
| `ChunkPutAsync(byte[] data)` | `PutResult` | Store a raw chunk |
| `ChunkGetAsync(string address)` | `byte[]` | Retrieve a chunk |

### Files

| Method | Returns | Description |
|--------|---------|-------------|
| `FilePutAsync(string path, PaymentMode mode = Auto)` | `FilePutResult` | Upload a file privately — DataMap returned to caller |
| `FileGetAsync(string dataMap, string destPath)` | — | Download a private file using a caller-held DataMap |
| `FilePutPublicAsync(string path, PaymentMode mode = Auto)` | `FilePutPublicResult` | Upload a file publicly — DataMap stored on-network |
| `FileGetPublicAsync(string address, string destPath)` | — | Download a public file by address |
| `FileCostAsync(string path, bool isPublic, PaymentMode mode = Auto)` | `UploadCostEstimate` | Estimate cost — size, chunks, gas, payment mode |

### Pointers

A pointer is a small, owner-signed, mutable reference. Its address is derived from the owner's key and never changes; what it points at (a chunk, such as a public file's data map, or another pointer) can be changed by the owner. The daemon holds the owner keys, loaded at startup with `antd --pointer-keys <file-or-dir>` (files in the format `ant pointer keygen` writes), so every write names the pointer by its address (`owner`), never by a key. The daemon accepts addresses with or without `0x` and always returns bare hex.

**Every write pays** (about the price of one chunk), and every attempt pays again. The SDK sends each create, update, transfer and finalize exactly once and never retries it; do not retry them automatically yourself. Reads are free to retry; a read during an update or churn can fail with `CloseGroupShortfallException`. Counters are `ulong`, parsed strictly from the daemon's decimal strings (a malformed one throws, it never reads as zero); a final state (a transfer) sits at `ulong.MaxValue`.

Both clients implement every method below, over REST and gRPC alike.

| Method | Returns | Description |
|--------|---------|-------------|
| `PointerKeysAsync()` | `List<string>` | The pointers this daemon holds owner keys for, so can write |
| `PointerCreateAsync(string owner, string target, PointerKind kind = Chunk)` | `PointerWriteResult` | Create a pointer, paid by the daemon wallet (`Address`, `StateId`, `Counter`). Refused before paying if it exists: `AlreadyExistsException` over gRPC, `ForkException` (the REST 409 mapping) over REST |
| `PointerUpdateAsync(string owner, string target, PointerKind kind = Chunk)` | `PointerWriteResult` | Point a pointer at a new target, paid by the daemon wallet; creates it if it does not exist. `PointerKind.Pointer` makes it a forwarding the owner can still change. `PointerFinalException` once transferred |
| `PointerTransferAsync(string owner, string recipient)` | `PointerTransferResult` | Hand a pointer over for good to the recipient's pointer, which must exist: readers of the address are redirected there and the old key can change nothing. Irreversible. Carries the close group's `Finality` (or `FinalityError` when that check failed) |
| `PointerGetAsync(string address)` | `PointerRecord` | Read a pointer: `Counter`, `Target`, `Kind`/`KindTag`, `IsFinal`, `TransferredTo`, the owner's public key. `NotFoundException` if there is none |
| `PointerResolveAsync(string address)` | `PointerTarget` | Follow a chain of pointers (forwardings and transfers, at most 16 hops) to the target at its end |
| `PointerFinalityAsync(string address)` | `PointerFinality` | Ask the whole close group where a pointer stands: `Status` is `Open`, `Settling`, `Unconfirmed`, `Final`, `Forked`, or `Unknown` for a status from a newer daemon (`RawStatus` keeps the wire value). Check `IsFinal` before relying on a transfer |
| `PointerControllerAsync(string address)` | `PointerController` | Follow transfers to the pointer whose owner now decides |
| `PointerPrepareAsync(PointerPrepareRequest request)` | `PointerPrepareResult` | External signer: the daemon signs `PointerPrepareRequest.Create(...)`, `.Update(...)` or `.Transfer(...)` with its key and quotes it (wave-batch `Payments` for `payForQuotes()`). Needs no daemon wallet. Set `IncludeSignedQuotes` on the request to also get the full signed quotes. Other writes to the pointer throw `ConflictException` until it is finalized or expires |
| `PointerFinalizeAsync(string uploadId, IDictionary<string, string> txHashes)` | `PointerFinalizeResult` | External signer: store the prepared write once paid. A write that falls short after payment throws `CloseGroupShortfallException` with `Retryable == true`: repeat the same call (same `uploadId`) to store it against the same payment, bounding the loop |

```csharp
using var client = AntdClient.CreateRest();
var owner = (await client.PointerKeysAsync())[0];

var v1 = await client.DataPutPublicAsync(Encoding.UTF8.GetBytes("version 1"));
await client.PointerCreateAsync(owner, v1.Address);        // pays once

var v2 = await client.DataPutPublicAsync(Encoding.UTF8.GetBytes("version 2"));
await client.PointerUpdateAsync(owner, v2.Address);        // pays once

var target = await client.PointerResolveAsync(owner);      // -> v2.Address
var finality = await client.PointerFinalityAsync(owner);   // Open: the owner can still move it
```

The members were added to `IAntdClient` with default implementations that throw `NotSupportedException`, so a class implementing the interface outside this package keeps compiling.

## Models

All models are sealed records (immutable).

| Model | Fields | Description |
|-------|--------|-------------|
| `HealthStatus` | `Ok`, `Network`, `Version`, `EvmNetwork`, `UptimeSeconds`, `BuildCommit`, `PaymentTokenAddress`, `PaymentVaultAddress` | Health check result (diagnostic fields require antd ≥ 0.4.0) |
| `PutResult` | `Cost`, `Address` | Result of `ChunkPutAsync` only |
| `DataPutResult` | `DataMap`, `ChunksStored`, `PaymentModeUsed` | Private data put — DataMap returned to caller |
| `DataPutPublicResult` | `Address`, `ChunksStored`, `PaymentModeUsed` | Public data put — DataMap stored on-network |
| `FilePutResult` | `DataMap`, `StorageCostAtto`, `GasCostWei`, `ChunksStored`, `PaymentModeUsed` | Private file put — DataMap returned to caller |
| `FilePutPublicResult` | `Address`, `StorageCostAtto`, `GasCostWei`, `ChunksStored`, `PaymentModeUsed` | Public file put — DataMap stored on-network |
| `UploadCostEstimate` | `Cost`, `FileSize`, `ChunkCount`, `EstimatedGasCostWei`, `PaymentMode` | Pre-upload cost breakdown |
| `PointerWriteResult` | `Address`, `StateId`, `Counter` | The state a create or update stored |
| `PointerRecord` | `Address`, `Owner`, `Counter`, `Kind`, `KindTag`, `Target`, `StateId`, `IsFinal`, `TransferredTo`, `TargetKind` | A pointer's current state; `TransferredTo` is `null` unless its final state is a transfer |
| `PointerTarget` | `Kind`, `KindTag`, `Target`, `TargetKind` | Where a chain of pointers ends |
| `PointerFinality` | `Address`, `Group`, `Answered`, `Status`, `RawStatus`, `Counter`, `State`, `States`, `Majority`, `TransferredTo`, `IsFinal` | The close group's view; unset values are `null` over both transports |
| `PointerFinalState` | `StateId`, `Kind`, `KindTag`, `Target`, `Holders`, `TransferredTo` | One final state a finality check saw |
| `PointerTransferResult` | `Address`, `StateId`, `Finality`, `FinalityError` | What a transfer stored |
| `PointerController` | `Pointer`, `Transfers`, `Frozen` | Whose pointer decides, after every transfer |
| `PointerPrepareRequest` | `Owner`, `Op`, `Target`, `Kind`, `Recipient`, `IncludeSignedQuotes` | An external-signer write; build it with `Create`, `Update` or `Transfer`; to ask for signed quotes, add `with { IncludeSignedQuotes = true }` |
| `PointerPrepareResult` | `UploadId`, `Op`, `Address`, `StateId`, `Counter`, `PaymentType`, `Payments`, `TotalAmount`, `PaymentVaultAddress`, `PaymentTokenAddress`, `RpcUrl`, `SignedQuotes` | A signed, quoted pointer write awaiting payment. `SignedQuotes` (`List<SignedQuoteEntry>`: `QuoteHash`, base64 `Quote`, optional base64 `CommitmentSidecar`) is empty unless the request set `IncludeSignedQuotes` |
| `PointerFinalizeResult` | `Address`, `StateId`, `Counter`, `Finality` | The state a finalize stored; `Finality` for transfers only |

## Error Handling

All errors inherit from `AntdException`:

```csharp
using Antd.Sdk;

try
{
    var data = await client.DataGetPublicAsync("nonexistent");
}
catch (NotFoundException)
{
    Console.WriteLine("Data not found");
}
catch (PaymentException)
{
    Console.WriteLine("Insufficient funds");
}
catch (AntdException ex)
{
    Console.WriteLine($"Error ({ex.StatusCode}): {ex.Message}");
}
```

| Exception | HTTP | gRPC | Description |
|-----------|------|------|-------------|
| `BadRequestException` | 400 | `INVALID_ARGUMENT` | Invalid parameters |
| `PaymentException` | 402 | `FAILED_PRECONDITION` | Payment issue |
| `NotFoundException` | 404 | `NOT_FOUND` | Not found |
| `AlreadyExistsException` | 409 | `ALREADY_EXISTS` | Already exists |
| `ForkException` | 409 | `ABORTED` (non-partial-upload) | Version conflict |
| `TooLargeException` | 413 | `RESOURCE_EXHAUSTED` | Too large |
| `InternalException` | 500 | `INTERNAL` | Server error |
| `NetworkException` | 502 | `UNAVAILABLE` | Unreachable |
| `PartialUploadException` | 502 (`code: "PARTIAL_UPLOAD"`) | `ABORTED` (detail starts with `Partial upload:`) | Finalize stored some chunks, not all; extends `NetworkException` |
| `PointerFinalException` | 409 (`code: "POINTER_FINAL"`) | `FAILED_PRECONDITION` + `x-antd-error-code: POINTER_FINAL` | The pointer is transferred or frozen; nothing can change it. Extends `ForkException` |
| `PointerForkedException` | 409 (`code: "POINTER_FORKED"`) | `FAILED_PRECONDITION` + `x-antd-error-code: POINTER_FORKED` | The owner signed two final states and no majority holds either. Extends `ForkException` |
| `ConflictException` | 409 (`code: "CONFLICT"`) | `ABORTED` + `x-antd-error-code: CONFLICT` | A pointer write while a prepared write to it awaits payment, or an update that lost to a newer state. Extends `ForkException` |
| `CloseGroupShortfallException` | 503 (`code: "CLOSE_GROUP_SHORTFALL"`) | `UNAVAILABLE` + `x-antd-error-code: CLOSE_GROUP_SHORTFALL` | Too few of the close group answered or stored; `Retryable` is `true` only for a pointer finalize that kept the paid state |

Over gRPC the four pointer-era errors share status codes with older ones, so the daemon tags them with `x-antd-error-code` trailing metadata; the SDK maps the tag only when it agrees with the status code shown, and otherwise keeps the code-based mapping (a `FAILED_PRECONDITION` without a tag is still a `PaymentException`). Over REST they are read from the error body's `code`.

### Upgrading: pointer-era errors

These are new subclasses in the existing hierarchy, so no `catch` stops compiling, but some errors now arrive as a more specific type:

- **REST 409s** with `POINTER_FINAL`, `POINTER_FORKED` or `CONFLICT` were `ForkException`; they are now the subclasses above, so `catch (ForkException)` still matches. A 409 `ALREADY_EXISTS` stays a plain `ForkException`.
- **`CLOSE_GROUP_SHORTFALL`** is not only for pointers: a daemon with the pointer API reports a close group that fell short on any call (a chunk store, say) as a 503 / `UNAVAILABLE`, which an older daemon sent as a 500. It is now `CloseGroupShortfallException`, which extends `AntdException` directly, so it no longer matches `catch (ServiceUnavailableException)` over REST or `catch (NetworkException)` over gRPC.
- **gRPC `FAILED_PRECONDITION`** tagged `POINTER_FINAL` / `POINTER_FORKED` is no longer a `PaymentException`, and a tagged `ABORTED` `CONFLICT` is a `ConflictException` (still a `ForkException`).

### Partial uploads

A finalize (`FinalizeUploadAsync`, `FinalizeMerkleUploadAsync`, `FinalizeChunkUploadAsync`) can fail *after* the wallet has paid: some chunks store, others miss quorum after the daemon's own retries. The SDK surfaces that as `PartialUploadException` with `ChunksStored`, `ChunksFailed`, `TotalChunks`, `Retryable` and `RetentionKnown`. The on-chain payment persists and the stored chunks stay on the network; the two flags say how to finish:

- **`Retryable`**: the daemon kept the paid attempt (payment proofs plus the unstored chunks) under the same `upload_id`. Call the **same finalize method again with the same arguments** (same `upload_id`, same payment artefacts) to store the remainder against the same payment: no re-prepare, no second signature, no double payment. Bound the loop: a persistent failure throws on every call, so cap the attempts and treat a `ChunksFailed` that stops shrinking as stuck. The retained attempt expires with the daemon's pending-upload TTL.
- **`RetentionKnown && !Retryable`**: the daemon confirmed it kept nothing (for example a merkle finalize that deliberately left sub-batches unpaid). Re-prepare the same content; already-stored chunks are skipped, so the retry pays only for the remainder.
- **`!RetentionKnown`**: retention is unknown, because a daemon before antd 0.14.0 answered over REST (it never sends `retryable`) or the SDK could not fully read the error. The daemon may still hold the paid attempt, since it records the resume handle before it returns the error. Stop automatic recovery, keep the `upload_id` and the original payment artefacts, and reconcile before re-preparing or paying again. Never pay again on this signal alone.

`Retryable` implies `RetentionKnown`. `PartialUploadException` extends `NetworkException` because a partial upload has always arrived as a 502, so existing `catch (NetworkException)` blocks keep matching; catch the derived type first to branch on the counts. Over REST the counts come from the structured error body, and `RetentionKnown` is `true` only when `retryable` is a JSON boolean (missing, `null`, `"true"` or `1` read as unknown). Over gRPC an `ABORTED` status maps to `PartialUploadException` only when its status detail starts with the daemon's fixed `Partial upload:` prefix; any other `ABORTED`, including one that quotes `Partial upload:` further into its detail, keeps the `ForkException` mapping. The detail reads `Partial upload: <stored>/<total> chunks stored, <failed> failed after retries: <reason> (<hint>)`. `RetentionKnown` is `true` only when the detail starts with those counts, all three parse, and it ends with one of the daemon's two hints: `(paid attempt retained...)` sets `Retryable`, and `(stored chunks persist; re-prepare the same content...)` means the daemon confirmed it kept nothing (daemons before antd 0.14.0 write only this one). If the counts do not match the daemon's layout or do not convert (an overflow, non-ASCII digits), all three read as zero and both flags are `false`, even with a hint. Readable counts with a missing, truncated or unrecognised hint, or text after it, keep the counts, but both flags stay `false`: retention is unknown (stop and reconcile), not "nothing retained".

**Behaviour change over gRPC:** a partial-upload `ABORTED` used to surface as `ForkException`; it is now `PartialUploadException`. Apart from a tagged pointer `CONFLICT`, the daemon emits `ABORTED` only for `PARTIAL_UPLOAD`, so a `catch (ForkException)` around a gRPC finalize should become `catch (PartialUploadException)`.

```csharp
var lastFailed = 0UL;
for (var attempt = 1; ; attempt++)
{
    try
    {
        return await client.FinalizeUploadAsync(uploadId, txHashes); // every chunk stored
    }
    catch (PartialUploadException ex) when (ex.Retryable)
    {
        var stalled = attempt > 1 && ex.ChunksFailed >= lastFailed;
        if (attempt >= 5 || stalled)
            throw; // still retained under uploadId until the daemon's TTL: finalize again later
        lastFailed = ex.ChunksFailed;
        await Task.Delay(TimeSpan.FromSeconds(attempt * 2), cancellationToken);
    }
    // RetentionKnown && !Retryable propagates: the daemon kept nothing, so re-prepare the same content.
    // !RetentionKnown propagates: retention unknown, so keep uploadId + txHashes and reconcile before paying again.
}
```

See `Examples/FinalizeRetry.cs` (`FinalizeWithRetryAsync`, used by example 7) and [docs/external-signer-flow.md §6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment).

## Manifests

A manifest (ADR-0006) is a `.ant` file, or an `ant://manifest/` link when it is small enough, that describes a set of files. Each entry has an optional path and size, and either an embedded DataMap (the manifest is then the key to a private file) or a public file's DataMap address. The daemon builds and decodes manifests with ant-core, so the format, content addresses, link encoding and portable path rules are never re-implemented here. The manifest methods need the antd release after 0.15.0.

**Nothing is uploaded or paid for.** Building and decoding are free. The daemon reads the network only to resolve DataMaps (the root-embedding policy on build, and `resolve` on decode), so a call can time out; it is safe to retry.

Both clients implement every method below, over REST and gRPC alike. The `.ant` bytes are always a raw `byte[]`: REST carries them as base64 in the JSON and gRPC as protobuf bytes, and the SDK converts. Sizes are `ulong?`, and an unset size is `null`, never `0`.

| Method | Returns | Description |
|--------|---------|-------------|
| `BuildManifestAsync(IReadOnlyList<ManifestEntryInput> entries, BuildManifestOptions? options = null)` | `BuiltManifest` | Build a manifest from DataMaps and public addresses already in hand. Each entry sets exactly one of `DataMap` or `Address` (`ManifestEntryInput.Embedded(...)` or `.Public(...)`); both or neither throws `BadRequestException` (status 400, the daemon's own wording) before anything is sent. The options are `Name`, `TorrentInfoHashes` and `EmbedRoots` |
| `DecodeManifestAsync(byte[] manifest, bool resolve = false)` | `DecodedManifest` | Decode `.ant` bytes. With `resolve`, the daemon fetches each entry's DataMap (not its content) to report `ExactSize` and confirm it is on the network; one entry's failure is in its `Error`, not thrown |
| `DecodeManifestLinkAsync(string link, bool resolve = false)` | `DecodedManifest` | Decode an `ant://` manifest link, a file link or a bare 64-hex address. A file link or address reads as one public entry with no path, and `Source` is `"file_link"` |

| Model | Fields | Description |
|-------|--------|-------------|
| `ManifestEntryInput` | `Path`, `Size`, `DataMap`, `Address` | One file to build from. `Size` is recorded as given (the creator's claim); `null` records none |
| `BuildManifestOptions` | `Name`, `TorrentInfoHashes`, `EmbedRoots` | `EmbedRoots` defaults to `true`: the daemon resolves each shrunk DataMap and embeds its root when it is at most 64 KiB, so recipients skip that fetch. `false` embeds DataMaps exactly as given. `null` options mean all defaults |
| `BuiltManifest` | `Manifest`, `Link`, `Entries` | `Link` is `null` when the link would pass the recommended 1,500 bytes; share `Manifest` instead. Entries are sorted by effective name |
| `DecodedManifest` | `Source`, `Name`, `TorrentInfoHashV1`, `TorrentInfoHashV2`, `Entries` | `Source` is `"manifest"` or `"file_link"`; absent values are `null` |
| `ManifestEntryInfo` | `EffectiveName`, `Path`, `Size`, `Kind`, `ContentAddress`, `DataMap`, `ExactSize`, `Error` | `Kind` is `"embedded"` or `"public"`. `ExactSize` comes from an embedded root DataMap or a resolving decode. `DataMap` is set by a decode, for embedded entries only |

```csharp
using var client = AntdClient.CreateRest();
var one = await client.DataPutPublicAsync(Encoding.UTF8.GetBytes("note one"));   // pays
var two = await client.DataPutPublicAsync(Encoding.UTF8.GetBytes("note two"));   // pays

var built = await client.BuildManifestAsync(new[]                                 // free
{
    ManifestEntryInput.Public(one.Address, "notes/one.txt"),
    ManifestEntryInput.Public(two.Address, "notes/two.txt"),
}, new BuildManifestOptions(Name: "example"));
Console.WriteLine(built.Link);                       // ant://manifest/... (null when too long)
await File.WriteAllBytesAsync("example.ant", built.Manifest);

var decoded = await client.DecodeManifestLinkAsync(built.Link!, resolve: true);  // free
foreach (var e in decoded.Entries)
    Console.WriteLine($"{e.EffectiveName}: {e.ExactSize} bytes");
```

A client-side refusal is indistinguishable from the daemon's: an entry with both or neither source, or an empty manifest or link, throws the same `BadRequestException` (status 400) with the daemon's text (`2 invalid entries: entries[0]: give data_map or address, not both; entries[2]: needs a data_map or an address`, at most 20 entries spelled out; `needs a manifest (base64 .ant bytes) or a link`). The daemon refuses a bad entry (a path that breaks the portable rules, such as `../x`, or a malformed DataMap or address) or a bad torrent hash with HTTP 400 / gRPC `INVALID_ARGUMENT`. That surfaces as `BadRequestException`, whose message names each bad entry as `entries[i]`. Bytes or a link that are not a manifest are a `BadRequestException` too. There are no new exception types.

Over gRPC, a manifest response can pass Grpc.Net.Client's default 4 MiB receive limit, since a manifest can be 64 MiB. Grpc.Net.Client sets message limits per channel, not per call, so `AntdGrpcClient` sends manifest calls over a second channel to the same target with both limits raised to 256 MiB; the other services keep the defaults. That channel connects on the first manifest call.

The members were added to `IAntdClient` with default implementations that throw `NotSupportedException`, so a class implementing the interface outside this package keeps compiling.

## Examples

```bash
cd Examples

dotnet run -- 1     # Connect
dotnet run -- 2     # Public data
dotnet run -- 3     # Chunks
dotnet run -- 4     # Files
dotnet run -- 6     # Private data
dotnet run -- 7     # External signer (bounded partial-upload retry)
dotnet run -- all   # Run all of the above

# Pointers: run explicitly; "all" leaves it out, because every write pays.
ANTD_POINTER_OWNER=<address from GET /v1/pointers/keys> dotnet run -- 8   # or: dotnet run -- pointers
dotnet run -- 9     # Manifests (or: dotnet run -- manifests; needs the antd release after 0.15.0)
```

Example 8 uploads two pieces of public data, creates a pointer at the first, updates it to the second, resolves and reads it, and prints its finality. It needs an antd started with `--pointer-keys` and a wallet; `ANTD_BASE_URL` overrides the daemon URL (default `http://localhost:8082`). Without `ANTD_POINTER_OWNER` it prints a note and skips. A rerun with the same owner skips the create and only updates.

Or use the dev CLI:

```bash
ant dev example data -l csharp
ant dev example all -l csharp
```

Example 9 (`dotnet run -- 9`, or `dotnet run -- manifests`) uploads two pieces of public data, builds a manifest of them with paths `notes/one.txt` and `notes/two.txt`, prints its link and entries, and decodes the link with `resolve` to print each entry's exact size. Only the two uploads pay. It is left out of "all" because it needs the antd release after 0.15.0; `ANTD_BASE_URL` overrides the daemon URL (default `http://localhost:8082`).

## Project Structure

```
antd-csharp/
├── Antd.sln                   # Solution file
├── Antd.Sdk/                  # SDK library
│   ├── Antd.Sdk.csproj
│   ├── IAntdClient.cs         # Client interface
│   ├── IAntdClient.Manifests.cs
│   ├── AntdRestClient.Manifests.cs
│   ├── AntdGrpcClient.Manifests.cs
│   ├── ManifestModels.cs      # Manifest models
│   ├── AntdClientFactory.cs   # Factory methods
│   ├── AntdRestClient.cs      # REST implementation
│   ├── AntdRestClient.Pointers.cs
│   ├── AntdGrpcClient.cs      # gRPC implementation
│   ├── AntdGrpcClient.Pointers.cs
│   ├── Models.cs              # Data models
│   ├── PointerModels.cs       # Pointer models
│   └── Exceptions.cs          # Exception hierarchy
├── Examples/                  # Example programs
│   ├── Examples.csproj
│   ├── Example09Manifests.cs
│   └── Program.cs
└── Antd.Sdk.Tests/            # Tests
    ├── Antd.Sdk.Tests.csproj
    └── Program.cs
```
