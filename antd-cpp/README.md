# antd-cpp

C++ SDK for the [antd](../antd/) daemon — the gateway to the Autonomi decentralized network.

## Installation

### CMake FetchContent (recommended)

Add to your `CMakeLists.txt`:

```cmake
include(FetchContent)
FetchContent_Declare(
    antd-cpp
    GIT_REPOSITORY https://github.com/WithAutonomi/ant-sdk.git
    SOURCE_SUBDIR  antd-cpp
)
FetchContent_MakeAvailable(antd-cpp)

target_link_libraries(your_target PRIVATE antd)
```

All dependencies (nlohmann_json, cpp-httplib) are fetched automatically.

### Manual

```bash
git clone https://github.com/WithAutonomi/ant-sdk.git
cd ant-sdk/antd-cpp
cmake -B build
cmake --build build
```

## Quick Start

```cpp
#include "antd/antd.hpp"
#include <iostream>

int main() {
    antd::Client client;  // defaults to http://localhost:8082

    // Check daemon health
    auto health = client.health();
    std::cout << "OK: " << health.ok << ", Network: " << health.network << "\n";

    // Store data
    std::string msg = "Hello, Autonomi!";
    std::vector<uint8_t> data(msg.begin(), msg.end());
    auto result = client.data_put_public(data);
    std::cout << "Stored at " << result.address << " (cost: " << result.cost << " atto)\n";

    // Retrieve data
    auto retrieved = client.data_get_public(result.address);
    std::string text(retrieved.begin(), retrieved.end());
    std::cout << "Retrieved: " << text << "\n";
}
```

## Async Usage

The SDK ships an `AsyncClient` that wraps every synchronous method in
`std::async(std::launch::async, ...)` and returns a `std::future<T>`.
No additional dependencies are required — only C++20 `<future>`.

```cpp
#include "antd/antd.hpp"
#include <iostream>

int main() {
    antd::AsyncClient client;  // defaults to http://localhost:8082

    // Fire off two requests concurrently
    auto health_future = client.health();
    auto cost_future   = client.data_cost({0x01, 0x02, 0x03});

    // Block until the health check completes
    auto health = health_future.get();
    std::cout << "OK: " << health.ok << "\n";

    // Block until the cost estimate completes — returns UploadCostEstimate
    auto est = cost_future.get();
    std::cout << "Estimate: " << est.file_size << " bytes in " << est.chunk_count
              << " chunks, " << est.cost << " atto, gas " << est.estimated_gas_cost_wei
              << " wei, mode " << est.payment_mode << "\n";
}
```

### Waiting with a timeout

```cpp
auto future = client.data_put_public(data);

// Wait up to 10 seconds
if (future.wait_for(std::chrono::seconds(10)) == std::future_status::ready) {
    auto result = future.get();
    std::cout << "Stored at " << result.address << "\n";
} else {
    std::cerr << "Upload still in progress...\n";
}
```

### Error handling

Exceptions thrown by the underlying synchronous client propagate through the
future. Calling `.get()` on a failed future rethrows the original exception:

```cpp
try {
    auto data = client.data_get_public("bad-address").get();
} catch (const antd::NotFoundError& e) {
    std::cerr << "Not found\n";
} catch (const antd::AntdError& e) {
    std::cerr << "Error " << e.status_code << ": " << e.what() << "\n";
}
```

### Fan-out pattern

```cpp
// Launch many downloads in parallel
std::vector<std::future<std::vector<uint8_t>>> futures;
for (const auto& addr : addresses) {
    futures.push_back(client.data_get_public(addr));
}

// Collect results
for (auto& f : futures) {
    auto data = f.get();  // blocks until this particular download finishes
    process(data);
}
```

## gRPC Transport

The SDK includes a `GrpcClient` class that provides the same methods as the
REST `Client`, but communicates over gRPC. This can offer lower latency and
better streaming support for large data transfers.

### Building with gRPC

Enable the gRPC target by passing `-DANTD_BUILD_GRPC=ON` to CMake:

```bash
cmake -B build -DANTD_BUILD_GRPC=ON
cmake --build build
```

This requires `protoc`, `grpc_cpp_plugin`, and a gRPC installation (e.g. via
`vcpkg`, `apt install libgrpc++-dev`, or building from source). The CMake
configuration will automatically run `protoc` against the proto files in
`antd/proto/antd/v1/` and generate the C++ stubs.

Link against the `antd_grpc` target instead of (or in addition to) `antd`:

```cmake
target_link_libraries(your_target PRIVATE antd_grpc)
```

### Usage

```cpp
#include "antd/grpc_client.hpp"
#include <iostream>

int main() {
    antd::GrpcClient client;  // defaults to localhost:50051

    // Custom target
    // antd::GrpcClient client("my-host:50051");

    auto health = client.health();
    std::cout << "OK: " << health.ok << ", Network: " << health.network << "\n";

    std::string msg = "Hello via gRPC!";
    std::vector<uint8_t> data(msg.begin(), msg.end());
    auto result = client.data_put_public(data);
    std::cout << "Stored at " << result.address << "\n";

    auto retrieved = client.data_get_public(result.address);
    std::string text(retrieved.begin(), retrieved.end());
    std::cout << "Retrieved: " << text << "\n";
}
```

The `GrpcClient` throws the same `antd::AntdError` hierarchy as the REST
client, translating gRPC status codes to the appropriate error subclass.

> **Note:** Wallet operations (address, balance, approve) and payment_mode are available via REST only.

## Prerequisites

- C++20 compiler (GCC 10+, Clang 10+, MSVC 19.29+)
- CMake 3.14+
- A running antd daemon. Start it with:

```bash
ant dev start
```

## Configuration

```cpp
// Default: http://localhost:8082, 5 minute timeout
antd::Client client;

// Custom URL
antd::Client client("http://custom-host:9090");

// Custom URL and timeout (seconds)
antd::Client client("http://localhost:8082", 30);
```

## API Reference

All methods throw `antd::AntdError` (or a subclass) on failure.

### Health

| Method | Description |
|--------|-------------|
| `health()` | Check daemon status |

### Data (Immutable)

| Method | Description |
|--------|-------------|
| `data_put_public(data)` | Store public data |
| `data_get_public(address)` | Retrieve public data |
| `data_put_private(data)` | Store encrypted private data |
| `data_get_private(data_map)` | Retrieve private data |
| `data_cost(data)` | Estimate storage cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

### Chunks

| Method | Description |
|--------|-------------|
| `chunk_put(data)` | Store a raw chunk |
| `chunk_get(address)` | Retrieve a chunk |

### Files & Directories

| Method | Description |
|--------|-------------|
| `file_upload_public(path)` | Upload a file |
| `file_download_public(address, dest_path)` | Download a file |
| `dir_upload_public(path)` | Upload a directory |
| `dir_download_public(address, dest_path)` | Download a directory |
| `file_cost(path, is_public)` | Estimate upload cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

## Error Handling

All errors inherit from `antd::AntdError` (which inherits from `std::runtime_error`), so you can catch them at any granularity:

```cpp
try {
    auto data = client.data_get_public(address);
} catch (const antd::NotFoundError& e) {
    std::cerr << "Not found on network\n";
} catch (const antd::PaymentError& e) {
    std::cerr << "Insufficient funds\n";
} catch (const antd::AntdError& e) {
    std::cerr << "antd error " << e.status_code << ": " << e.what() << "\n";
}
```

| Error Type | HTTP Status | When |
|-----------|-------------|------|
| `BadRequestError` | 400 | Invalid parameters |
| `PaymentError` | 402 | Insufficient funds |
| `NotFoundError` | 404 | Resource not found |
| `AlreadyExistsError` | 409 | Resource exists |
| `ForkError` | 409 | Version conflict |
| `TooLargeError` | 413 | Payload too large |
| `InternalError` | 500 | Server error |
| `NetworkError` | 502 | Network unreachable |

## Building

```bash
cmake -B build
cmake --build build

# Run tests
cd build && ctest --output-on-failure

# Build without examples
cmake -B build -DANTD_BUILD_EXAMPLES=OFF
```

## Examples

See the [examples/](examples/) directory:

- `01-connect` — Health check
- `02-data` — Public data storage and retrieval
- `03-chunks` — Raw chunk operations
- `04-files` — File and directory upload/download
- `06-private-data` — Private encrypted data storage
