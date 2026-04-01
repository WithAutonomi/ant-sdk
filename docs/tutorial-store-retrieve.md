# Tutorial: Store and Retrieve Data

This tutorial covers the fundamentals: storing text, uploading files, downloading files, and estimating costs. Each example is shown in Python, C#, Kotlin, and Swift.

## Prerequisites

- antd daemon running on a local testnet (`ant dev start`)
- Python SDK installed (`pip install antd[rest]`), C# SDK built (`dotnet build`), Kotlin SDK built (`./gradlew build`), or Swift SDK built (`swift build`)

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

### Kotlin

```kotlin
import com.autonomi.sdk.*
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    val client = AntdClient.createRest()

    val text = "Hello, Autonomi network!".toByteArray()
    val result = client.dataPutPublic(text)

    println("Stored at: ${result.address}")
    println("Cost: ${result.cost} atto tokens")

    val data = client.dataGetPublic(result.address)
    println("Retrieved: ${String(data)}")

    check(data.contentEquals(text))
    client.close()
}
```

### Swift

```swift
import AntdSdk

let client = try AntdClient.createRest()

let text = "Hello, Autonomi network!".data(using: .utf8)!
let result = try await client.dataPutPublic(text)

print("Stored at: \(result.address)")
print("Cost: \(result.cost) atto tokens")

let data = try await client.dataGetPublic(address: result.address)
print("Retrieved: \(String(data: data, encoding: .utf8)!)")

assert(data == text)
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

### Kotlin

```kotlin
val client = AntdClient.createRest()

val payload = "Cost estimation example data".toByteArray()

val cost = client.dataCost(payload)
println("Estimated cost: $cost atto tokens")

val result = client.dataPutPublic(payload)
println("Actual cost: ${result.cost} atto tokens")
```

### Swift

```swift
let client = try AntdClient.createRest()

let payload = "Cost estimation example data".data(using: .utf8)!

let cost = try await client.dataCost(payload)
print("Estimated cost: \(cost) atto tokens")

let result = try await client.dataPutPublic(payload)
print("Actual cost: \(result.cost) atto tokens")
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

### Kotlin

```kotlin
val client = AntdClient.createRest()

val srcFile = java.io.File.createTempFile("test-upload", ".txt")
srcFile.writeText("File content stored on Autonomi!")

try {
    val cost = client.fileCost(srcFile.absolutePath)
    println("Upload cost: $cost atto tokens")

    val result = client.fileUploadPublic(srcFile.absolutePath)
    println("Uploaded to: ${result.address}")

    val destPath = srcFile.absolutePath + ".downloaded"
    client.fileDownloadPublic(result.address, destPath)

    val content = java.io.File(destPath).readText()
    println("Downloaded: $content")
    java.io.File(destPath).delete()
} finally {
    srcFile.delete()
}
```

### Swift

```swift
import AntdSdk
import Foundation

let client = try AntdClient.createRest()

let srcPath = NSTemporaryDirectory() + "test-upload.txt"
try "File content stored on Autonomi!".write(
    toFile: srcPath, atomically: true, encoding: .utf8
)

do {
    let cost = try await client.fileCost(path: srcPath)
    print("Upload cost: \(cost) atto tokens")

    let result = try await client.fileUploadPublic(path: srcPath)
    print("Uploaded to: \(result.address)")

    let destPath = srcPath + ".downloaded"
    try await client.fileDownloadPublic(address: result.address, destPath: destPath)

    let content = try String(contentsOfFile: destPath, encoding: .utf8)
    print("Downloaded: \(content)")
    try FileManager.default.removeItem(atPath: destPath)
} catch {
    throw error
}
try FileManager.default.removeItem(atPath: srcPath)
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

### Kotlin

```kotlin
val client = AntdClient.createRest()

val secretMessage = "This is encrypted on the network".toByteArray()

val result = client.dataPutPrivate(secretMessage)
val dataMap = result.address
println("Data map: ${dataMap.take(40)}...")

val decrypted = client.dataGetPrivate(dataMap)
println("Decrypted: ${String(decrypted)}")

check(decrypted.contentEquals(secretMessage))
```

### Swift

```swift
let client = try AntdClient.createRest()

let secretMessage = "This is encrypted on the network".data(using: .utf8)!

let result = try await client.dataPutPrivate(secretMessage)
let dataMap = result.address
print("Data map: \(String(dataMap.prefix(40)))...")

let decrypted = try await client.dataGetPrivate(dataMap: dataMap)
print("Decrypted: \(String(data: decrypted, encoding: .utf8)!)")

assert(decrypted == secretMessage)
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

### Kotlin

```kotlin
val client = AntdClient.createRest()

val raw = "Raw chunk content for direct storage".toByteArray()
val result = client.chunkPut(raw)
println("Chunk address: ${result.address}")

val retrieved = client.chunkGet(result.address)
check(retrieved.contentEquals(raw))
println("Chunk round-trip OK!")
```

### Swift

```swift
let client = try AntdClient.createRest()

let raw = "Raw chunk content for direct storage".data(using: .utf8)!
let result = try await client.chunkPut(raw)
print("Chunk address: \(result.address)")

let retrieved = try await client.chunkGet(address: result.address)
assert(retrieved == raw)
print("Chunk round-trip OK!")
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

### Kotlin

```kotlin
import com.autonomi.sdk.*

val client = AntdClient.createRest()

try {
    val data = client.dataGetPublic("0000000000000000")
} catch (e: NotFoundException) {
    println("Address not found")
} catch (e: PaymentException) {
    println("Payment failed")
} catch (e: AntdException) {
    println("Error (${e.statusCode}): ${e.message}")
}
```

### Swift

```swift
import AntdSdk

let client = try AntdClient.createRest()

do {
    let data = try await client.dataGetPublic(address: "0000000000000000")
} catch let error as NotFoundError {
    print("Address not found")
} catch let error as PaymentError {
    print("Payment failed")
} catch let error as AntdError {
    print("Error (\(error.statusCode)): \(error.localizedDescription)")
}
```

## Next Steps

- [Architecture Guide](architecture.md) — Understand the full data model
