# C++ Quickstart

A comprehensive guide to using the Autonomi network with the C++ SDK.

## Setup

```bash
# Prerequisites
# - C++20 compiler (GCC 12+, Clang 15+, MSVC 2022+)
# - CMake 3.24+
# - antd daemon running (ant dev start)
```

Add to your `CMakeLists.txt`:

```cmake
include(FetchContent)

FetchContent_Declare(
    antd
    GIT_REPOSITORY https://github.com/WithAutonomi/ant-sdk.git
    GIT_TAG        main
    SOURCE_SUBDIR  antd-cpp
)
FetchContent_MakeAvailable(antd)

target_link_libraries(my_app PRIVATE antd::antd)
```

Or scaffold a new project:

```bash
ant dev init cpp --name my-project
```

## Connecting

```cpp
#include <antd/antd.hpp>

int main() {
    // REST transport (default)
    auto client = antd::Client::create();

    // Custom endpoint
    auto client2 = antd::Client::builder()
        .transport("rest")
        .base_url("http://localhost:8082")
        .timeout(std::chrono::seconds(30))
        .build();

    // gRPC transport
    auto client3 = antd::Client::builder()
        .transport("grpc")
        .target("localhost:50051")
        .build();

    return 0;
}
```

The client is synchronous. All methods block until the operation completes or throws.

## Health Check

```cpp
auto status = client.health();
std::println("Healthy: {}", status.ok);
std::println("Network: {}", status.network); // "local", "default", "alpha"
```

## Public Data

```cpp
#include <antd/antd.hpp>
#include <vector>
#include <string>

// Store
std::vector<uint8_t> payload(
    std::string_view("Hello, Autonomi!").begin(),
    std::string_view("Hello, Autonomi!").end()
);
auto result = client.data_put_public(payload);
std::println("Address: {}", result.address);
std::println("Cost: {} atto tokens", result.cost);

// Retrieve
auto data = client.data_get_public(result.address);
std::string text(data.begin(), data.end());
std::println("{}", text); // "Hello, Autonomi!"

// Cost estimation
auto cost = client.data_cost(payload);
std::println("Would cost: {} atto tokens", cost);
```

## Private Data

```cpp
// Store (self-encrypting)
std::vector<uint8_t> secret(
    std::string_view("secret message").begin(),
    std::string_view("secret message").end()
);
auto result = client.data_put_private(secret);
auto data_map = result.address; // Keep this secret!

// Retrieve (decrypt)
auto data = client.data_get_private(data_map);
std::string text(data.begin(), data.end());
std::println("{}", text);
```

## Files

```cpp
// Upload a file
auto result = client.file_upload_public("/path/to/file.txt");
std::println("File address: {}", result.address);

// Download a file
client.file_download_public(result.address, "/path/to/output.txt");

// Upload a directory
auto dir_result = client.dir_upload_public("/path/to/directory");

// Download a directory
client.dir_download_public(dir_result.address, "/path/to/output_dir");

// Cost estimation
auto cost = client.file_cost("/path/to/file.txt");
```

## Graph Entries (DAG Nodes)

```cpp
#include <antd/antd.hpp>
#include <random>

std::random_device rd;
std::mt19937 gen(rd());
std::uniform_int_distribution<uint8_t> dist(0, 255);

auto random_hex = [&](size_t bytes) {
    std::string hex;
    hex.reserve(bytes * 2);
    for (size_t i = 0; i < bytes; ++i)
        std::format_to(std::back_inserter(hex), "{:02x}", dist(gen));
    return hex;
};

auto key = random_hex(32);
auto content = random_hex(32);

// Create root node
auto result = client.graph_entry_put(
    key,
    {},        // parents
    content,
    {}         // descendants
);
std::println("Graph entry: {}", result.address);

// Read
auto entry = client.graph_entry_get(result.address);
std::println("Owner: {}", entry.owner);
std::println("Content: {}", entry.content);

// Check existence
bool exists = client.graph_entry_exists(result.address);
```

## Error Handling

```cpp
#include <antd/antd.hpp>

try {
    client.data_get_public("nonexistent");
} catch (const antd::NotFoundException&) {
    std::println("Not found");
} catch (const antd::PaymentError&) {
    std::println("Payment issue");
} catch (const antd::NetworkError&) {
    std::println("Network unreachable");
} catch (const antd::AntdError& e) {
    std::println("Error ({}): {}", e.status_code(), e.what());
}
```

Exception hierarchy (all inherit from `antd::AntdError`):

| Exception | HTTP Code | When |
|-----------|-----------|------|
| `antd::BadRequestError` | 400 | Invalid parameters |
| `antd::PaymentError` | 402 | Insufficient funds |
| `antd::NotFoundException` | 404 | Resource not found |
| `antd::AlreadyExistsError` | 409 | Duplicate creation |
| `antd::ForkError` | 409 | Version conflict |
| `antd::TooLargeError` | 413 | Payload too large |
| `antd::InternalError` | 500 | Server error |
| `antd::NetworkError` | 502 | Network unreachable |

## Examples

```bash
cd antd-cpp/examples
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

./build/01_connect
./build/02_data
./build/03_chunks
./build/04_files
./build/05_graph
./build/06_private
```

Or use the dev CLI:

```bash
ant dev example data -l cpp
ant dev example all -l cpp
```
