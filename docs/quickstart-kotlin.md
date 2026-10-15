# Kotlin Quickstart

A comprehensive guide to using the Autonomi network with the Kotlin SDK.

> **📱 Building an Android app? This is the wrong doc.** This page covers the
> **REST/gRPC SDK**, which needs a locally-running `antd` daemon and targets
> **JVM/server** apps. For Android, use the in-process Kotlin bindings —
> **[`ant-android`](https://github.com/WithAutonomi/ant-android)** (published as
> `com.autonomi:ant-android` via the ant-maven repo) — which embed the Autonomi
> client directly (no daemon) and have their own getting-started guide covering
> connect methods, uploads/downloads, cost estimation, and external-signer
> (WalletConnect) payments. Continue below only if you specifically want the
> daemon-backed REST SDK on the JVM.

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
    baseUrl = "http://localhost:8082",
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

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
val est = client.dataCost(payload)
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

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
val est = client.fileCost("/path/to/file.txt")
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

## Manifests

A manifest describes a set of files as one `ant://manifest/` link, or as a `.ant` file when the link would be too long. Each entry is either a public file's address or an embedded DataMap (the manifest is then the key to a private file), with an optional path. Building and decoding upload and pay for nothing: upload the files first, then describe them. Needs the antd release after 0.15.0. Walk-through: [Tutorial: Share a Set of Files as One Link](tutorial-manifests.md).

```kotlin
val one = client.dataPutPublic("first note".toByteArray()).address   // pays
val two = client.dataPutPublic("second note".toByteArray()).address  // pays

val built = client.buildManifest(                                     // free
    listOf(
        ManifestEntryInput(address = one, path = "notes/one.txt"),
        ManifestEntryInput(address = two, path = "notes/two.txt"),
    ),
    BuildManifestOptions(name = "example"),
)
println(built.link)                                // null when over 1,500 bytes: share built.manifest (ByteArray) instead

val decoded = client.decodeManifestLink(built.link!!, resolve = true)   // free
decoded.entries.forEach { println("${it.effectiveName}: ${it.exactSize} bytes") }
```

`decodeManifest(bytes, resolve = false)` takes raw `.ant` bytes. Use `dataMap =` instead of `address =` for an embedded entry; `BuildManifestOptions` has `embedRoots` (default `true`). Sizes are `ULong?`.

Runnable example: `antd-kotlin/examples/src/main/kotlin/com/autonomi/examples/Example09Manifests.kt`. Its two uploads pay; the manifest calls do not.

```bash
cd antd-kotlin
ANTD_BASE_URL=http://localhost:8082 ./gradlew :examples:run --args="9"
```

## Examples

```bash
cd antd-kotlin

./gradlew :examples:run --args="1"    # Connect
./gradlew :examples:run --args="2"    # Public data
./gradlew :examples:run --args="3"    # Chunks
./gradlew :examples:run --args="4"    # Files
./gradlew :examples:run --args="6"    # Private data
./gradlew :examples:run --args="all"  # Run all examples
```

Or use the dev CLI:

```bash
ant dev example data -l kotlin
ant dev example all -l kotlin
```
