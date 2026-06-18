#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
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

/// Default address of the antd daemon.
inline constexpr const char* kDefaultBaseURL = "http://localhost:8082";

/// Default request timeout in seconds (5 minutes).
inline constexpr int kDefaultTimeoutSeconds = 300;

/// Sink invoked for each chunk of a streamed download.
///
/// Receives a pointer to the chunk and its length; the bytes are only valid
/// for the duration of the call, so copy or write them out before returning.
/// Return `true` to continue streaming or `false` to abort the download early.
using DataSink = std::function<bool(const char* data, std::size_t len)>;

/// Sink invoked for each [DownloadFrame] of a progress-enabled streamed
/// download (the `*_with_progress` methods). Each frame is either a plaintext
/// data chunk or a [DownloadProgress] update — discriminate with
/// `DownloadFrame::is_progress()`. Return `true` to continue or `false` to
/// abort the download early.
using DownloadFrameSink = std::function<bool(const DownloadFrame& frame)>;

/// REST client for the antd daemon.
///
/// Naming convention (post v1.0):
///   * Unqualified verb (`data_put`, `data_get`, `file_put`, `file_get`) =
///     private — the DataMap is returned to the caller and NOT stored
///     on-network.
///   * `_public` suffix = public — the DataMap is stored on-network as an
///     extra chunk; the call returns the shareable address.
///
/// All methods throw antd::AntdError (or a subclass) on failure.
class Client {
public:
    /// Construct a client connected to the given base URL.
    explicit Client(const std::string& base_url = kDefaultBaseURL,
                    int timeout_seconds = kDefaultTimeoutSeconds);
    ~Client();

    // Non-copyable, movable.
    Client(const Client&) = delete;
    Client& operator=(const Client&) = delete;
    Client(Client&&) noexcept;
    Client& operator=(Client&&) noexcept;

    /// Create a client by auto-discovering the daemon port from the
    /// daemon.port file.  Falls back to kDefaultBaseURL if not found.
    static Client auto_discover(int timeout_seconds = kDefaultTimeoutSeconds) {
        auto url = discover_daemon_url();
        if (url.empty()) url = kDefaultBaseURL;
        return Client(url, timeout_seconds);
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

    /// Stream public data by address, invoking `sink` for each chunk of
    /// decrypted bytes as it arrives. The streaming counterpart to
    /// `data_get_public`: memory usage stays constant regardless of object
    /// size, so it is suited to large blobs or piping straight to a file.
    ///
    /// The daemon sets a Content-Length, so a `sink` that stops receiving
    /// before the advertised length indicates a failed/truncated download.
    /// Returning `false` from `sink` aborts the download early.
    ///
    /// On a non-2xx response the `{"error"}` body is parsed and thrown as the
    /// matching AntdError subclass, exactly like `data_get_public`.
    void data_stream_public(std::string_view address, const DataSink& sink);

    /// Store private encrypted data on the network. The returned DataMap is
    /// the caller's key to retrieve the data later via `data_get`.
    DataPutResult data_put(const std::vector<uint8_t>& data,
                           PaymentMode payment_mode = PaymentMode::Auto);

    /// Retrieve private data using a caller-held DataMap.
    std::vector<uint8_t> data_get(std::string_view data_map);

    /// Stream private data from a caller-held DataMap, invoking `sink` for each
    /// chunk of decrypted bytes as it arrives. The streaming counterpart to
    /// `data_get`: memory usage stays constant regardless of object size.
    ///
    /// The daemon sets a Content-Length, so a `sink` that stops receiving
    /// before the advertised length indicates a failed/truncated download.
    /// Returning `false` from `sink` aborts the download early.
    ///
    /// On a non-2xx response the `{"error"}` body is parsed and thrown as the
    /// matching AntdError subclass, exactly like `data_get`.
    void data_stream(std::string_view data_map, const DataSink& sink);

    /// Like `data_stream` but opts into NDJSON progress framing
    /// (`Accept: application/x-ndjson`), invoking `sink` with each
    /// [DownloadFrame] so the caller can drive a *determinate* progress bar.
    /// Data frames carry the plaintext bytes; progress frames carry chunk-fetch
    /// counts. The byte denominator arrives as the leading NDJSON `meta` frame
    /// (parsed and dropped here); a terminal `error` frame surfaces as the
    /// matching AntdError subclass. Returning `false` from `sink` aborts early.
    void data_stream_with_progress(std::string_view data_map,
                                   const DownloadFrameSink& sink);

    /// The public counterpart to `data_stream_with_progress`.
    void data_stream_public_with_progress(std::string_view address,
                                          const DownloadFrameSink& sink);

    /// Pre-upload cost breakdown for the given bytes.
    UploadCostEstimate data_cost(const std::vector<uint8_t>& data,
                                 PaymentMode payment_mode = PaymentMode::Auto);

    // --- Chunks ---

    /// Store a raw chunk on the network.
    PutResult chunk_put(const std::vector<uint8_t>& data);

    /// Retrieve a chunk by address.
    std::vector<uint8_t> chunk_get(std::string_view address);

    /// Prepare a single chunk for external-signer publish via POST /v1/chunks/prepare.
    ///
    /// Returns either `already_stored=true` with `address` set (no payment
    /// needed and no finalize call) or a wave-batch payment intent with
    /// `upload_id`, `payments`, and `total_amount` populated. After the
    /// external signer pays, call `finalize_chunk_upload` with the resulting
    /// tx hashes.
    ///
    /// Unlike `chunk_put`, this method does NOT require the daemon to have a
    /// wallet — all funds flow through the external signer.
    PrepareChunkResult prepare_chunk_upload(const std::vector<uint8_t>& data);

    /// Submit a prepared chunk to the network after external payment via
    /// POST /v1/chunks/finalize.
    ///
    /// `tx_hashes` maps each non-zero quote_hash from `prepare_chunk_upload`'s
    /// `payments` to the corresponding tx_hash returned by `payForQuotes()`.
    /// Returns the hex-encoded network address of the stored chunk (matches
    /// `PrepareChunkResult::address`).
    std::string finalize_chunk_upload(std::string_view upload_id,
                                      const std::map<std::string, std::string>& tx_hashes);

    // --- Files ---

    /// Upload a local file *privately*. The returned DataMap is the
    /// caller's key to retrieve the file later via `file_get`. The DataMap
    /// itself is NOT stored on-network.
    FilePutResult file_put(std::string_view path,
                           PaymentMode payment_mode = PaymentMode::Auto);

    /// Download a file from a caller-held DataMap into `dest_path`.
    void file_get(std::string_view data_map, std::string_view dest_path);

    /// Upload a local file *publicly*. The DataMap is stored on-network as
    /// an extra chunk; the returned address is the shareable retrieval
    /// handle.
    FilePutPublicResult file_put_public(std::string_view path,
                                        PaymentMode payment_mode = PaymentMode::Auto);

    /// Download a public file from an on-network DataMap address.
    void file_get_public(std::string_view address, std::string_view dest_path);

    /// Pre-upload cost breakdown for the file at `path`.
    UploadCostEstimate file_cost(std::string_view path,
                                 bool is_public,
                                 PaymentMode payment_mode = PaymentMode::Auto);

    // --- Wallet ---

    /// Get the wallet address configured on the daemon.
    WalletAddress wallet_address();

    /// Get the wallet balance (tokens and gas).
    WalletBalance wallet_balance();

    /// Approve the wallet to spend tokens on payment contracts (one-time operation).
    bool wallet_approve();

    // --- External Signer (Two-Phase Upload) ---

    /// Prepare a file upload for external signing.
    ///
    /// @param path        Path to the file to upload.
    /// @param visibility  When set, forwarded as a JSON field. Pass "public"
    ///                    to bundle the DataMap chunk into the same
    ///                    external-signer payment batch — the resulting
    ///                    `FinalizeUploadResult::data_map_address` is the
    ///                    shareable retrieval handle. When std::nullopt
    ///                    (default) the field is omitted, preserving the
    ///                    pre-public daemon wire shape.
    PrepareUploadResult prepare_upload(std::string_view path,
                                       std::optional<std::string> visibility = std::nullopt);

    /// Convenience wrapper: prepare a *public* file upload for external signing.
    /// Equivalent to `prepare_upload(path, "public")`. Requires antd >= 0.6.1.
    PrepareUploadResult prepare_upload_public(std::string_view path);

    /// Prepare a data upload for external signing.
    /// Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
    ///
    /// Note: `visibility="public"` returns 501 from the daemon until upstream
    /// ant-client exposes `data_prepare_upload_with_visibility`. Use
    /// `prepare_upload_public` with a file path until then.
    PrepareUploadResult prepare_data_upload(const std::vector<uint8_t>& data,
                                            std::optional<std::string> visibility = std::nullopt);

    /// Finalize a wave-batch upload after an external signer has submitted payment transactions.
    FinalizeUploadResult finalize_upload(std::string_view upload_id,
                                          const std::map<std::string, std::string>& tx_hashes,
                                          bool store_data_map = false);

    /// Finalize a merkle upload after the external signer has submitted
    /// the payForMerkleTree transaction.
    /// @param upload_id      The upload ID from prepare_upload.
    /// @param winner_pool_hash  The bytes32 value from the MerklePaymentMade event (hex with 0x prefix).
    /// @param store_data_map Whether to store the data map on-network.
    FinalizeUploadResult finalize_merkle_upload(std::string_view upload_id,
                                                 std::string_view winner_pool_hash,
                                                 bool store_data_map = false);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace antd
