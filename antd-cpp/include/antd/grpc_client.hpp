#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "discover.hpp"
#include "errors.hpp"
#include "models.hpp"

namespace antd {

/// Default gRPC target address of the antd daemon.
inline constexpr const char* kDefaultGrpcTarget = "localhost:50051";

/// gRPC client for the antd daemon.
///
/// Provides the same methods as the REST `Client`, but communicates over
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

    /// Create a client by auto-discovering the daemon gRPC port from the
    /// daemon.port file.  Falls back to kDefaultGrpcTarget if not found.
    static GrpcClient auto_discover() {
        auto target = discover_grpc_target();
        if (target.empty()) target = kDefaultGrpcTarget;
        return GrpcClient(target);
    }

    // --- Health ---

    /// Check daemon status.
    HealthStatus health();

    // --- Data (Immutable) ---

    /// Store public immutable data on the network.
    DataPutPublicResult data_put_public(const std::vector<uint8_t>& data,
                                        PaymentMode payment_mode = PaymentMode::Auto);

    /// Retrieve public data by address.
    std::vector<uint8_t> data_get_public(std::string_view address);

    /// Store private encrypted data on the network.
    DataPutResult data_put(const std::vector<uint8_t>& data,
                           PaymentMode payment_mode = PaymentMode::Auto);

    /// Retrieve private data using a caller-held DataMap.
    std::vector<uint8_t> data_get(std::string_view data_map);

    /// Pre-upload cost breakdown for the given bytes.
    UploadCostEstimate data_cost(const std::vector<uint8_t>& data,
                                 PaymentMode payment_mode = PaymentMode::Auto);

    // --- Chunks ---

    /// Store a raw chunk on the network.
    PutResult chunk_put(const std::vector<uint8_t>& data);

    /// Retrieve a chunk by address.
    std::vector<uint8_t> chunk_get(std::string_view address);

    // --- Files ---

    /// Upload a local file *privately*.
    FilePutResult file_put(std::string_view path,
                           PaymentMode payment_mode = PaymentMode::Auto);

    /// Download a file from a caller-held DataMap into `dest_path`.
    void file_get(std::string_view data_map, std::string_view dest_path);

    /// Upload a local file *publicly*.
    FilePutPublicResult file_put_public(std::string_view path,
                                        PaymentMode payment_mode = PaymentMode::Auto);

    /// Download a public file by on-network DataMap address.
    void file_get_public(std::string_view address, std::string_view dest_path);

    /// Pre-upload cost breakdown for the file at `path`.
    UploadCostEstimate file_cost(std::string_view path,
                                 bool is_public,
                                 PaymentMode payment_mode = PaymentMode::Auto);

    // --- Wallet (V2-286) ---

    /// Returns the wallet's on-chain address (hex with 0x prefix).
    WalletAddress wallet_address();

    /// Returns the wallet's token + gas balances.
    WalletBalance wallet_balance();

    /// Approves the wallet to spend tokens on the payment vault contract.
    /// One-time operation; idempotent at the contract level.
    bool wallet_approve();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace antd
