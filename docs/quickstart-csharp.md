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
    baseUrl: "http://localhost:8082",
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

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
var est = await client.DataCostAsync(payload);
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

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
var est = await client.FileCostAsync("/path/to/file.txt");
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

## Manifests

A manifest describes a set of files as one `ant://manifest/` link, or as a `.ant` file when the link would be too long. Each entry is either a public file's address or an embedded DataMap (the manifest is then the key to a private file), with an optional path. Building and decoding upload and pay for nothing: upload the files first, then describe them. Needs the antd release after 0.15.0. Walk-through: [Tutorial: Share a Set of Files as One Link](tutorial-manifests.md).

```csharp
var one = await client.DataPutPublicAsync(Encoding.UTF8.GetBytes("note one"));   // pays
var two = await client.DataPutPublicAsync(Encoding.UTF8.GetBytes("note two"));   // pays

var built = await client.BuildManifestAsync(new[]                                 // free
{
    ManifestEntryInput.Public(one.Address, "notes/one.txt"),
    ManifestEntryInput.Public(two.Address, "notes/two.txt"),
}, new BuildManifestOptions(Name: "example"));
Console.WriteLine(built.Link);                    // null when over 1,500 bytes: share built.Manifest (byte[]) instead

var decoded = await client.DecodeManifestLinkAsync(built.Link!, resolve: true);  // free
foreach (var e in decoded.Entries)
    Console.WriteLine($"{e.EffectiveName}: {e.ExactSize} bytes");
```

`DecodeManifestAsync(byte[] manifest, bool resolve = false)` takes raw `.ant` bytes. `ManifestEntryInput.Embedded(dataMap, path)` makes an embedded entry. Sizes are `ulong?`.

Runnable example: example 9 in `antd-csharp/Examples/Program.cs`. Its two uploads pay; the manifest calls do not.

```bash
cd antd-csharp/Examples
ANTD_BASE_URL=http://localhost:8082 dotnet run -- 9
```

## Examples

```bash
cd antd-csharp/Examples

dotnet run -- 1      # Connect
dotnet run -- 2      # Public data
dotnet run -- 3      # Chunks
dotnet run -- 4      # Files
dotnet run -- 6      # Private data
dotnet run -- all    # Run all examples
```

Or use the dev CLI:

```bash
ant dev example data -l csharp
ant dev example all -l csharp
```
