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
| **Pointers** | `pointerKeys`, `pointerCreate`, `pointerUpdate`, `pointerTransfer`, `pointerGet`, `pointerResolve`, `pointerFinality`, `pointerController`, `pointerPrepare`, `pointerFinalize`. See [Pointers](#pointers). |

## Pointers

A pointer is a small, owner-signed, mutable reference. Its address is derived from the owner's key and never changes; what it points at (a chunk, such as a public file's data map, or another pointer) can be changed by the owner. The daemon holds the owner keys, loaded at startup with `antd --pointer-keys <file-or-dir>` (files in the format `ant pointer keygen` writes), so every write names the pointer by its address (`owner`), never by a key. An owner the daemon holds no key for is a `BadRequestException`. Addresses are 64 hex characters; the daemon accepts a `0x` prefix but always returns bare lowercase hex, so normalise before comparing. The pointer methods need the antd release after 0.15.0, the first with pointers; both `AntdRestClient` and `AntdGrpcClient` implement them.

**Every write pays** (about the price of one chunk), and every attempt pays again. Neither client retries `pointerCreate`, `pointerUpdate`, `pointerTransfer` or `pointerFinalize`, and you should not wrap them in an automatic retry. Reads are free to retry; a read during an update or churn can throw `CloseGroupShortfallException`.

```kotlin
val client = AntdClient.createRest()
val owner = client.pointerKeys().first()            // a pointer this daemon can write

val v1 = client.dataPutPublic("version 1".toByteArray()).address
val v2 = client.dataPutPublic("version 2".toByteArray()).address

client.pointerCreate(owner, v1)                     // pays; AlreadyExistsException if it exists
client.pointerUpdate(owner, v2)                     // pays again; counter 1
val target = client.pointerResolve(owner).target    // == v2
val finality = client.pointerFinality(owner)
println("${finality.status.wire}: ${finality.answered}/${finality.group} peers answered")
```

| Method | Description |
|---|---|
| `pointerKeys()` | The addresses of the pointers this daemon holds owner keys for, so can write |
| `pointerCreate(owner, target, kind = CHUNK)` | Create a pointer, paid by the daemon wallet. Returns `PointerWriteResult` (`address`, `stateId`, `counter`). `AlreadyExistsException` if it exists, refused before paying |
| `pointerUpdate(owner, target, kind = CHUNK)` | Point a pointer at a new target, paid by the daemon wallet; creates it if it does not exist. `kind` is `PointerKind.CHUNK` or `PointerKind.POINTER` (a forwarding the owner can still change). `PointerFinalException` once transferred |
| `pointerTransfer(owner, recipient)` | Hand a pointer over for good to the recipient's pointer, which must exist: readers of the address are redirected there. Irreversible. Returns `PointerTransferResult` with the close group's `finality` (null, with `finalityError`, when that check failed; the transfer still stands) |
| `pointerGet(address)` | Read a pointer: `PointerRecord` (`counter`, `target`, `kind` / `kindTag`, `isFinal`, `transferredTo`, the owner's public key). `NotFoundException` if there is none |
| `pointerResolve(address)` | Follow a chain of pointers (forwardings and transfers) to the `PointerTarget` at its end |
| `pointerFinality(address)` | Ask the whole close group where a pointer stands: `PointerFinality` whose `status` is `Open`, `Settling`, `Unconfirmed`, `Final`, `Forked` or `Unknown(wire)` for a status a newer daemon adds. Check `isFinal` before relying on a transfer |
| `pointerController(address)` | Follow transfers to the pointer whose owner now decides: `PointerController` |
| `pointerPrepare(owner, op, includeSignedQuotes = false)` | External signer: the daemon signs `PointerOp.Create`, `Update` or `Transfer` with its key and quotes it. Returns `PointerPrepareResult` (wave-batch `payments` for `payForQuotes()`). Needs no daemon wallet. Other writes to the pointer throw `ConflictException` until it is finalized or expires (one hour) |
| `pointerFinalize(uploadId, txHashes)` | External signer: store the prepared write once paid. A write that falls short after payment throws `CloseGroupShortfallException` with `retryable == true`: repeat the same call (same `uploadId`) to store it against the same payment. Bound that loop |

Counters are `ULong`. The daemon sends them as decimal strings in both transports because a final state (a transfer or a freeze) sits at 2^64-1 (`PointerRecord.FINAL_COUNTER`), past what a JSON number keeps exactly in several languages. A counter that is not ASCII decimal digits fitting a u64 throws `InternalException`; it never reads as 0. Unset values (the finality `counter`, `state`, `majority`, `transferredTo`) are `null` on both transports: REST sends `null`, gRPC sends `""` or an absent message.

See `examples/src/main/kotlin/com/autonomi/examples/Example08Pointers.kt` for a runnable round trip.

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
| `PointerFinalException` | 409 (`code: "POINTER_FINAL"`) | FAILED_PRECONDITION + `x-antd-error-code: POINTER_FINAL` | The pointer is transferred or frozen; nothing can change it. Refused before paying |
| `PointerForkedException` | 409 (`code: "POINTER_FORKED"`) | FAILED_PRECONDITION + `x-antd-error-code: POINTER_FORKED` | The owner signed two final states and no majority holds either (extends `ForkException`) |
| `ConflictException` | 409 (`code: "CONFLICT"`) | ABORTED + `x-antd-error-code: CONFLICT` | A pointer write while a prepared write to it awaits payment, or an update that lost to a newer state |
| `CloseGroupShortfallException` | 503 (`code: "CLOSE_GROUP_SHORTFALL"`) | UNAVAILABLE + `x-antd-error-code: CLOSE_GROUP_SHORTFALL` | Too few of the close group answered or stored. `retryable` is true only for a pointer finalize that kept the paid state |

The last four share an HTTP status or gRPC code with older errors, so the clients tell them apart by the daemon's `code`: from the REST error body, and over gRPC from the `x-antd-error-code` trailer, trusted only when it agrees with the status code (a FAILED_PRECONDITION without the tag is still a `PaymentException`; an UNAVAILABLE without it is still a `NetworkException`). The gRPC mapping applies to every call, not only pointers: `CLOSE_GROUP_SHORTFALL` can come from any store or fetch. Over gRPC, `retryable` is read from the daemon's closing `(paid attempt retained…)` hint.

Both clients follow this table: every `AntdGrpcClient` method maps a failed gRPC status to the exception type in the same row, so a `catch (e: NotFoundException)` works unchanged whichever client you construct, and raw `io.grpc.StatusException` / `StatusRuntimeException` never escape. The mapping is not one-to-one everywhere, because gRPC carries less detail than HTTP: the daemon reports both an unreachable network (REST 502) and a service-unavailable error (REST 503) as gRPC UNAVAILABLE, so a service-unavailable error throws `ServiceUnavailableException` over REST but `NetworkException` over gRPC; code that must handle it on both transports should catch both. A gRPC status with no row here (e.g. DEADLINE_EXCEEDED) throws a plain `AntdException` whose `statusCode` is the gRPC code number.

### Partial uploads

An external-signer finalize (`finalizeUpload`, `finalizeMerkleUpload`, `finalizeChunkUpload`) can fail *after* the wallet has paid: some chunks store, others miss quorum after the daemon's own retries. That surfaces as `PartialUploadException` carrying `chunksStored` / `chunksFailed` / `totalChunks` and two flags, `retryable` and `retentionKnown` (`retryable` implies `retentionKnown`). The on-chain payment persists and the stored chunks stay on the network; the flags say how to finish:

- **`retryable`** — the daemon kept the paid attempt under the same `uploadId`. Call the **same** finalize method again with the same `uploadId` and payment artefacts to store the remainder against the same payment — no re-prepare, no second signature, no double payment. Bound that loop: a persistent failure throws on every call, so cap the attempts and treat a `chunksFailed` that stops shrinking as stuck. The retained attempt expires with the daemon's pending-upload TTL.
- **`retentionKnown && !retryable`** — the daemon confirmed it kept nothing (e.g. a merkle finalize with deliberately unpaid batches). Re-prepare the same content; already-stored chunks are skipped, so the retry pays only for the remainder.
- **`!retentionKnown`** — retention is unknown, and the daemon may still hold the paid attempt: it records the resume handle before it returns the error. Stop automatic recovery, keep the `uploadId` and the original payment artefacts (tx hashes / quote data), and reconcile before re-preparing or paying again. Never pay again on this signal alone. Daemons older than 0.14.0 never send `retryable`, so their REST partial uploads always read as unknown.

`PartialUploadException` extends `NetworkException` because the daemon reports it as a 502, so existing `catch (e: NetworkException)` blocks keep working; narrow with `is PartialUploadException` to read the counts and flags. It is not a `ForkException`: over gRPC a partial upload's ABORTED used to map to `ForkException`, and around a finalize the daemon sends ABORTED only for PARTIAL_UPLOAD (its other ABORTED, a pointer `CONFLICT`, is tagged and maps to `ConflictException`), so code that caught `ForkException` around a gRPC finalize should catch `PartialUploadException` instead.

Over gRPC an ABORTED status maps to `PartialUploadException` only when its message starts with the daemon's fixed `Partial upload:` prefix (anchored, as in antd-rust); one tagged `CONFLICT` is a `ConflictException`, and any other ABORTED stays a `ForkException`. `retentionKnown` is true only when the message starts with the count layout (`Partial upload: S/T chunks stored, F failed after retries: <reason> (<hint>)`), all three counts convert to a `Long`, and the message ends with one of the daemon's two closing hints: `(paid attempt retained…)` sets `retryable`, and `(stored chunks persist; re-prepare the same content…)` means the daemon confirmed it kept nothing (daemons older than 0.14.0 write only this one). If the layout does not match or any count fails to convert (e.g. one past `Long.MAX_VALUE`), all three counts read as zero and both flags as false, even if a hint is present. Readable counts with a missing, truncated or unrecognised hint, or text after it, keep the counts, but both flags stay false: retention is unknown, so stop and reconcile rather than re-prepare.

Over REST, each count is read only from a JSON number holding a non-negative integer; a quoted number, a negative, fractional or out-of-range number, an array or an object reads as zero. `retentionKnown` is true when the body's `retryable` is a JSON boolean (`true` or `false`), and `retryable` only when it is the literal `true`; missing, `null`, a quoted `"true"`, a number, an array or an object reads as unknown and not retryable. A non-string `code` falls back to the plain `NetworkException`, and the error mapper never throws on a malformed body.

See `finalizeWithRetry` in `examples/src/main/kotlin/com/autonomi/examples/Example07ExternalSigner.kt` for a bounded retry loop that rethrows the original `PartialUploadException` whenever it stops, and [`docs/external-signer-flow.md` §6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment) for the daemon-side contract.

## Upgrading: pointer API

- `IAntdClient` gains the ten `pointer*` methods. Both bundled clients implement them; a class of your own that implements `IAntdClient` (a test fake, say) must add them before it compiles again.
- Four new exception types: `PointerFinalException`, `PointerForkedException`, `ConflictException` and `CloseGroupShortfallException`. The exception classes are not sealed, so no `when` stops compiling. `ForkException` is now `open`, and `PointerForkedException` extends it.
- `CloseGroupShortfallException` is not only for pointers: a daemon with the pointer API reports a close group that fell short on any call (a chunk store, say) as `503 CLOSE_GROUP_SHORTFALL` / UNAVAILABLE with the tag. An older daemon sent a 500, read as `InternalException`.
- The gRPC client now reads each failed call's trailers (`StatusException.trailers`); nothing changes for statuses without the `x-antd-error-code` tag.

## Examples

Run individual examples:

```bash
./gradlew :examples:run --args="1"   # Connect
./gradlew :examples:run --args="2"   # Public Data
./gradlew :examples:run --args="all" # All examples except 8

# Pointers: pays for each write and needs a never-written owner the daemon
# holds the key for, so it runs only when asked for. ANTD_BASE_URL overrides
# the daemon URL (default http://localhost:8082).
ANTD_POINTER_OWNER=<hex> ./gradlew :examples:run --args="8"
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
├── examples/                     # 7 runnable examples
├── build.gradle.kts              # Root build config
└── settings.gradle.kts
```
