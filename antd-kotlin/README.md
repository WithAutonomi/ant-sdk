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

Both clients follow this table: every `AntdGrpcClient` method maps a failed gRPC status to the exception type in the same row, so a `catch (e: NotFoundException)` works unchanged whichever client you construct, and raw `io.grpc.StatusException` / `StatusRuntimeException` never escape. The mapping is not one-to-one everywhere, because gRPC carries less detail than HTTP: the daemon reports both an unreachable network (REST 502) and a service-unavailable error (REST 503) as gRPC UNAVAILABLE, so a service-unavailable error throws `ServiceUnavailableException` over REST but `NetworkException` over gRPC; code that must handle it on both transports should catch both. A gRPC status with no row here (e.g. DEADLINE_EXCEEDED) throws a plain `AntdException` whose `statusCode` is the gRPC code number.

### Partial uploads

An external-signer finalize (`finalizeUpload`, `finalizeMerkleUpload`, `finalizeChunkUpload`) can fail *after* the wallet has paid: some chunks store, others miss quorum after the daemon's own retries. That surfaces as `PartialUploadException` carrying `chunksStored` / `chunksFailed` / `totalChunks` and two flags, `retryable` and `retentionKnown` (`retryable` implies `retentionKnown`). The on-chain payment persists and the stored chunks stay on the network; the flags say how to finish:

- **`retryable`** — the daemon kept the paid attempt under the same `uploadId`. Call the **same** finalize method again with the same `uploadId` and payment artefacts to store the remainder against the same payment — no re-prepare, no second signature, no double payment. Bound that loop: a persistent failure throws on every call, so cap the attempts and treat a `chunksFailed` that stops shrinking as stuck. The retained attempt expires with the daemon's pending-upload TTL.
- **`retentionKnown && !retryable`** — the daemon confirmed it kept nothing (e.g. a merkle finalize with deliberately unpaid batches). Re-prepare the same content; already-stored chunks are skipped, so the retry pays only for the remainder.
- **`!retentionKnown`** — retention is unknown, and the daemon may still hold the paid attempt: it records the resume handle before it returns the error. Stop automatic recovery, keep the `uploadId` and the original payment artefacts (tx hashes / quote data), and reconcile before re-preparing or paying again. Never pay again on this signal alone. Daemons older than 0.14.0 never send `retryable`, so their REST partial uploads always read as unknown.

`PartialUploadException` extends `NetworkException` because the daemon reports it as a 502, so existing `catch (e: NetworkException)` blocks keep working; narrow with `is PartialUploadException` to read the counts and flags. It is not a `ForkException`: over gRPC a partial upload's ABORTED used to map to `ForkException`, and the daemon sends ABORTED only for PARTIAL_UPLOAD, so code that caught `ForkException` around a gRPC finalize should catch `PartialUploadException` instead.

Over gRPC an ABORTED status maps to `PartialUploadException` only when its message starts with the daemon's fixed `Partial upload:` prefix (anchored, as in antd-rust); any other ABORTED stays a `ForkException`. `retentionKnown` is true only when the message starts with the count layout (`Partial upload: S/T chunks stored, F failed after retries: <reason> (<hint>)`), all three counts convert to a `Long`, and the message ends with one of the daemon's two closing hints: `(paid attempt retained…)` sets `retryable`, and `(stored chunks persist; re-prepare the same content…)` means the daemon confirmed it kept nothing (daemons older than 0.14.0 write only this one). If the layout does not match or any count fails to convert (e.g. one past `Long.MAX_VALUE`), all three counts read as zero and both flags as false, even if a hint is present. Readable counts with a missing, truncated or unrecognised hint, or text after it, keep the counts, but both flags stay false: retention is unknown, so stop and reconcile rather than re-prepare.

Over REST, each count is read only from a JSON number holding a non-negative integer; a quoted number, a negative, fractional or out-of-range number, an array or an object reads as zero. `retentionKnown` is true when the body's `retryable` is a JSON boolean (`true` or `false`), and `retryable` only when it is the literal `true`; missing, `null`, a quoted `"true"`, a number, an array or an object reads as unknown and not retryable. A non-string `code` falls back to the plain `NetworkException`, and the error mapper never throws on a malformed body.

See `finalizeWithRetry` in `examples/src/main/kotlin/com/autonomi/examples/Example07ExternalSigner.kt` for a bounded retry loop that rethrows the original `PartialUploadException` whenever it stops, and [`docs/external-signer-flow.md` §6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment) for the daemon-side contract.

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
