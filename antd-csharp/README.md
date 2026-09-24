# antd-csharp — C# SDK for Autonomi

C# SDK for the antd daemon. Provides an async client with both REST and gRPC transports targeting .NET 8.

## Installation

```bash
dotnet add package Autonomi.Antd
```

## Compatibility

This package talks to a running [antd](https://github.com/WithAutonomi/ant-sdk/tree/main/antd) daemon; it does not join the network itself. Targets .NET 8. Tested against antd 0.12.x. The gRPC transport uses `Grpc.Net.Client`, which is a package dependency, so both transports work out of the box. For a daemon-less client see [`Autonomi.Ffi`](https://www.nuget.org/packages/Autonomi.Ffi).

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
| `PartialUploadException` | 502 (`code: "PARTIAL_UPLOAD"`) | `ABORTED` (detail carries `Partial upload:`) | Finalize stored some chunks, not all; extends `NetworkException` |

### Partial uploads

A finalize (`FinalizeUploadAsync`, `FinalizeMerkleUploadAsync`, `FinalizeChunkUploadAsync`) can fail *after* the wallet has paid: some chunks store, others miss quorum after the daemon's own retries. The SDK surfaces that as `PartialUploadException` with `ChunksStored`, `ChunksFailed`, `TotalChunks` and `Retryable`. The on-chain payment persists and the stored chunks stay on the network; `Retryable` says how to finish:

- **`Retryable == true`** — the daemon kept the paid attempt (payment proofs plus the unstored chunks) under the same `upload_id`. Call the **same finalize method again with the same arguments** to store the remainder against the same payment: no re-prepare, no second signature, no double payment. Bound the loop: a persistent failure throws on every call, so cap the attempts and treat a `ChunksFailed` that stops shrinking as stuck. The retained attempt expires with the daemon's pending-upload TTL. The flag is sent by antd ≥ 0.14.0; older daemons omit it and it reads `false`.
- **`Retryable == false`** — nothing was retained (older daemon, or a merkle finalize with deliberately unpaid batches). Re-preparing the same content skips already-stored chunks, so a retry pays only for the remainder.

`PartialUploadException` extends `NetworkException` because a partial upload has always arrived as a 502, so existing `catch (NetworkException)` blocks keep matching; catch the derived type first to branch on the counts. Over REST the fields come from the structured error body; over gRPC an `ABORTED` status maps to `PartialUploadException` only when its message carries the daemon's fixed `Partial upload:` prefix, with the counts and `Retryable` parsed from the rest of the message (a prefixed message whose counts fail to parse leaves them at zero and `Retryable` false). Any other `ABORTED` keeps the `ForkException` mapping.

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
        var stuck = attempt > 1 && ex.ChunksFailed >= lastFailed;
        if (attempt >= 5 || stuck)
            throw; // paid attempt still retained under uploadId: retry later or re-prepare
        lastFailed = ex.ChunksFailed;
        await Task.Delay(TimeSpan.FromSeconds(attempt * 2));
    }
    // a non-retryable PartialUploadException propagates: re-prepare the same content
}
```

See `Examples/Program.cs` (`FinalizeWithRetryAsync`) and [docs/external-signer-flow.md §6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment).

## Examples

```bash
cd Examples

dotnet run -- 1     # Connect
dotnet run -- 2     # Public data
dotnet run -- 3     # Chunks
dotnet run -- 4     # Files
dotnet run -- 6     # Private data
dotnet run -- 7     # External signer (bounded partial-upload retry)
dotnet run -- all   # Run all
```

Or use the dev CLI:

```bash
ant dev example data -l csharp
ant dev example all -l csharp
```

## Project Structure

```
antd-csharp/
├── Antd.sln                   # Solution file
├── Antd.Sdk/                  # SDK library
│   ├── Antd.Sdk.csproj
│   ├── IAntdClient.cs         # Client interface
│   ├── AntdClientFactory.cs   # Factory methods
│   ├── AntdRestClient.cs      # REST implementation
│   ├── AntdGrpcClient.cs      # gRPC implementation
│   ├── Models.cs              # Data models
│   └── Exceptions.cs          # Exception hierarchy
├── Examples/                  # Example programs
│   ├── Examples.csproj
│   └── Program.cs
└── Antd.Sdk.Tests/            # Tests
    ├── Antd.Sdk.Tests.csproj
    └── Program.cs
```
