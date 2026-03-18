#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "errors.hpp"
#include "models.hpp"

namespace antd {

/// Default gRPC target address of the antd daemon.
inline constexpr const char* kDefaultGrpcTarget = "localhost:50051";

/// gRPC client for the antd daemon.
///
/// Provides the same 19 methods as the REST `Client`, but communicates over
/// gRPC using the proto-generated stubs from `antd/v1/*.proto`.
///
/// All methods throw antd::AntdError (or a subclass) on failure.
///
/// **Proto compilation**: The generated headers are expected at
/// `antd/v1/*.grpc.pb.h` and `antd/v1/*.pb.h`. Run `protoc` with the
/// `--grpc_out` and `--cpp_out` plugins, or let the CMake `antd_grpc` target
/// handle it automatically via `protobuf_generate_cpp` /
/// `grpc_cpp_plugin`.
class GrpcClient {
public:
    /// Construct a client connected to the given gRPC target.
    explicit GrpcClient(const std::string& target = kDefaultGrpcTarget);
    ~GrpcClient();

    // Non-copyable, movable.
    GrpcClient(const GrpcClient&) = delete;
    GrpcClient& operator=(const GrpcClient&) = delete;
    GrpcClient(GrpcClient&&) noexcept;
    GrpcClient& operator=(GrpcClient&&) noexcept;

    // --- Health ---

    /// Check daemon status.
    HealthStatus health();

    // --- Data (Immutable) ---

    /// Store public immutable data on the network.
    PutResult data_put_public(const std::vector<uint8_t>& data);

    /// Retrieve public data by address.
    std::vector<uint8_t> data_get_public(std::string_view address);

    /// Store private encrypted data on the network.
    PutResult data_put_private(const std::vector<uint8_t>& data);

    /// Retrieve private data using a data map.
    std::vector<uint8_t> data_get_private(std::string_view data_map);

    /// Estimate the cost of storing data.
    std::string data_cost(const std::vector<uint8_t>& data);

    // --- Chunks ---

    /// Store a raw chunk on the network.
    PutResult chunk_put(const std::vector<uint8_t>& data);

    /// Retrieve a chunk by address.
    std::vector<uint8_t> chunk_get(std::string_view address);

    // --- Graph Entries (DAG Nodes) ---

    /// Create a new graph entry.
    PutResult graph_entry_put(std::string_view owner_secret_key,
                              const std::vector<std::string>& parents,
                              std::string_view content,
                              const std::vector<GraphDescendant>& descendants);

    /// Retrieve a graph entry by address.
    GraphEntry graph_entry_get(std::string_view address);

    /// Check if a graph entry exists at the given address.
    bool graph_entry_exists(std::string_view address);

    /// Estimate the cost of creating a graph entry.
    std::string graph_entry_cost(std::string_view public_key);

    // --- Files & Directories ---

    /// Upload a local file to the network.
    PutResult file_upload_public(std::string_view path);

    /// Download a file from the network to a local path.
    void file_download_public(std::string_view address, std::string_view dest_path);

    /// Upload a local directory to the network.
    PutResult dir_upload_public(std::string_view path);

    /// Download a directory from the network to a local path.
    void dir_download_public(std::string_view address, std::string_view dest_path);

    /// Retrieve an archive manifest by address.
    Archive archive_get_public(std::string_view address);

    /// Create an archive manifest on the network.
    PutResult archive_put_public(const Archive& archive);

    /// Estimate the cost of uploading a file.
    std::string file_cost(std::string_view path, bool is_public, bool include_archive);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace antd
