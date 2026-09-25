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
| `ForkException` | 409 | ABORTED (non-partial-upload) | Conflicting update |
| `BadRequestException` | 400 | INVALID_ARGUMENT | Invalid input |
| `PaymentException` | 402 | FAILED_PRECONDITION | Insufficient funds |
| `NetworkException` | 502 | UNAVAILABLE | Network unreachable |
| `PartialUploadException` | 502 (`code: "PARTIAL_UPLOAD"`) | ABORTED (`Partial upload:` message) | Finalize stored some chunks, others stayed unstored (extends `NetworkException`) |
| `TooLargeException` | 413 | RESOURCE_EXHAUSTED | Data too large |
| `InternalException` | 500 | INTERNAL | Server error |

### Partial uploads

An external-signer finalize (`finalizeUpload`, `finalizeMerkleUpload`, `finalizeChunkUpload`) can fail *after* the wallet has paid: some chunks store, others miss quorum after the daemon's own retries. That surfaces as `PartialUploadException` carrying `chunksStored` / `chunksFailed` / `totalChunks` and a `retryable` flag. The on-chain payment persists and the stored chunks stay on the network; `retryable` says how to finish:

- **`retryable == true`** (flag sent by antd ≥ 0.14.0) — the daemon kept the paid attempt under the same `uploadId`. Call the **same** finalize method again with the same arguments to store the remainder against the same payment — no re-prepare, no second signature, no double payment. Bound that loop: a persistent failure throws on every call, so cap the attempts and treat a `chunksFailed` that stops shrinking as stuck. The retained attempt expires with the daemon's pending-upload TTL.
- **`retryable == false`** — nothing was retained: an older daemon (the flag is absent and defaults to `false`), or a merkle finalize with deliberately unpaid batches. Re-preparing the same content skips already-stored chunks, so a retry pays only for the remainder.

`PartialUploadException` extends `NetworkException` because the daemon reports it as a 502, so existing `catch (e: NetworkException)` blocks keep working; narrow with `is PartialUploadException` to read the counts. Over gRPC an ABORTED status maps to `PartialUploadException` only when its message starts with the daemon's fixed `Partial upload:` prefix (anchored, as in antd-rust); the counts are then parsed from that message (`Partial upload: S/T chunks stored, F failed …`), and `retryable` is true only when the message matches that layout, all three counts convert to a `Long`, and it carries the daemon's "paid attempt retained" hint. If the layout does not match or any count fails to convert (e.g. one past `Long.MAX_VALUE`), all three counts read as zero and `retryable` as false, even if the hint is present. Over REST, each count is read only from a JSON number holding a non-negative integer, and `retryable` only from a JSON boolean. A quoted number, a quoted `"true"`, a negative, fractional or out-of-range number, an array or an object reads as zero / `false`. A non-string `code` falls back to the plain `NetworkException`, and the error mapper never throws on a malformed body. Any other ABORTED stays a `ForkException`. See `finalizeWithRetry` in `examples/src/main/kotlin/com/autonomi/examples/Example07ExternalSigner.kt` for a bounded retry loop, and [`docs/external-signer-flow.md` §6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment) for the daemon-side contract.

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
