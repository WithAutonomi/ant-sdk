# antd-csharp — C# SDK for Autonomi

C# SDK for the antd daemon. Provides an async client with both REST and gRPC transports targeting .NET 8.

## Prerequisites

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- antd daemon running (see root [README](../README.md))

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
| `ForkException` | 409 | `ABORTED` | Version conflict |
| `TooLargeException` | 413 | `RESOURCE_EXHAUSTED` | Too large |
| `InternalException` | 500 | `INTERNAL` | Server error |
| `NetworkException` | 502 | `UNAVAILABLE` | Unreachable |

## Examples

```bash
cd Examples

dotnet run -- 1     # Connect
dotnet run -- 2     # Public data
dotnet run -- 3     # Chunks
dotnet run -- 4     # Files
dotnet run -- 6     # Private data
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
