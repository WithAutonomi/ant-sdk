# antd-kotlin

Kotlin/JVM SDK for the [Autonomi](https://autonomi.com) decentralized network. Talks to the **antd** daemon via REST or gRPC.

## Installation

Add the dependency to your `build.gradle.kts`:

```kotlin
dependencies {
    implementation("com.autonomi:antd-kotlin:0.1.0")
}
```

> **Note**: Until published to Maven Central, use the project as a local dependency or include it as a composite build.

## Prerequisites

- JDK 17+
- A running `antd` daemon (see [ant-sdk README](../README.md))

## Quick Start

```kotlin
import com.autonomi.sdk.*
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    val client = AntdClient.createRest()

    // Check health
    val status = client.health()
    println("Network: ${status.network}")

    // Store data
    val result = client.dataPutPublic("Hello, Autonomi!".toByteArray())
    println("Address: ${result.address}")
    println("Chunks stored: ${result.chunksStored}")

    // Retrieve data
    val data = client.dataGetPublic(result.address)
    println(String(data)) // "Hello, Autonomi!"

    client.close()
}
```

## Transport Options

```kotlin
// REST (default, recommended)
val restClient = AntdClient.createRest("http://localhost:8082")

// gRPC (higher throughput; wallet operations and payment_mode are REST-only)
val grpcClient = AntdClient.createGrpc("localhost:50051")

// Dynamic transport selection
val client = AntdClient.create("rest") // or "grpc"
```

## API Surface

All methods are `suspend` functions for use with Kotlin coroutines.

| Domain | Methods |
|---|---|
| **Health** | `health()` returns `HealthStatus` carrying antd version, EVM network, uptime, build commit, and payment contract addresses (antd ≥ 0.4.0) |
| **Data** | `dataPutPublic`, `dataGetPublic`, `dataPut`, `dataGet`, `dataCost`. Private `dataPut` returns a caller-held DataMap (NOT stored on-network); public `dataPutPublic` stores the DataMap on-network at the returned address. All puts and `dataCost` accept a `PaymentMode` parameter. |
| **Chunks** | `chunkPut`, `chunkGet` |
| **Files** | `filePut`, `fileGet`, `filePutPublic`, `fileGetPublic`, `fileCost`. Private variants return a caller-held DataMap (NOT stored on-network); public variants store the DataMap on-network at the returned address. All puts and `fileCost` accept a `PaymentMode` parameter. |

## Error Handling

All errors extend `AntdException` with a `statusCode` property:

```kotlin
try {
    val data = client.dataGetPublic("nonexistent")
} catch (e: NotFoundException) {
    println("Not found: ${e.message}")
} catch (e: PaymentException) {
    println("Payment required: ${e.message}")
} catch (e: AntdException) {
    println("Error (${e.statusCode}): ${e.message}")
}
```

| Exception | HTTP | gRPC | Description |
|---|---|---|---|
| `NotFoundException` | 404 | NOT_FOUND | Resource not found |
| `AlreadyExistsException` | 409 | ALREADY_EXISTS | Resource already exists |
| `ForkException` | 409 | ABORTED | Conflicting update |
| `BadRequestException` | 400 | INVALID_ARGUMENT | Invalid input |
| `PaymentException` | 402 | FAILED_PRECONDITION | Insufficient funds |
| `NetworkException` | 502 | UNAVAILABLE | Network unreachable |
| `TooLargeException` | 413 | RESOURCE_EXHAUSTED | Data too large |
| `InternalException` | 500 | INTERNAL | Server error |

## Examples

Run individual examples:

```bash
./gradlew :examples:run --args="1"   # Connect
./gradlew :examples:run --args="2"   # Public Data
./gradlew :examples:run --args="all" # All examples
```

## Building

```bash
# Build everything
./gradlew build

# Run tests
./gradlew test

# Run examples
./gradlew :examples:run
```

## Project Structure

```
antd-kotlin/
├── lib/                          # SDK library
│   └── src/main/kotlin/com/autonomi/sdk/
│       ├── IAntdClient.kt        # Client interface
│       ├── AntdClient.kt         # Factory
│       ├── AntdRestClient.kt     # REST implementation
│       ├── AntdGrpcClient.kt     # gRPC implementation
│       ├── Models.kt             # Data classes
│       └── Exceptions.kt         # Exception hierarchy
├── examples/                     # 6 runnable examples
├── build.gradle.kts              # Root build config
└── settings.gradle.kts
```
