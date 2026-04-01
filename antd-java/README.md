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
            PutResult result = client.dataPutPublic("Hello, Autonomi!".getBytes());
            System.out.printf("Stored at %s (cost: %s atto)%n", result.address(), result.cost());

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
| `health()` | Check daemon status |

### Data (Immutable)

| Method | Description |
|--------|-------------|
| `dataPutPublic(data)` | Store public data |
| `dataGetPublic(address)` | Retrieve public data |
| `dataPutPrivate(data)` | Store encrypted private data |
| `dataGetPrivate(dataMap)` | Retrieve private data |
| `dataCost(data)` | Estimate storage cost |

### Chunks

| Method | Description |
|--------|-------------|
| `chunkPut(data)` | Store a raw chunk |
| `chunkGet(address)` | Retrieve a chunk |

### Files & Directories

| Method | Description |
|--------|-------------|
| `fileUploadPublic(path)` | Upload a file |
| `fileDownloadPublic(address, destPath)` | Download a file |
| `dirUploadPublic(path)` | Upload a directory |
| `dirDownloadPublic(address, destPath)` | Download a directory |
| `fileCost(path, isPublic)` | Estimate upload cost |

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
    CompletableFuture<PutResult> upload1 = client.dataPutPublicAsync("file1".getBytes());
    CompletableFuture<PutResult> upload2 = client.dataPutPublicAsync("file2".getBytes());

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
