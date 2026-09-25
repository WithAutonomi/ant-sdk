# antd-java

Java SDK for the [antd](../antd/) daemon — the gateway to the Autonomi decentralized network.

Targets Java 17+ enterprise/ERP environments. Supports both REST (`java.net.http.HttpClient` with an internal JSON parser, zero external deps) and gRPC (`io.grpc`) transports. Immutable data types only (Java records).

## Installation

### Gradle (Kotlin DSL)

```kotlin
dependencies {
    implementation("com.autonomi:antd-java:0.1.0")
}
```

### Gradle (Groovy DSL)

```groovy
dependencies {
    implementation 'com.autonomi:antd-java:0.1.0'
}
```

### Maven

```xml
<dependency>
    <groupId>com.autonomi</groupId>
    <artifactId>antd-java</artifactId>
    <version>0.1.0</version>
</dependency>
```

## Quick Start

```java
import com.autonomi.antd.AntdClient;
import com.autonomi.antd.models.*;

public class QuickStart {
    public static void main(String[] args) {
        try (var client = new AntdClient()) {
            // Check daemon health
            HealthStatus health = client.health();
            System.out.println("OK: " + health.ok() + ", Network: " + health.network());

            // Store data
            DataPutPublicResult result = client.dataPutPublic("Hello, Autonomi!".getBytes());
            System.out.printf("Stored at %s (chunks: %d)%n", result.address(), result.chunksStored());

            // Retrieve data
            byte[] data = client.dataGetPublic(result.address());
            System.out.println("Retrieved: " + new String(data));
        }
    }
}
```

## Prerequisites

The antd daemon must be running. Start it with:

```bash
ant dev start
```

## Configuration

```java
// Default: http://localhost:8082, 5 minute timeout
var client = new AntdClient();

// Custom URL
var client = new AntdClient("http://custom-host:9090");

// Custom URL and timeout
var client = new AntdClient("http://localhost:8082", Duration.ofSeconds(30));

// Custom HTTP client
var httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
var client = new AntdClient("http://localhost:8082", Duration.ofSeconds(30), httpClient);
```

## API Reference

All methods throw `AntdException` (or a typed subclass) on failure.

### Health

| Method | Description |
|--------|-------------|
| `health()` | Check daemon status — returns `HealthStatus` carrying antd version, EVM network, uptime, build commit, and payment contract addresses (antd ≥ 0.4.0) |

### Data (Immutable)

| Method | Description |
|--------|-------------|
| `dataPutPublic(data, paymentMode)` | Store public data — returns `DataPutPublicResult` (DataMap stored on-network) |
| `dataGetPublic(address)` | Retrieve public data by address |
| `dataPut(data, paymentMode)` | Store encrypted private data — returns `DataPutResult` (DataMap returned to caller) |
| `dataGet(dataMap)` | Retrieve private data using a caller-held DataMap |
| `dataCost(data, paymentMode)` | Estimate storage cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

### Chunks

| Method | Description |
|--------|-------------|
| `chunkPut(data)` | Store a raw chunk |
| `chunkGet(address)` | Retrieve a chunk |

### Files

| Method | Description |
|--------|-------------|
| `filePut(path, paymentMode)` | Upload a file privately — returns `FilePutResult` (DataMap returned to caller) |
| `fileGet(dataMap, destPath)` | Download a private file using a caller-held DataMap |
| `filePutPublic(path, paymentMode)` | Upload a file publicly — returns `FilePutPublicResult` (DataMap stored on-network) |
| `fileGetPublic(address, destPath)` | Download a public file by address |
| `fileCost(path, isPublic, paymentMode)` | Estimate upload cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

## Async Usage

The `AsyncAntdClient` provides non-blocking variants of every method, returning `CompletableFuture<T>`. It uses `HttpClient.sendAsync()` internally — no thread-pool wrappers around blocking calls.

```java
import com.autonomi.antd.AsyncAntdClient;
import com.autonomi.antd.models.*;

try (var client = new AsyncAntdClient()) {
    // Fire-and-forget style
    client.healthAsync()
          .thenAccept(h -> System.out.println("Network: " + h.network()));

    // Chain operations
    client.dataPutPublicAsync("Hello, async!".getBytes())
          .thenCompose(result -> client.dataGetPublicAsync(result.address()))
          .thenAccept(data -> System.out.println("Got: " + new String(data)))
          .join(); // block only at the end

    // Parallel uploads
    CompletableFuture<DataPutPublicResult> upload1 = client.dataPutPublicAsync("file1".getBytes());
    CompletableFuture<DataPutPublicResult> upload2 = client.dataPutPublicAsync("file2".getBytes());

    CompletableFuture.allOf(upload1, upload2).join();
    System.out.printf("Addresses: %s, %s%n", upload1.join().address(), upload2.join().address());

    // Error handling
    client.dataGetPublicAsync("bad-address")
          .exceptionally(ex -> {
              System.out.println("Failed: " + ex.getCause().getMessage());
              return null;
          })
          .join();
}
```

The async client has the same constructors as `AntdClient`:

```java
var client = new AsyncAntdClient();                                          // defaults
var client = new AsyncAntdClient("http://custom:9090");                      // custom URL
var client = new AsyncAntdClient("http://localhost:8082", Duration.ofSeconds(30)); // custom timeout
```

All methods follow the naming convention `methodNameAsync()` and return `CompletableFuture<T>` where `T` matches the sync return type. Void methods return `CompletableFuture<Void>`.

## gRPC Transport

The `GrpcAntdClient` provides an alternative transport using gRPC instead of REST. It implements the same 15 methods with identical signatures, so switching transports requires only changing the constructor.

```java
import com.autonomi.antd.GrpcAntdClient;
import com.autonomi.antd.models.*;

// Default: localhost:50051, plaintext
try (var client = new GrpcAntdClient()) {
    HealthStatus health = client.health();
    System.out.println("OK: " + health.ok() + ", Network: " + health.network());

    // Same API as AntdClient
    PutResult result = client.dataPutPublic("Hello via gRPC!".getBytes());
    byte[] data = client.dataGetPublic(result.address());
    System.out.println("Retrieved: " + new String(data));
}

// Custom target
try (var client = new GrpcAntdClient("myhost:50051")) {
    client.health();
}
```

The gRPC client uses `io.grpc` blocking stubs and maps gRPC status codes to the same `AntdException` hierarchy.

> **Note:** Wallet operations (address, balance, approve) and payment_mode are available via REST only.

| gRPC Status | Exception Type |
|-------------|---------------|
| `INVALID_ARGUMENT` | `BadRequestException` |
| `NOT_FOUND` | `NotFoundException` |
| `ALREADY_EXISTS` | `AlreadyExistsException` |
| `FAILED_PRECONDITION` | `PaymentException` |
| `RESOURCE_EXHAUSTED` | `TooLargeException` |
| `INTERNAL` | `InternalException` |
| `UNAVAILABLE` | `NetworkException` |
| `ABORTED` whose message starts with `Partial upload:` | `PartialUploadException` (counts and `retryable` parsed from the status message); any other `ABORTED` maps to the generic `AntdException` |

### Proto compilation

The build uses the [protobuf Gradle plugin](https://github.com/google/protobuf-gradle-plugin) to compile `.proto` files from `../antd/proto` and generate Java/gRPC stubs automatically:

```bash
./gradlew generateProto   # generate stubs (also runs as part of build)
./gradlew build           # full build including proto compilation
```

### Additional dependencies

The gRPC transport adds the following dependencies (managed in `build.gradle.kts`):

- `io.grpc:grpc-netty-shaded` — Netty-based gRPC transport (shaded to avoid conflicts)
- `io.grpc:grpc-protobuf` — Protobuf marshalling for gRPC
- `io.grpc:grpc-stub` — Stub classes for gRPC
- `com.google.protobuf:protobuf-java` — Protocol Buffers runtime

## Error Handling

All errors are subtypes of `AntdException`, which extends `RuntimeException`. Use standard Java exception handling:

```java
try {
    byte[] data = client.dataGetPublic(address);
} catch (NotFoundException e) {
    System.out.println("Data not found on network");
} catch (PaymentException e) {
    System.out.println("Insufficient funds");
} catch (AntdException e) {
    System.out.println("Error " + e.getStatusCode() + ": " + e.getMessage());
}
```

| Exception Type | HTTP Status | When |
|---------------|-------------|------|
| `BadRequestException` | 400 | Invalid parameters |
| `PaymentException` | 402 | Insufficient funds |
| `NotFoundException` | 404 | Resource not found |
| `AlreadyExistsException` | 409 | Resource exists |
| `ForkException` | 409 | Version conflict |
| `TooLargeException` | 413 | Payload too large |
| `InternalException` | 500 | Server error |
| `NetworkException` | 502 | Network unreachable |
| `PartialUploadException` | 502 (`code: PARTIAL_UPLOAD`) | Finalize stored some chunks but not all — see below |

### Partial uploads

A `finalizeUpload` / `finalizeMerkleUpload` / `finalizeChunkUpload` where some chunks stayed unstored after the daemon's retries throws `PartialUploadException` (a subclass of `NetworkException`, so existing `catch (NetworkException e)` blocks keep working) with `getChunksStored()` / `getChunksFailed()` / `getTotalChunks()` and an `isRetryable()` flag. The on-chain payment persists and the stored chunks stay on the network.

- `isRetryable() == true` (sent by antd ≥ 0.14.0) means the daemon kept the paid attempt under the same `upload_id`: call the **same** finalize method again with the same arguments to store the remainder against the same payment — no re-prepare, no second signature, no double payment. Bound that loop: cap the attempts, and treat a `getChunksFailed()` that stops shrinking as stuck.
- `isRetryable() == false` — an older daemon (which never sends the flag, so it defaults to `false`), or a merkle finalize with deliberately unpaid batches — means nothing was retained: re-preparing the same content skips already-stored chunks, so a retry pays only for the remainder.

```java
try {
    result = client.finalizeUpload(uploadId, txHashes);
} catch (PartialUploadException e) {
    if (e.isRetryable()) {
        // same upload_id, same payment: retry finalizeUpload(uploadId, txHashes) with a cap
    } else {
        // re-prepare the same content; already-stored chunks are skipped
    }
}
```

Over REST the counts and flag come from the structured error body; over gRPC (status `ABORTED` whose message starts with the daemon's fixed `Partial upload:` prefix) they are parsed from the status message. Counts and the "paid attempt retained" hint are parsed independently, so a message that starts with the prefix but has unparseable counts yields zero counts while `isRetryable()` still follows the hint. The match is anchored at the start of the message, as in antd-rust: an `ABORTED` that does not start with the prefix, including one that merely quotes it further in, is not a partial upload and maps to the generic `AntdException`. On the REST side a malformed error body never escapes as a parse error: a count that is not a JSON number, or a `retryable` that is not a JSON boolean, reads as zero / `false`, and a `code` that is not the string `PARTIAL_UPLOAD` keeps the plain `NetworkException`. See `finalizeWithRetry` in [`examples/.../Example07ExternalSigner.java`](examples/src/main/java/com/autonomi/examples/Example07ExternalSigner.java) for a bounded retry helper, and [`docs/external-signer-flow.md` §6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment) for the daemon-side contract.

## Examples

See the [examples/](examples/) directory:

- `Example01Connect` — Health check
- `Example02PublicData` — Public data storage and retrieval
- `Example03Files` — File upload and download
- `Example05ErrorHandling` — Typed exception handling
- `Example06PrivateData` — Private (encrypted) data storage

## Building

```bash
./gradlew build
```

## Testing

```bash
./gradlew test
```
