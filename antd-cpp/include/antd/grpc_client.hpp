#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
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

    // --- External signer (two-phase upload) ---

    /// Phase 1: prepare a file upload for external signing.
    ///
    /// @param path        Path to the file on the daemon host.
    /// @param visibility  When set, forwarded as `visibility` on the wire.
    ///                    `"public"` bundles the DataMap chunk into the
    ///                    same external-signer payment batch — the
    ///                    resulting `FinalizeUploadResult::data_map_address`
    ///                    is the shareable retrieval handle. `std::nullopt`
    ///                    (default) leaves the proto3 default of `""`,
    ///                    preserving the pre-public daemon wire shape.
    PrepareUploadResult prepare_upload(std::string_view path,
                                       std::optional<std::string> visibility = std::nullopt);

    /// Convenience wrapper: prepare a *public* file upload for external signing.
    /// Equivalent to `prepare_upload(path, "public")`.
    PrepareUploadResult prepare_upload_public(std::string_view path);

    /// Phase 1 (data): prepare an in-memory data upload for external signing.
    /// Mirrors `Client::prepare_data_upload` — takes raw bytes and forwards
    /// `visibility` when set.
    PrepareUploadResult prepare_data_upload(const std::vector<uint8_t>& data,
                                            std::optional<std::string> visibility = std::nullopt);

    /// Phase 2 (wave-batch): finalize an upload after an external signer has
    /// submitted the per-quote `payForQuotes()` transactions. `tx_hashes`
    /// maps each `quote_hash` from `PrepareUploadResult::payments` to its
    /// resulting tx hash.
    FinalizeUploadResult finalize_upload(std::string_view upload_id,
                                          const std::map<std::string, std::string>& tx_hashes,
                                          bool store_data_map = false);

    /// Phase 2 (merkle): finalize an upload after the external signer has
    /// submitted the `payForMerkleTree2()` transaction. `winner_pool_hash` is
    /// the bytes32 from the `MerklePaymentMade` event (hex with 0x prefix).
    FinalizeUploadResult finalize_merkle_upload(std::string_view upload_id,
                                                 std::string_view winner_pool_hash,
                                                 bool store_data_map = false);

    /// Phase 1 (chunk): prepare a single-chunk publish for external signing.
    /// Returns either `already_stored=true` (no payment needed and no
    /// finalize call) or a wave-batch payment intent the external signer
    /// must execute before calling `finalize_chunk_upload`.
    PrepareChunkResult prepare_chunk_upload(const std::vector<uint8_t>& data);

    /// Phase 2 (chunk): submit a prepared chunk after external payment.
    /// Returns the on-network address of the stored chunk (matches
    /// `PrepareChunkResult::address`).
    std::string finalize_chunk_upload(std::string_view upload_id,
                                      const std::map<std::string, std::string>& tx_hashes);
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
