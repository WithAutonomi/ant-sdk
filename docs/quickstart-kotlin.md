# Kotlin Quickstart

A comprehensive guide to using the Autonomi network with the Kotlin SDK.

## Setup

```bash
# Prerequisites
# - JDK 17+
# - Gradle
# - antd daemon running (ant dev start)

# Build the SDK
cd antd-kotlin
./gradlew build
```

To reference the SDK from your own project, add the dependency to `build.gradle.kts`:

```kotlin
dependencies {
    implementation(project(":lib"))  // or published coordinates
}
```

Or scaffold a new project:

```bash
ant dev init kotlin --name my-project
```

## Connecting

```kotlin
import com.autonomi.sdk.*

// REST transport (default)
val client = AntdClient.createRest()

// Custom endpoint
val client2 = AntdClient.createRest(
    baseUrl = "http://localhost:8080",
    timeout = java.time.Duration.ofSeconds(30),
)

// gRPC transport
val grpcClient = AntdClient.createGrpc(
    target = "localhost:50051",
)

// Factory method
val auto = AntdClient.create(transport = "rest")
```

All methods are `suspend` functions for use with Kotlin coroutines. The client implements `Closeable`.

## Health Check

```kotlin
val status = client.health()
println("Healthy: ${status.ok}")
println("Network: ${status.network}")  // "local", "default", "alpha"
```

## Public Data

```kotlin
// Store
val payload = "Hello, Autonomi!".toByteArray()
val result = client.dataPutPublic(payload)
println("Address: ${result.address}")
println("Cost: ${result.cost} atto tokens")

// Retrieve
val data = client.dataGetPublic(result.address)
println(String(data))

// Cost estimation
val cost = client.dataCost(payload)
```

## Private Data

```kotlin
// Store (encrypted)
val secret = "secret message".toByteArray()
val result = client.dataPutPrivate(secret)
val dataMap = result.address  // Keep this secret!

// Retrieve (decrypt)
val decrypted = client.dataGetPrivate(dataMap)
println(String(decrypted))
```

## Files

```kotlin
// Upload a file
val result = client.fileUploadPublic("/path/to/file.txt")

// Download a file
client.fileDownloadPublic(result.address, "/path/to/output.txt")

// Upload a directory
val dirResult = client.dirUploadPublic("/path/to/directory")

// Download a directory
client.dirDownloadPublic(dirResult.address, "/path/to/output_dir")

// Cost estimation
val cost = client.fileCost("/path/to/file.txt")
```

## Pointers (Mutable References)

```kotlin
import java.security.SecureRandom

val secretKey = ByteArray(32).also { SecureRandom().nextBytes(it) }
    .joinToString("") { "%02x".format(it) }

// Store two versions
val v1 = client.dataPutPublic("version 1".toByteArray())
val v2 = client.dataPutPublic("version 2".toByteArray())

// Create pointer to v1
val target = PointerTarget("chunk", v1.address)
val ptr = client.pointerCreate(secretKey, target)
println("Pointer: ${ptr.address}")

// Read
val pointer = client.pointerGet(ptr.address)
println("Points to: ${pointer.target.address}")
println("Counter: ${pointer.counter}")

// Update to v2
client.pointerUpdate(
    secretKey,
    PointerTarget("chunk", v2.address),
)

// Check existence
val exists = client.pointerExists(ptr.address)
```

## Scratchpads (Versioned Mutable Storage)

```kotlin
val secretKey = ByteArray(32).also { SecureRandom().nextBytes(it) }
    .joinToString("") { "%02x".format(it) }

// Create
val result = client.scratchpadCreate(
    secretKey,
    contentType = 1UL,
    data = "initial data".toByteArray(),
)

// Read
val pad = client.scratchpadGet(result.address)
println("Counter: ${pad.counter}")
println("Data: ${String(pad.data)}")

// Update
client.scratchpadUpdate(
    secretKey,
    contentType = 1UL,
    data = "updated data".toByteArray(),
)

// Check existence
val exists = client.scratchpadExists(result.address)
```

## Graph Entries (DAG Nodes)

```kotlin
val secretKey = ByteArray(32).also { SecureRandom().nextBytes(it) }
    .joinToString("") { "%02x".format(it) }
val content = ByteArray(32).also { SecureRandom().nextBytes(it) }
    .joinToString("") { "%02x".format(it) }

// Create root node
val result = client.graphEntryPut(
    secretKey,
    parents = emptyList(),
    content = content,
    descendants = emptyList(),
)

// Read
val entry = client.graphEntryGet(result.address)
println("Owner: ${entry.owner}")
println("Parents: ${entry.parents.size}")

// Check existence
val exists = client.graphEntryExists(result.address)
```

## Registers (32-byte Values)

```kotlin
val secretKey = ByteArray(32).also { SecureRandom().nextBytes(it) }
    .joinToString("") { "%02x".format(it) }

// Create (64 hex chars = 32 bytes)
val initial = "0".repeat(64)
val result = client.registerCreate(secretKey, initial)

// Read
val reg = client.registerGet(result.address)
println("Value: ${reg.value}")

// Update
val newValue = ByteArray(32).also { SecureRandom().nextBytes(it) }
    .joinToString("") { "%02x".format(it) }
client.registerUpdate(secretKey, newValue)
```

## Vaults (Encrypted Key-Value)

```kotlin
val secretKey = ByteArray(32).also { SecureRandom().nextBytes(it) }
    .joinToString("") { "%02x".format(it) }

// Store
val cost = client.vaultPut(
    secretKey,
    "vault data".toByteArray(),
    contentType = 42UL,
)

// Retrieve
val vault = client.vaultGet(secretKey)
println("Data: ${String(vault.data)}")
println("Content type: ${vault.contentType}")
```

## Error Handling

```kotlin
import com.autonomi.sdk.*

try {
    client.dataGetPublic("nonexistent")
} catch (e: NotFoundException) {
    println("Not found: ${e.message}")
} catch (e: PaymentException) {
    println("Payment issue: ${e.message}")
} catch (e: NetworkException) {
    println("Network unreachable: ${e.message}")
} catch (e: AntdException) {
    println("Error (${e.statusCode}): ${e.message}")
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
cd antd-kotlin

./gradlew :examples:run --args="1"    # Connect
./gradlew :examples:run --args="2"    # Public data
./gradlew :examples:run --args="3"    # Chunks
./gradlew :examples:run --args="4"    # Files
./gradlew :examples:run --args="5"    # Pointers
./gradlew :examples:run --args="6"    # Scratchpads
./gradlew :examples:run --args="7"    # Graph entries
./gradlew :examples:run --args="8"    # Registers
./gradlew :examples:run --args="9"    # Vaults
./gradlew :examples:run --args="10"   # Private data
./gradlew :examples:run --args="all"  # Run all examples
```

Or use the dev CLI:

```bash
ant dev example data -l kotlin
ant dev example all -l kotlin
```
