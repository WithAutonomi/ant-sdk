# Java Quickstart

A comprehensive guide to using the Autonomi network with the Java SDK.

## Setup

```bash
# Prerequisites
# - Java 21+: https://adoptium.net/
# - antd daemon running (ant dev start)
```

**Gradle** (`build.gradle.kts`):

```kotlin
dependencies {
    implementation("com.autonomi:antd-java:0.1.0")
}
```

**Maven** (`pom.xml`):

```xml
<dependency>
    <groupId>com.autonomi</groupId>
    <artifactId>antd-java</artifactId>
    <version>0.1.0</version>
</dependency>
```

Or scaffold a new project:

```bash
ant dev init java --name my-project
```

## Connecting

```java
import com.autonomi.antd.AntdClient;

// REST transport (default) — implements AutoCloseable
try (var client = AntdClient.create()) {
    // use client
}

// Custom endpoint
try (var client = AntdClient.builder()
        .transport("rest")
        .baseUrl("http://localhost:8082")
        .timeout(Duration.ofSeconds(30))
        .build()) {
    // use client
}

// gRPC transport
try (var client = AntdClient.builder()
        .transport("grpc")
        .target("localhost:50051")
        .build()) {
    // use client
}
```

`AntdClient` implements `AutoCloseable`. Always use try-with-resources to ensure proper cleanup.

## Health Check

```java
var status = client.health();
System.out.println("Healthy: " + status.ok());
System.out.println("Network: " + status.network()); // "local", "default", "alpha"
```

Response types are Java records with accessor methods.

## Public Data

```java
import java.nio.charset.StandardCharsets;

// Store
byte[] payload = "Hello, Autonomi!".getBytes(StandardCharsets.UTF_8);
var result = client.dataPutPublic(payload);
System.out.println("Address: " + result.address());
System.out.println("Cost: " + result.cost() + " atto tokens");

// Retrieve
byte[] data = client.dataGetPublic(result.address());
System.out.println(new String(data, StandardCharsets.UTF_8)); // "Hello, Autonomi!"

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
UploadCostEstimate est = client.dataCost(payload);
System.out.println("Estimate: " + est.fileSize() + " bytes in " + est.chunkCount()
    + " chunks, " + est.cost() + " atto, gas " + est.estimatedGasCostWei()
    + " wei, mode " + est.paymentMode());
```

## Private Data

```java
// Store (self-encrypting)
byte[] secret = "secret message".getBytes(StandardCharsets.UTF_8);
var result = client.dataPutPrivate(secret);
String dataMap = result.address(); // Keep this secret!

// Retrieve (decrypt)
byte[] data = client.dataGetPrivate(dataMap);
System.out.println(new String(data, StandardCharsets.UTF_8));
```

## Files

```java
// Upload a file
var result = client.fileUploadPublic("/path/to/file.txt");
System.out.println("File address: " + result.address());

// Download a file
client.fileDownloadPublic(result.address(), "/path/to/output.txt");

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
UploadCostEstimate est = client.fileCost("/path/to/file.txt");
```


## Error Handling

```java
import com.autonomi.antd.*;

try {
    client.dataGetPublic("nonexistent");
} catch (NotFoundException e) {
    System.out.println("Not found");
} catch (PaymentException e) {
    System.out.println("Payment issue");
} catch (NetworkException e) {
    System.out.println("Network unreachable");
} catch (AntdException e) {
    System.out.println("Error (" + e.statusCode() + "): " + e.getMessage());
}
```

Exception hierarchy (all extend `AntdException`, which extends `RuntimeException`):

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
cd antd-java

# Gradle
./gradlew run --args="1"    # Connect
./gradlew run --args="2"    # Public data
./gradlew run --args="3"    # Chunks
./gradlew run --args="4"    # Files
./gradlew run --args="6"    # Private data
./gradlew run --args="all"  # Run all examples

# Maven
mvn exec:java -Dexec.args="1"
```

Or use the dev CLI:

```bash
ant dev example data -l java
ant dev example all -l java
```
