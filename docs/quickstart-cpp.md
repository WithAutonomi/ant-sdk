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

// Cost estimation — returns size, chunks, gas, and payment mode
auto est = client.data_cost(payload);
std::println("Estimate: {} bytes in {} chunks, {} atto, gas {} wei, mode {}",
             est.file_size, est.chunk_count, est.cost, est.estimated_gas_cost_wei, est.payment_mode);
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

// Cost estimation — returns UploadCostEstimate with size, chunks, gas, payment mode
auto est = client.file_cost("/path/to/file.txt");
```

## Pointers

A pointer is an owner-signed address you can move to new data. antd signs with the owner keys it loaded at startup (`antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`), so `owner` is the pointer's address, never a key. Every create, update and transfer pays (about the price of one chunk) and is never retried; reads are free. A transfer hands the pointer over to another pointer for good. Needs the first antd release with pointers (after 0.15.0). Walk-through: [Tutorial: Point at a Public File and Update It](tutorial-pointers.md).

```cpp
const std::string owner = client.pointer_keys().at(0).address;  // a pointer antd can write

auto bytes = [](std::string s) { return std::vector<uint8_t>(s.begin(), s.end()); };
auto v1 = client.data_put_public(bytes("version 1"));
auto v2 = client.data_put_public(bytes("version 2"));

client.pointer_create(owner, v1.address);            // pays; counter 0
auto w = client.pointer_update(owner, v2.address);   // pays again; counter 1
auto target = client.pointer_resolve(owner).target;  // == v2.address (free)

auto f = client.pointer_finality(owner);             // free
if (f.status == antd::PointerFinalityStatus::Open) {
    std::println("open at counter {}", f.counter.value_or(0));
}
```

Counters are `std::uint64_t`; unset values are `std::optional`. `pointer_transfer`, `pointer_get`, `pointer_controller`, `pointer_prepare` and `pointer_finalize` complete the set, on `GrpcClient` too.

Runnable example: `antd-cpp/examples/08-pointers.cpp`. Set `ANTD_POINTER_OWNER` to an address the daemon holds a key for, one it has not written yet (each run creates the pointer and pays for its writes), and `ANTD_BASE_URL` for a daemon other than `http://localhost:8082`:

```bash
cd antd-cpp
cmake -S . -B build && cmake --build build
ANTD_POINTER_OWNER=<address> ./build/08-pointers
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
./build/06_private
```

Or use the dev CLI:

```bash
ant dev example data -l cpp
ant dev example all -l cpp
```
