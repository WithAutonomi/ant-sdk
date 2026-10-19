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
#include "manifests.hpp"
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

    // --- Manifests ---
    //
    // `.ant` manifests and `ant://` links (ADR-0006; needs the antd release
    // after 0.15.0). Nothing is uploaded or paid for. The `.ant` bytes are
    // raw bytes here; the client handles REST's base64. See manifests.hpp for
    // the types.

    /// Builds a `.ant` manifest from DataMaps and public addresses already in
    /// hand (POST /v1/manifests/build). Throws BadRequestError, before
    /// sending, for an entry with both or neither of `data_map` and
    /// `address`, and the daemon's BadRequestError (naming `entries[i]`) for
    /// any other invalid entry or option. With the default options the
    /// daemon resolves shrunk DataMaps over the network to embed their roots.
    BuiltManifest build_manifest(const std::vector<ManifestEntryInput>& entries,
                                 const BuildManifestOptions& options = {});

    /// Decodes `.ant` bytes (POST /v1/manifests/decode). With `resolve`, the
    /// daemon fetches each entry's DataMap (and wrapper records) to report
    /// `exact_size` and confirm the DataMap is on the network; content chunks
    /// are not fetched, and one entry's failure is reported in its `error`,
    /// not as a failed call. Throws BadRequestError for empty or invalid
    /// bytes.
    DecodedManifest decode_manifest(const std::vector<uint8_t>& manifest,
                                    bool resolve = false);

    /// Decodes an `ant://` manifest link, file link or bare 64-hex address
    /// (POST /v1/manifests/decode). See decode_manifest for `resolve`.
    DecodedManifest decode_manifest_link(std::string_view link, bool resolve = false);

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
    ///
    /// Throws PartialUploadError when the payment settled but some chunks
    /// missed quorum after the daemon's retries (HTTP 502, code
    /// `PARTIAL_UPLOAD`). The stored chunks and the on-chain payment persist:
    ///   - `retryable` (antd >= 0.14.0): the daemon kept the paid attempt
    ///     under this `upload_id`; call `finalize_upload` again with the same
    ///     arguments to store the remainder against the same payment. Bound
    ///     the loop: cap attempts and treat a `chunks_failed` that stops
    ///     shrinking as stuck.
    ///   - `retention_known && !retryable`: the daemon confirmed nothing was
    ///     retained; re-prepare the same content (already-stored chunks are
    ///     skipped, so only the remainder is paid for).
    ///   - `!retention_known` (the body's `retryable` is missing or not a
    ///     boolean, as from daemons < 0.14.0): retention is unknown and the
    ///     daemon may still hold the paid attempt. Stop, keep the `upload_id`
    ///     and `tx_hashes`, and reconcile before re-preparing or paying
    ///     again; never pay again on this alone.
    /// See docs/external-signer-flow.md section 6.
    FinalizeUploadResult finalize_upload(std::string_view upload_id,
                                          const std::map<std::string, std::string>& tx_hashes,
                                          bool store_data_map = false);

    /// Finalize a merkle upload after the external signer has submitted
    /// the payForMerkleTree transaction.
    /// @param upload_id      The upload ID from prepare_upload.
    /// @param winner_pool_hash  The bytes32 value from the MerklePaymentMade event (hex with 0x prefix).
    /// @param store_data_map Whether to store the data map on-network.
    ///
    /// Throws PartialUploadError on a post-payment storage shortfall, exactly
    /// as `finalize_upload` does. A merkle finalize that deliberately left
    /// some sub-batches unpaid is reported with `retention_known == true`
    /// and `retryable == false` (a resume can never acquire proofs for unpaid
    /// chunks): re-prepare the same content to pay for and store only the
    /// remainder. See
    /// docs/external-signer-flow.md section 6.
    FinalizeUploadResult finalize_merkle_upload(std::string_view upload_id,
                                                 std::string_view winner_pool_hash,
                                                 bool store_data_map = false);

    // --- Pointers ---
    //
    // Owner-signed, paid, mutable references (antd with the pointer API,
    // after 0.15.0). The daemon signs with owner keys it loaded at startup
    // (`antd --pointer-keys`); a write names the pointer by its address
    // (`owner`), and an owner the daemon holds no key for is a
    // BadRequestError.
    //
    // Every write pays, about the price of one chunk, and every attempt pays
    // again: the SDK never retries pointer_create, pointer_update,
    // pointer_transfer or pointer_finalize, and callers should not either
    // without checking what landed first (pointer_get). Reads are free to
    // retry; a read during an update or churn can throw
    // CloseGroupShortfallError.

    /// The pointers this daemon holds owner keys for (GET /v1/pointers/keys).
    /// Only these can be written through this daemon.
    std::vector<PointerKey> pointer_keys();

    /// Creates the pointer at `owner`, pointing at `target`, paid by the
    /// daemon wallet (POST /v1/pointers). Throws AlreadyExistsError, before
    /// anything is paid, if the pointer exists; use pointer_update.
    PointerWriteResult pointer_create(std::string_view owner, std::string_view target,
                                      PointerKind kind = PointerKind::Chunk);

    /// Points the pointer at `owner` at `target`, paid by the daemon wallet
    /// (POST /v1/pointers/update). A pointer that does not exist yet is
    /// created at counter 0. Throws PointerFinalError if the pointer has been
    /// transferred or frozen (usually before anything is paid; see
    /// PointerFinalError), and ConflictError if a prepared write to it awaits
    /// payment (refused before paying) or the update lost to a newer state
    /// while in flight (possibly after paying). Read the pointer before
    /// writing again.
    PointerWriteResult pointer_update(std::string_view owner, std::string_view target,
                                      PointerKind kind = PointerKind::Chunk);

    /// Hands the pointer at `owner` over to the pointer at `recipient`, for
    /// good, paid by the daemon wallet (POST /v1/pointers/transfer). Readers
    /// of the address are redirected to the recipient's pointer, which only
    /// its owner can move. Irreversible once stored.
    ///
    /// Refused before paying if `recipient` does not exist or leads back
    /// (BadRequestError), and usually if the pointer is already final
    /// (PointerFinalError). A CloseGroupShortfallError means too few of the
    /// close group answered or stored it. That can happen before paying (the
    /// transfer checks every peer first) or after, so check the pointer with
    /// pointer_finality before paying again.
    PointerTransferResult pointer_transfer(std::string_view owner, std::string_view recipient);

    /// Reads the pointer at `address` (GET /v1/pointers/{address}). Throws
    /// NotFoundError if there is none.
    PointerRecord pointer_get(std::string_view address);

    /// Follows a chain of pointers from `address` to the target at its end
    /// (GET /v1/pointers/{address}/resolve), through forwardings and
    /// transfers alike. Throws NotFoundError if a pointer on the chain does
    /// not exist.
    PointerTarget pointer_resolve(std::string_view address);

    /// Asks the whole close group where the pointer at `address` stands
    /// (GET /v1/pointers/{address}/finality). Check it before relying on a
    /// transfer: only PointerFinalityStatus::Final means one final state,
    /// held by a majority, with no rival seen.
    PointerFinality pointer_finality(std::string_view address);

    /// Follows the transfers of the pointer at `address` to the pointer whose
    /// owner now decides what it resolves to
    /// (GET /v1/pointers/{address}/controller).
    PointerController pointer_controller(std::string_view address);

    /// Has the daemon sign a write with its loaded owner key and quote it for
    /// an external signer (POST /v1/pointers/prepare). Pay
    /// PointerPrepareResult::payments with payForQuotes(), then call
    /// pointer_finalize. Needs no daemon wallet. Every check the daemon-wallet
    /// methods make before paying is made here, before anything is quoted.
    /// While the prepared write awaits payment, other writes to the pointer
    /// throw ConflictError until it is finalized or expires (one hour).
    PointerPrepareResult pointer_prepare(const PointerPrepareRequest& req);

    /// Stores a prepared pointer write once its external signer has paid
    /// (POST /v1/pointers/finalize). `tx_hashes` maps each `quote_hash` from
    /// the prepare's payments to the payForQuotes() transaction hash.
    ///
    /// A write that falls short after payment throws CloseGroupShortfallError
    /// with `retryable == true`: the daemon kept the paid state under the
    /// same `upload_id`, and calling this again with the same `upload_id`
    /// stores it against the same payment (`tx_hashes` is then ignored).
    /// Bound that loop. A finalize without the payment's hashes is a
    /// BadRequestError and keeps the session, so it can be corrected.
    PointerFinalizeResult pointer_finalize(std::string_view upload_id,
                                           const std::map<std::string, std::string>& tx_hashes);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace antd
