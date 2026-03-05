# Tutorial: Store and Retrieve Data

This tutorial covers the fundamentals: storing text, uploading files, downloading files, and estimating costs. Each example is shown in both Python and C#.

## Prerequisites

- antd daemon running on a local testnet (`ant dev start`)
- Python SDK installed (`pip install antd[rest]`) or C# SDK built (`dotnet build`)

## 1. Store and Retrieve Text

The simplest operation: store a byte string on the network and retrieve it by address.

### Python

```python
from antd import AntdClient

client = AntdClient()

# Store text as public data
text = b"Hello, Autonomi network!"
result = client.data_put_public(text)

print(f"Stored at: {result.address}")
print(f"Cost: {result.cost} atto tokens")

# Retrieve by address
data = client.data_get_public(result.address)
print(f"Retrieved: {data.decode()}")

assert data == text  # Exact match guaranteed
```

### C#

```csharp
using System.Text;
using Antd.Sdk;

using var client = AntdClient.CreateRest();

var text = Encoding.UTF8.GetBytes("Hello, Autonomi network!");
var result = await client.DataPutPublicAsync(text);

Console.WriteLine($"Stored at: {result.Address}");
Console.WriteLine($"Cost: {result.Cost} atto tokens");

var data = await client.DataGetPublicAsync(result.Address);
Console.WriteLine($"Retrieved: {Encoding.UTF8.GetString(data)}");
```

**Key concepts:**
- `data_put_public` stores data so anyone with the address can read it.
- The `address` is a content hash — the same data always produces the same address.
- The `cost` is in atto tokens (1 token = 10^18 atto).

## 2. Estimate Costs Before Storing

Always check costs before committing to the network, especially for large payloads.

### Python

```python
from antd import AntdClient

client = AntdClient()

payload = b"Cost estimation example data"

# Check cost first
cost = client.data_cost(payload)
print(f"Estimated cost: {cost} atto tokens")

# If acceptable, store it
result = client.data_put_public(payload)
print(f"Actual cost: {result.cost} atto tokens")
```

### C#

```csharp
using System.Text;
using Antd.Sdk;

using var client = AntdClient.CreateRest();

var payload = Encoding.UTF8.GetBytes("Cost estimation example data");

var cost = await client.DataCostAsync(payload);
Console.WriteLine($"Estimated cost: {cost} atto tokens");

var result = await client.DataPutPublicAsync(payload);
Console.WriteLine($"Actual cost: {result.Cost} atto tokens");
```

## 3. Upload and Download Files

Upload local files to the network and download them to a new location.

### Python

```python
from antd import AntdClient
import tempfile
import os

client = AntdClient()

# Create a test file
src = os.path.join(tempfile.gettempdir(), "test-upload.txt")
with open(src, "w") as f:
    f.write("File content stored on Autonomi!")

# Estimate cost
cost = client.file_cost(src)
print(f"Upload cost estimate: {cost} atto tokens")

# Upload
result = client.file_upload_public(src)
print(f"File uploaded to: {result.address}")

# Download to a different location
dest = src + ".downloaded"
client.file_download_public(result.address, dest)

with open(dest) as f:
    print(f"Downloaded content: {f.read()}")

# Clean up
os.unlink(src)
os.unlink(dest)
```

### C#

```csharp
using Antd.Sdk;

using var client = AntdClient.CreateRest();

var srcPath = Path.GetTempFileName();
await File.WriteAllTextAsync(srcPath, "File content stored on Autonomi!");

try
{
    var cost = await client.FileCostAsync(srcPath);
    Console.WriteLine($"Upload cost: {cost} atto tokens");

    var result = await client.FileUploadPublicAsync(srcPath);
    Console.WriteLine($"Uploaded to: {result.Address}");

    var destPath = srcPath + ".downloaded";
    await client.FileDownloadPublicAsync(result.Address, destPath);

    var content = await File.ReadAllTextAsync(destPath);
    Console.WriteLine($"Downloaded: {content}");

    File.Delete(destPath);
}
finally
{
    File.Delete(srcPath);
}
```

## 4. Private (Encrypted) Data

Store data that only you can read. The network never sees the plaintext.

### Python

```python
from antd import AntdClient

client = AntdClient()

secret_message = b"This is encrypted on the network"

# Store privately
result = client.data_put_private(secret_message)
data_map = result.address  # This is the decryption key — keep it secret!
print(f"Data map: {data_map[:40]}...")

# Retrieve and decrypt
decrypted = client.data_get_private(data_map)
print(f"Decrypted: {decrypted.decode()}")

assert decrypted == secret_message
```

### C#

```csharp
using System.Text;
using Antd.Sdk;

using var client = AntdClient.CreateRest();

var secret = Encoding.UTF8.GetBytes("This is encrypted on the network");

var result = await client.DataPutPrivateAsync(secret);
var dataMap = result.Address;
Console.WriteLine($"Data map: {dataMap[..40]}...");

var decrypted = await client.DataGetPrivateAsync(dataMap);
Console.WriteLine($"Decrypted: {Encoding.UTF8.GetString(decrypted)}");
```

**Key concepts:**
- Private data is self-encrypted before leaving your machine.
- The "data map" returned is the decryption metadata — treat it as a secret.
- Without the data map, the encrypted chunks on the network are unreadable.

## 5. Raw Chunks

For advanced use cases, you can store and retrieve raw chunks directly.

### Python

```python
from antd import AntdClient

client = AntdClient()

raw = b"Raw chunk content for direct storage"
result = client.chunk_put(raw)
print(f"Chunk address: {result.address}")

retrieved = client.chunk_get(result.address)
assert retrieved == raw
print("Chunk round-trip OK!")
```

### C#

```csharp
using System.Text;
using Antd.Sdk;

using var client = AntdClient.CreateRest();

var raw = Encoding.UTF8.GetBytes("Raw chunk content for direct storage");
var result = await client.ChunkPutAsync(raw);
Console.WriteLine($"Chunk address: {result.Address}");

var retrieved = await client.ChunkGetAsync(result.Address);
Console.WriteLine($"Retrieved {retrieved.Length} bytes");
```

## Error Handling

Always handle errors in production code:

### Python

```python
from antd import AntdClient, NotFoundError, PaymentError, AntdError

client = AntdClient()

try:
    data = client.data_get_public("0000000000000000")
except NotFoundError:
    print("Address not found on the network")
except PaymentError:
    print("Payment failed — check wallet balance")
except AntdError as e:
    print(f"Unexpected error ({e.status_code}): {e}")
```

### C#

```csharp
using Antd.Sdk;

using var client = AntdClient.CreateRest();

try
{
    var data = await client.DataGetPublicAsync("0000000000000000");
}
catch (NotFoundException)
{
    Console.WriteLine("Address not found");
}
catch (PaymentException)
{
    Console.WriteLine("Payment failed");
}
catch (AntdException ex)
{
    Console.WriteLine($"Error ({ex.StatusCode}): {ex.Message}");
}
```

## Next Steps

- [Tutorial: Build a Key-Value Store](tutorial-key-value-store.md) — Mutable data with registers and pointers
- [Tutorial: Mutable Configuration](tutorial-mutable-config.md) — Pointers and scratchpads for app config
- [Architecture Guide](architecture.md) — Understand the full data model
