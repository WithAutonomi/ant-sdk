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
    std::cout << "Stored at " << result.address << " (chunks: " << result.chunks_stored << ")\n";

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
| `data_put_public(data, payment_mode)` | Store public data — returns `DataPutPublicResult` (DataMap stored on-network) |
| `data_get_public(address)` | Retrieve public data by address |
| `data_put(data, payment_mode)` | Store encrypted private data — returns `DataPutResult` (DataMap returned to caller) |
| `data_get(data_map)` | Retrieve private data using a caller-held DataMap |
| `data_cost(data, payment_mode)` | Estimate storage cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

### Chunks

| Method | Description |
|--------|-------------|
| `chunk_put(data)` | Store a raw chunk |
| `chunk_get(address)` | Retrieve a chunk |

### Files

| Method | Description |
|--------|-------------|
| `file_put(path, payment_mode)` | Upload a file privately — returns `FilePutResult` (DataMap returned to caller) |
| `file_get(data_map, dest_path)` | Download a private file using a caller-held DataMap |
| `file_put_public(path, payment_mode)` | Upload a file publicly — returns `FilePutPublicResult` (DataMap stored on-network) |
| `file_get_public(address, dest_path)` | Download a public file by address |
| `file_cost(path, is_public, payment_mode)` | Estimate upload cost — returns `UploadCostEstimate` with size, chunks, gas, payment mode |

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
| `PartialUploadError` | 502 (`code: PARTIAL_UPLOAD`) | Finalize paid and stored some chunks, others missed quorum — see below |

### Partial uploads

`finalize_upload` / `finalize_merkle_upload` can fail *after* the wallet has
paid: some chunks store, others miss quorum after the daemon's own retries.
That surfaces as `antd::PartialUploadError` (HTTP 502 with
`code: "PARTIAL_UPLOAD"`; gRPC `ABORTED` whose message starts with
`Partial upload:`, where the fields are parsed from the status message). The
gRPC match is anchored at the start of the message: any other `ABORTED`,
including one that only quotes `Partial upload:` further into its text, stays
a plain `AntdError`. Over REST, a count of the wrong JSON type reads as zero,
and a body whose `code` is not the string `PARTIAL_UPLOAD` keeps the plain
status mapping; the error mapping never throws anything but an `AntdError`
subclass. It derives from `NetworkError`, so existing 502 handlers keep
working — catch it first to handle the partial case specifically. The
on-chain payment persists and the stored chunks stay on the network. Two
flags say how to finish, `retryable` and `retention_known` (`retryable`
implies `retention_known`):

- **`retryable`**: the daemon kept the paid attempt under the same
  `upload_id`. Call the **same finalize method again with the same `upload_id`
  and payment artefacts** to store the remainder against the same payment —
  no re-prepare, no second signature, no double payment. Bound the loop: a
  persistent failure throws on every call, so cap attempts and treat a
  `chunks_failed` that stops shrinking as stuck.
- **`retention_known && !retryable`**: the daemon confirmed nothing was
  retained (for example a merkle finalize with deliberately unpaid batches).
  Re-prepare the same content — already-stored chunks are skipped, so the
  retry pays only for the remainder.
- **`!retention_known`**: retention is unknown, and the daemon may still hold
  the paid attempt (it records the resume handle before it returns the
  error). Stop automatic recovery, keep the `upload_id` and the original
  payment artefacts, and reconcile before re-preparing or paying again; never
  pay again on this signal alone. Daemons older than 0.14.0 never send
  `retryable`, so their REST partials read as unknown.

`retention_known` is true over REST only when the body's `retryable` is
present and a JSON boolean. Over gRPC the status message reads
`Partial upload: <stored>/<total> chunks stored, <failed> failed after retries: <reason> (<hint>)`,
and `retention_known` is true only when the counts right after the
`Partial upload:` prefix parse (all three) and the message ends with one of
the daemon's two hints: `(paid attempt retained...)` sets `retryable`, and
`(stored chunks persist; re-prepare the same content...)` means the daemon
confirmed nothing was retained (daemons older than 0.14.0 write only this
one). A message whose counts do not parse reads as zero counts with
retention unknown, even with a hint. Readable counts with a missing,
truncated or unrecognised hint, or text after it, keep the counts but read
as retention unknown: stop and reconcile, not "nothing retained".

```cpp
for (int attempt = 1;; ++attempt) {
    try {
        auto fin = client.finalize_upload(upload_id, tx_hashes);
        break;  // every chunk stored
    } catch (const antd::PartialUploadError& e) {
        if (!e.retention_known) throw;  // unknown: stop, keep upload_id + tx_hashes, reconcile
        if (!e.retryable) throw;        // confirmed not retained: re-prepare the same content
        if (attempt >= 5) throw;        // still retained: retry the same finalize later
        std::cerr << e.chunks_stored << "/" << e.total_chunks << " stored, "
                  << e.chunks_failed << " unstored — retrying same upload_id\n";
    }
}
```

`examples/07-external-signer.cpp` has a complete `finalize_with_retry` with
backoff and stuck detection. Contract reference:
[`docs/external-signer-flow.md` §6](../docs/external-signer-flow.md#6-retry-a-partial-store--same-upload_id-same-payment).

## Manifests

A manifest (ADR-0006) is a `.ant` file, or an `ant://manifest/` link, that
describes a set of files: each with an optional path and size, and either an
embedded DataMap (a private upload; the manifest is its key) or a public
DataMap address. The daemon builds and decodes them, so the format is never
re-implemented here. Needs the antd release after 0.15.0.

**Nothing is uploaded or paid for.** Upload the files first (`data_put`,
`file_put_public`, ...), then describe them. The daemon reads the network
only to resolve DataMaps (the embedding policy on build, `resolve` on
decode), so a call can time out; retrying is safe.

On `Client`, `AsyncClient` (as `std::future`s) and `GrpcClient`; the types
are in `antd/manifests.hpp`.

| Method | Description |
|--------|-------------|
| `build_manifest(entries, options)` | Build a manifest from `ManifestEntryInput`s — returns `BuiltManifest` (`.ant` bytes, `link`, entries) |
| `decode_manifest(bytes, resolve)` | Decode `.ant` bytes — returns `DecodedManifest` |
| `decode_manifest_link(link, resolve)` | Decode an `ant://` manifest link, file link or bare 64-hex address — returns `DecodedManifest` |

```cpp
antd::Client client;
auto bytes_of = [](std::string s) { return std::vector<uint8_t>(s.begin(), s.end()); };
auto one = client.data_put_public(bytes_of("first"));
auto two = client.data_put_public(bytes_of("second"));

antd::BuildManifestOptions opts;
opts.name = "notes";
auto built = client.build_manifest({
    {.path = "notes/one.txt", .address = one.address},
    {.path = "notes/two.txt", .address = two.address},
}, opts);
// built.manifest: the .ant bytes; built.link: "ant://manifest/..." (empty if
// it would pass 1,500 bytes, so share the bytes instead)

auto decoded = client.decode_manifest_link(built.link, /*resolve=*/true);
for (const auto& e : decoded.entries) {
    std::cout << e.effective_name << " " << e.kind << " "
              << (e.exact_size ? std::to_string(*e.exact_size) : e.error) << "\n";
}
```

- **Entries**: set exactly one of `data_map` (hex, embedded) or `address`
  (hex, public). An entry with both or neither throws `BadRequestError`
  (naming `entries[i]`) before anything is sent. `path` is optional (empty:
  the entry extracts under its content address), as is `size` (the creator's
  claim, recorded as given).
- **Bytes**: `BuiltManifest::manifest` and `decode_manifest` take and return
  raw bytes on both transports; the client handles REST's base64.
- **Sizes** (`size`, `exact_size`) are `std::optional<std::uint64_t>`. Unset
  is `std::nullopt`, never 0: REST omits the field, gRPC leaves the proto3
  `optional` unset. `exact_size` comes from an embedded root DataMap, or from
  a `resolve` decode.
- **Embedding**: by default the daemon resolves each shrunk DataMap and
  embeds its root when it is at most 64 KiB (`embed_roots`, always sent).
  Set `BuildManifestOptions::keep_shrunk_data_maps` to embed them as given.
- **Errors**: an invalid entry, path, hash or manifest is the daemon's 400
  `BAD_REQUEST` (gRPC `INVALID_ARGUMENT`), thrown as `BadRequestError` with
  the daemon's message, which names the entry (`entries[1]: invalid path
  "../x": ...`). One entry's `resolve` failure is not a failed call: it is in
  that entry's `error`, with `exact_size` unset.
- **gRPC message size**: a manifest can be 64 MiB, past gRPC's 4 MiB default.
  C++ gRPC has no per-call limit, so `GrpcClient` sends the manifest calls on
  their own channel to the same target, created with `grpc::ChannelArguments`
  `SetMaxReceiveMessageSize` and `SetMaxSendMessageSize` at 256 MiB. Every
  other call keeps the default channel and limits.

`examples/09-manifests.cpp` uploads two pieces of public data (paid), builds
a manifest of them and decodes its link with `resolve`:
`ANTD_BASE_URL=http://localhost:8082 ./build/09-manifests`. The live
manifest test (`antd_live_manifest_tests`) pays for nothing and does nothing
unless `ANTD_TEST_URL` and `ANTD_TEST_MANIFEST_ADDRESSES` (plus
`ANTD_TEST_GRPC` in a gRPC build) are set; it also reads
`ANTD_TEST_MANIFEST_SIZES`, `ANTD_TEST_MANIFEST_DATA_MAP`,
`ANTD_TEST_MANIFEST_DATA_MAP_SIZE` and `ANTD_TEST_MANIFEST_LINK` when present.

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
- `07-external-signer` — Two-phase upload paid by an external signer (runs foundry's `cast` without a shell, after validating the daemon's payment fields), with a bounded `finalize_with_retry` for partial stores
