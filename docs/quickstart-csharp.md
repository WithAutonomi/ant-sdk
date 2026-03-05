# C# Quickstart

A comprehensive guide to using the Autonomi network with the C# SDK.

## Setup

```bash
# Prerequisites
# - .NET 8 SDK: https://dotnet.microsoft.com/download/dotnet/8.0
# - antd daemon running (ant dev start)

# Build the SDK
cd antd-csharp
dotnet build Antd.sln
```

To reference the SDK from your own project:

```xml
<ItemGroup>
  <ProjectReference Include="../antd-csharp/Antd.Sdk/Antd.Sdk.csproj" />
</ItemGroup>
```

Or scaffold a new project:

```bash
ant dev init csharp --name my-project
```

## Connecting

```csharp
using Antd.Sdk;

// REST transport (default)
using var client = AntdClient.CreateRest();

// Custom endpoint
using var client2 = AntdClient.CreateRest(
    baseUrl: "http://localhost:8080",
    timeout: TimeSpan.FromSeconds(30)
);

// gRPC transport
using var grpcClient = AntdClient.CreateGrpc(
    target: "http://localhost:50051"
);

// Factory method
using var auto = AntdClient.Create(transport: "rest");
```

All methods are async. The client implements `IDisposable`.

## Health Check

```csharp
var status = await client.HealthAsync();
Console.WriteLine($"Healthy: {status.Ok}");
Console.WriteLine($"Network: {status.Network}");  // "local", "default", "alpha"
```

## Public Data

```csharp
using System.Text;

// Store
var payload = Encoding.UTF8.GetBytes("Hello, Autonomi!");
var result = await client.DataPutPublicAsync(payload);
Console.WriteLine($"Address: {result.Address}");
Console.WriteLine($"Cost: {result.Cost} atto tokens");

// Retrieve
var data = await client.DataGetPublicAsync(result.Address);
Console.WriteLine(Encoding.UTF8.GetString(data));

// Cost estimation
var cost = await client.DataCostAsync(payload);
```

## Private Data

```csharp
// Store (encrypted)
var secret = Encoding.UTF8.GetBytes("secret message");
var result = await client.DataPutPrivateAsync(secret);
var dataMap = result.Address;  // Keep this secret!

// Retrieve (decrypt)
var decrypted = await client.DataGetPrivateAsync(dataMap);
Console.WriteLine(Encoding.UTF8.GetString(decrypted));
```

## Files

```csharp
// Upload a file
var result = await client.FileUploadPublicAsync("/path/to/file.txt");

// Download a file
await client.FileDownloadPublicAsync(result.Address, "/path/to/output.txt");

// Upload a directory
var dirResult = await client.DirUploadPublicAsync("/path/to/directory");

// Download a directory
await client.DirDownloadPublicAsync(dirResult.Address, "/path/to/output_dir");

// Cost estimation
var cost = await client.FileCostAsync("/path/to/file.txt");
```

## Pointers (Mutable References)

```csharp
using System.Security.Cryptography;

var secretKey = Convert.ToHexString(
    RandomNumberGenerator.GetBytes(32)
).ToLower();

// Store two versions
var v1 = await client.DataPutPublicAsync(
    Encoding.UTF8.GetBytes("version 1")
);
var v2 = await client.DataPutPublicAsync(
    Encoding.UTF8.GetBytes("version 2")
);

// Create pointer to v1
var target = new PointerTarget("chunk", v1.Address);
var ptr = await client.PointerCreateAsync(secretKey, target);
Console.WriteLine($"Pointer: {ptr.Address}");

// Read
var pointer = await client.PointerGetAsync(ptr.Address);
Console.WriteLine($"Points to: {pointer.Target.Address}");
Console.WriteLine($"Counter: {pointer.Counter}");

// Update to v2
await client.PointerUpdateAsync(
    secretKey,
    new PointerTarget("chunk", v2.Address)
);

// Check existence
var exists = await client.PointerExistsAsync(ptr.Address);
```

## Scratchpads (Versioned Mutable Storage)

```csharp
var secretKey = Convert.ToHexString(
    RandomNumberGenerator.GetBytes(32)
).ToLower();

// Create
var result = await client.ScratchpadCreateAsync(
    secretKey,
    contentType: 1,
    data: Encoding.UTF8.GetBytes("initial data")
);

// Read
var pad = await client.ScratchpadGetAsync(result.Address);
Console.WriteLine($"Counter: {pad.Counter}");
Console.WriteLine($"Data: {Encoding.UTF8.GetString(pad.Data)}");

// Update
await client.ScratchpadUpdateAsync(
    secretKey,
    contentType: 1,
    data: Encoding.UTF8.GetBytes("updated data")
);

// Check existence
var exists = await client.ScratchpadExistsAsync(result.Address);
```

## Graph Entries (DAG Nodes)

```csharp
var secretKey = Convert.ToHexString(
    RandomNumberGenerator.GetBytes(32)
).ToLower();
var content = Convert.ToHexString(
    RandomNumberGenerator.GetBytes(32)
).ToLower();

// Create root node
var result = await client.GraphEntryPutAsync(
    secretKey,
    parents: new List<string>(),
    content: content,
    descendants: new List<GraphDescendant>()
);

// Read
var entry = await client.GraphEntryGetAsync(result.Address);
Console.WriteLine($"Owner: {entry.Owner}");
Console.WriteLine($"Parents: {entry.Parents.Count}");

// Check existence
var exists = await client.GraphEntryExistsAsync(result.Address);
```

## Registers (32-byte Values)

```csharp
var secretKey = Convert.ToHexString(
    RandomNumberGenerator.GetBytes(32)
).ToLower();

// Create (64 hex chars = 32 bytes)
var initial = new string('0', 64);
var result = await client.RegisterCreateAsync(secretKey, initial);

// Read
var reg = await client.RegisterGetAsync(result.Address);
Console.WriteLine($"Value: {reg.Value}");

// Update
var newValue = Convert.ToHexString(
    RandomNumberGenerator.GetBytes(32)
).ToLower();
await client.RegisterUpdateAsync(secretKey, newValue);
```

## Vaults (Encrypted Key-Value)

```csharp
var secretKey = Convert.ToHexString(
    RandomNumberGenerator.GetBytes(32)
).ToLower();

// Store
var cost = await client.VaultPutAsync(
    secretKey,
    Encoding.UTF8.GetBytes("vault data"),
    contentType: 42
);

// Retrieve
var vault = await client.VaultGetAsync(secretKey);
Console.WriteLine($"Data: {Encoding.UTF8.GetString(vault.Data)}");
Console.WriteLine($"Content type: {vault.ContentType}");
```

## Error Handling

```csharp
using Antd.Sdk;

try
{
    await client.DataGetPublicAsync("nonexistent");
}
catch (NotFoundException)
{
    Console.WriteLine("Not found");
}
catch (PaymentException)
{
    Console.WriteLine("Payment issue");
}
catch (NetworkException)
{
    Console.WriteLine("Network unreachable");
}
catch (AntdException ex)
{
    Console.WriteLine($"Error ({ex.StatusCode}): {ex.Message}");
}
```

Exception hierarchy:

| Exception | HTTP Code | When |
|-----------|-----------|------|
| `BadRequestException` | 400 | Invalid parameters |
| `PaymentException` | 402 | Insufficient funds |
| `NotFoundException` | 404 | Resource not found |
| `AlreadyExistsException` | 409 | Duplicate creation |
| `ForkException` | 409 | Version conflict |
| `TooLargeException` | 413 | Payload too large |
| `InternalException` | 500 | Server error |
| `NetworkException` | 502 | Network unreachable |

## Examples

```bash
cd antd-csharp/Examples

dotnet run -- 1      # Connect
dotnet run -- 2      # Public data
dotnet run -- 3      # Chunks
dotnet run -- 4      # Files
dotnet run -- 5      # Pointers
dotnet run -- 6      # Scratchpads
dotnet run -- 7      # Graph entries
dotnet run -- 8      # Registers
dotnet run -- 9      # Vaults
dotnet run -- 10     # Private data
dotnet run -- all    # Run all examples
```

Or use the dev CLI:

```bash
ant dev example data -l csharp
ant dev example all -l csharp
```
