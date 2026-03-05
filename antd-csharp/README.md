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
Console.WriteLine($"Address: {result.Address}, Cost: {result.Cost}");

var data = await client.DataGetPublicAsync(result.Address);
Console.WriteLine(Encoding.UTF8.GetString(data));
```

## Client Creation

```csharp
using Antd.Sdk;

// REST transport (default)
using var client = AntdClient.CreateRest(
    baseUrl: "http://localhost:8080",
    timeout: TimeSpan.FromSeconds(30)
);

// gRPC transport
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
| `HealthAsync()` | `HealthStatus` | Check daemon health |

### Data

| Method | Returns | Description |
|--------|---------|-------------|
| `DataPutPublicAsync(byte[] data)` | `PutResult` | Store public data |
| `DataGetPublicAsync(string address)` | `byte[]` | Retrieve public data |
| `DataPutPrivateAsync(byte[] data)` | `PutResult` | Store private data |
| `DataGetPrivateAsync(string dataMap)` | `byte[]` | Retrieve private data |
| `DataCostAsync(byte[] data)` | `string` | Estimate storage cost |

### Chunks

| Method | Returns | Description |
|--------|---------|-------------|
| `ChunkPutAsync(byte[] data)` | `PutResult` | Store a raw chunk |
| `ChunkGetAsync(string address)` | `byte[]` | Retrieve a chunk |

### Pointers

| Method | Returns | Description |
|--------|---------|-------------|
| `PointerCreateAsync(string key, PointerTarget target)` | `PutResult` | Create a pointer |
| `PointerGetAsync(string address)` | `Pointer` | Read a pointer |
| `PointerExistsAsync(string address)` | `bool` | Check existence |
| `PointerUpdateAsync(string key, PointerTarget target)` | — | Update target |
| `PointerCostAsync(string publicKey)` | `string` | Estimate cost |

### Scratchpads

| Method | Returns | Description |
|--------|---------|-------------|
| `ScratchpadCreateAsync(string key, ulong contentType, byte[] data)` | `PutResult` | Create |
| `ScratchpadGetAsync(string address)` | `ScratchpadRecord` | Read |
| `ScratchpadExistsAsync(string address)` | `bool` | Check existence |
| `ScratchpadUpdateAsync(string key, ulong contentType, byte[] data)` | — | Update |
| `ScratchpadCostAsync(string publicKey)` | `string` | Estimate cost |

### Graph

| Method | Returns | Description |
|--------|---------|-------------|
| `GraphEntryPutAsync(string key, List<string> parents, string content, List<GraphDescendant> desc)` | `PutResult` | Create |
| `GraphEntryGetAsync(string address)` | `GraphEntry` | Read |
| `GraphEntryExistsAsync(string address)` | `bool` | Check existence |
| `GraphEntryCostAsync(string publicKey)` | `string` | Estimate cost |

### Registers

| Method | Returns | Description |
|--------|---------|-------------|
| `RegisterCreateAsync(string key, string initialValue)` | `PutResult` | Create |
| `RegisterGetAsync(string address)` | `Register` | Read |
| `RegisterUpdateAsync(string key, string newValue)` | `PutResult` | Update |
| `RegisterCostAsync(string publicKey)` | `string` | Estimate cost |

### Vaults

| Method | Returns | Description |
|--------|---------|-------------|
| `VaultGetAsync(string secretKey)` | `Vault` | Retrieve vault |
| `VaultPutAsync(string secretKey, byte[] data, ulong contentType)` | `string` | Store vault |
| `VaultCostAsync(string secretKey, ulong maxSize)` | `string` | Estimate cost |

### Files

| Method | Returns | Description |
|--------|---------|-------------|
| `FileUploadPublicAsync(string path)` | `PutResult` | Upload file |
| `FileDownloadPublicAsync(string address, string dest)` | — | Download file |
| `DirUploadPublicAsync(string path)` | `PutResult` | Upload directory |
| `DirDownloadPublicAsync(string address, string dest)` | — | Download directory |
| `ArchiveGetPublicAsync(string address)` | `Archive` | Get archive |
| `ArchivePutPublicAsync(Archive archive)` | `PutResult` | Create archive |
| `FileCostAsync(string path, bool isPublic, bool includeArchive)` | `string` | Estimate cost |

## Models

All models are sealed records (immutable).

| Model | Fields | Description |
|-------|--------|-------------|
| `HealthStatus` | `Ok`, `Network` | Health check result |
| `PutResult` | `Cost`, `Address` | Write operation result |
| `PointerTarget` | `Kind`, `Address` | Pointer target reference |
| `Pointer` | `Address`, `Owner`, `Counter`, `Target` | Pointer record |
| `ScratchpadRecord` | `Address`, `DataEncoding`, `Data`, `Counter` | Scratchpad record |
| `GraphDescendant` | `PublicKey`, `Content` | Graph descendant entry |
| `GraphEntry` | `Owner`, `Parents`, `Content`, `Descendants` | Graph DAG node |
| `Register` | `Value` | 32-byte register value (hex) |
| `Vault` | `Data`, `ContentType` | Vault record |
| `ArchiveEntry` | `Path`, `Address`, `Created`, `Modified`, `Size` | Archive file entry |
| `Archive` | `Entries` | Archive manifest |

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
dotnet run -- 5     # Pointers
dotnet run -- 6     # Scratchpads
dotnet run -- 7     # Graph
dotnet run -- 8     # Registers
dotnet run -- 9     # Vaults
dotnet run -- 10    # Private data
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
