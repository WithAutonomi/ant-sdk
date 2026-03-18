# antd-java

Java SDK for the [antd](../antd/) daemon — the gateway to the Autonomi decentralized network.

Targets Java 17+ enterprise/ERP environments. Zero external dependencies — uses `java.net.http.HttpClient` (stdlib) with an internal JSON parser. Immutable data types only (Java records).

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
// Default: http://localhost:8080, 5 minute timeout
var client = new AntdClient();

// Custom URL
var client = new AntdClient("http://custom-host:9090");

// Custom URL and timeout
var client = new AntdClient("http://localhost:8080", Duration.ofSeconds(30));

// Custom HTTP client
var httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
var client = new AntdClient("http://localhost:8080", Duration.ofSeconds(30), httpClient);
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

### Graph Entries (DAG Nodes)

| Method | Description |
|--------|-------------|
| `graphEntryPut(secretKey, parents, content, descendants)` | Create entry |
| `graphEntryGet(address)` | Read entry |
| `graphEntryExists(address)` | Check if exists |
| `graphEntryCost(publicKey)` | Estimate creation cost |

### Files & Directories

| Method | Description |
|--------|-------------|
| `fileUploadPublic(path)` | Upload a file |
| `fileDownloadPublic(address, destPath)` | Download a file |
| `dirUploadPublic(path)` | Upload a directory |
| `dirDownloadPublic(address, destPath)` | Download a directory |
| `archiveGetPublic(address)` | Get archive manifest |
| `archivePutPublic(archive)` | Create archive manifest |
| `fileCost(path, isPublic, includeArchive)` | Estimate upload cost |

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
- `Example04GraphEntries` — Graph entry (DAG node) operations
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
