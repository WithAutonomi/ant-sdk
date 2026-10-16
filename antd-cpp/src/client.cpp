#include "antd/client.hpp"

#include <nlohmann/json.hpp>
#include <httplib.h>

#include <limits>
#include <optional>

#include "base64.hpp"
#include "manifests_json.hpp"

namespace antd {

using json = nlohmann::json;

namespace {

/// Media type that opts the stream endpoints into NDJSON progress framing.
constexpr const char* kNdjsonContentType = "application/x-ndjson";

/// Parse one NDJSON line into a [DownloadFrame], appending it to `out`.
///
/// Returns false for blank lines and unknown frame types (forward-compat) —
/// nothing is appended in those cases. The leading `meta` frame surfaces as a
/// Meta DownloadFrame carrying the total byte count. Throws the matching
/// AntdError subclass for a terminal `error` frame.
bool parse_ndjson_frame(std::string_view line, DownloadFrame& out) {
    if (!line.empty() && line.back() == '\r') {
        line.remove_suffix(1);
    }
    if (line.empty()) {
        return false;
    }
    json v = json::parse(line);
    const std::string type = v.value("type", "");
    if (type == "data") {
        // base64 lives under "chunk" (NOT "data") on NDJSON data frames.
        out = DownloadFrame::from_data(detail::base64_decode(v.value("chunk", "")));
        return true;
    }
    if (type == "progress") {
        out = DownloadFrame::from_progress(DownloadProgress{
            v.value("phase", ""),
            v.value<std::uint64_t>("fetched", 0),
            v.value<std::uint64_t>("total", 0),
        });
        return true;
    }
    if (type == "error") {
        error_for_status(500, v.value("message", "download failed"));
    }
    if (type == "meta") {
        // "meta" carries the byte denominator; surface it as a Meta frame.
        out = DownloadFrame::from_meta(v.value<std::uint64_t>("total_size", 0));
        return true;
    }
    // Unknown types are ignored for forward compatibility.
    return false;
}

/// Throw the typed error for a non-2xx response body.
///
/// Parses the daemon's `{"error", "code", ...}` JSON body (falling back to the
/// raw body as the message when it is not JSON) and prefers the machine-
/// readable `code` over the bare HTTP status where they diverge: a
/// PARTIAL_UPLOAD arrives as a 502 that would otherwise read as a generic
/// NetworkError, so it is thrown as PartialUploadError carrying the body's
/// `chunks_stored` / `chunks_failed` / `total_chunks` and `retryable`.
/// `retention_known` is true only when `retryable` is present and a JSON
/// boolean; absent (daemons < 0.14.0), null or any other type leaves
/// retention unknown and `retryable` false. POINTER_FINAL, POINTER_FORKED and
/// CONFLICT are 409s that must not read as AlreadyExistsError, and
/// CLOSE_GROUP_SHORTFALL is a 503 whose `retryable` (true only as a JSON
/// boolean `true`) says a pointer finalize kept the paid state; each becomes
/// its own type (throw_for_error_code). Every other code keeps the status
/// mapping.
///
/// The body is network input, so a malformed one never escapes as anything
/// but an AntdError subclass: a non-JSON or non-object body, or a `code`
/// that is missing, another value, or not a string, takes the status mapping
/// (NetworkError for a 502); a count of the wrong JSON type reads as zero; a
/// non-string `error` falls back to the raw body.
[[noreturn]] void throw_error_response(int status, const std::string& body) {
    std::string msg = body;
    try {
        auto err_json = json::parse(body);
        if (err_json.contains("error") && err_json["error"].is_string()) {
            msg = err_json["error"].get<std::string>();
        }
        // find() returns end() on a non-object, and the string check keeps a
        // `code` of any other JSON type on the status mapping.
        const auto code = err_json.find("code");
        if (code != err_json.end() && code->is_string() &&
            code->get_ref<const std::string&>() == "PARTIAL_UPLOAD") {
            // Tolerate a missing or mistyped field (zero / false) rather than
            // degrading the whole error to a generic NetworkError. Counts must
            // be non-negative JSON integers: get<uint64_t> would wrap a
            // negative value and truncate (or, out of range, misconvert) a
            // floating-point one.
            auto u64 = [&](const char* key) -> std::uint64_t {
                auto it = err_json.find(key);
                return it != err_json.end() && it->is_number_unsigned()
                           ? it->get<std::uint64_t>()
                           : 0;
            };
            // The daemon's answer about retention counts only when
            // `retryable` is a JSON boolean; anything else leaves it unknown.
            const auto retry = err_json.find("retryable");
            const bool retention_known = retry != err_json.end() && retry->is_boolean();
            const bool retryable = retention_known && retry->get<bool>();
            throw PartialUploadError(msg, u64("chunks_stored"), u64("chunks_failed"),
                                     u64("total_chunks"), retryable, retention_known);
        }
        if (code != err_json.end() && code->is_string()) {
            const auto retry = err_json.find("retryable");
            const bool retryable =
                retry != err_json.end() && retry->is_boolean() && retry->get<bool>();
            throw_for_error_code(code->get_ref<const std::string&>(), msg, retryable);
        }
    } catch (const AntdError&) {
        throw;
    } catch (...) {
        // Not JSON (or unexpected shape): use the raw body as the message.
    }
    error_for_status(status, msg);
}

}  // namespace

// ---------------------------------------------------------------------------
// Impl (pimpl hides httplib from the public header)
// ---------------------------------------------------------------------------

struct Client::Impl {
    httplib::Client http;
    std::string base_url;

    Impl(const std::string& base_url, int timeout_seconds)
        : http(base_url), base_url(base_url) {
        http.set_connection_timeout(timeout_seconds);
        http.set_read_timeout(timeout_seconds);
        http.set_write_timeout(timeout_seconds);
    }

    // --- internal helpers ---

    /// Perform a JSON request. Returns parsed JSON and the status code.
    /// Throws on HTTP error status codes.
    json do_json(const std::string& method, const std::string& path,
                 const json& body = json()) {
        httplib::Result res{nullptr, httplib::Error::Unknown};
        std::string body_str;
        std::string content_type = "application/json";

        if (!body.is_null()) {
            body_str = body.dump();
        }

        if (method == "GET") {
            res = http.Get(path);
        } else if (method == "POST") {
            res = http.Post(path, body_str, content_type);
        } else if (method == "PUT") {
            res = http.Put(path, body_str, content_type);
        }

        if (!res) {
            throw AntdError(0, "HTTP request failed: connection error");
        }

        if (res->status < 200 || res->status >= 300) {
            throw_error_response(res->status, res->body);
        }

        if (res->body.empty()) {
            return json::object();
        }

        return json::parse(res->body);
    }

    /// Perform a streaming request, forwarding each chunk of a 2xx response
    /// body to `sink` as it arrives (constant memory). Mirrors do_json's
    /// non-2xx handling: the error body is buffered and handed to
    /// throw_error_response.
    ///
    /// httplib's high-level Client has no Post(..., ContentReceiver) overload,
    /// so we build a Request directly and use Client::send — this works
    /// uniformly for GET and POST and reuses the configured client/timeouts.
    void do_stream(const std::string& method, const std::string& path,
                   const DataSink& sink, const json& body = json(),
                   const std::string& accept = std::string()) {
        httplib::Request req;
        req.method = method;
        req.path = path;
        if (!body.is_null()) {
            req.body = body.dump();
            req.set_header("Content-Type", "application/json");
        }
        if (!accept.empty()) {
            req.set_header("Accept", accept);
        }

        // Captured by the response_handler so the content_receiver knows
        // whether to stream to the caller or buffer an error payload.
        int status = 0;
        bool success = false;
        std::string error_body;

        req.response_handler = [&](const httplib::Response& res) -> bool {
            status = res.status;
            success = res.status >= 200 && res.status < 300;
            return true;  // keep going so we can read the (error) body too
        };

        // content_receiver is always invoked regardless of status, so route
        // by the captured success flag: stream to the sink on 2xx, otherwise
        // accumulate the short error body for parsing after send() returns.
        req.content_receiver = [&](const char* data, size_t len,
                                   uint64_t /*off*/, uint64_t /*total*/) -> bool {
            if (success) {
                return sink(data, len);
            }
            error_body.append(data, len);
            return true;
        };

        auto res = http.send(req);

        // A canceled transfer is expected when the caller's sink returns false;
        // only treat it as an error when the response itself never arrived.
        if (!res && status == 0) {
            throw AntdError(0, "HTTP request failed: connection error");
        }

        if (!success) {
            throw_error_response(status, error_body);
        }
    }

    /// Perform a HEAD request, returning the status code.
    int do_head(const std::string& path) {
        auto res = http.Head(path);
        if (!res) {
            throw AntdError(0, "HTTP HEAD request failed: connection error");
        }
        return res->status;
    }
};

// ---------------------------------------------------------------------------
// Client lifetime
// ---------------------------------------------------------------------------

Client::Client(const std::string& base_url, int timeout_seconds)
    : impl_(std::make_unique<Impl>(base_url, timeout_seconds)) {}

Client::~Client() = default;
Client::Client(Client&&) noexcept = default;
Client& Client::operator=(Client&&) noexcept = default;

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

HealthStatus Client::health() {
    auto j = impl_->do_json("GET", "/health");
    return HealthStatus{
        .ok = j.value("status", "") == "ok",
        .network = j.value("network", ""),
        .version = j.value("version", ""),
        .evm_network = j.value("evm_network", ""),
        .uptime_seconds = j.value<std::uint64_t>("uptime_seconds", 0),
        .build_commit = j.value("build_commit", ""),
        .payment_token_address = j.value("payment_token_address", ""),
        .payment_vault_address = j.value("payment_vault_address", ""),
    };
}

// ---------------------------------------------------------------------------
// Data (Immutable)
// ---------------------------------------------------------------------------

DataPutPublicResult Client::data_put_public(const std::vector<uint8_t>& data,
                                            PaymentMode payment_mode) {
    json body = {
        {"data", detail::base64_encode(data)},
        {"payment_mode", payment_mode_wire(payment_mode)},
    };
    auto j = impl_->do_json("POST", "/v1/data/public", body);
    return DataPutPublicResult{
        .address = j.value("address", ""),
        .chunks_stored = j.value<std::uint64_t>("chunks_stored", 0),
        .payment_mode_used = j.value("payment_mode_used", ""),
    };
}

std::vector<uint8_t> Client::data_get_public(std::string_view address) {
    auto j = impl_->do_json("GET", "/v1/data/public/" + std::string(address));
    return detail::base64_decode(j.value("data", ""));
}

void Client::data_stream_public(std::string_view address, const DataSink& sink) {
    impl_->do_stream("GET",
                     "/v1/data/public/" + std::string(address) + "/stream",
                     sink);
}

DataPutResult Client::data_put(const std::vector<uint8_t>& data,
                               PaymentMode payment_mode) {
    json body = {
        {"data", detail::base64_encode(data)},
        {"payment_mode", payment_mode_wire(payment_mode)},
    };
    auto j = impl_->do_json("POST", "/v1/data", body);
    return DataPutResult{
        .data_map = j.value("data_map", ""),
        .chunks_stored = j.value<std::uint64_t>("chunks_stored", 0),
        .payment_mode_used = j.value("payment_mode_used", ""),
    };
}

std::vector<uint8_t> Client::data_get(std::string_view data_map) {
    auto j = impl_->do_json("POST", "/v1/data/get", json{
        {"data_map", std::string(data_map)},
    });
    return detail::base64_decode(j.value("data", ""));
}

void Client::data_stream(std::string_view data_map, const DataSink& sink) {
    impl_->do_stream("POST", "/v1/data/stream", sink, json{
        {"data_map", std::string(data_map)},
    });
}

namespace {

/// Adapt a [DownloadFrameSink] onto the byte-oriented [DataSink] do_stream
/// uses: buffer the raw body across chunk boundaries, split on '\n', and emit
/// a [DownloadFrame] per complete NDJSON line. A `false` return from the frame
/// sink aborts the download (propagated as a `false` DataSink return);
/// `error` frames throw out of parse_ndjson_frame and unwind the request.
///
/// Trailing bytes with no terminating newline are not flushed here — the
/// daemon terminates every NDJSON frame (including the final one) with '\n',
/// so a complete stream leaves the buffer empty.
DataSink ndjson_sink(const DownloadFrameSink& frames) {
    auto buf = std::make_shared<std::string>();
    return [buf, frames](const char* data, std::size_t len) -> bool {
        buf->append(data, len);
        std::size_t start = 0;
        std::size_t nl;
        while ((nl = buf->find('\n', start)) != std::string::npos) {
            std::string_view line(buf->data() + start, nl - start);
            DownloadFrame frame;
            if (parse_ndjson_frame(line, frame)) {
                if (!frames(frame)) {
                    buf->clear();
                    return false;  // caller aborted
                }
            }
            start = nl + 1;
        }
        buf->erase(0, start);
        return true;
    };
}

}  // namespace

void Client::data_stream_with_progress(std::string_view data_map,
                                       const DownloadFrameSink& sink) {
    impl_->do_stream("POST", "/v1/data/stream", ndjson_sink(sink),
                     json{{"data_map", std::string(data_map)}},
                     kNdjsonContentType);
}

void Client::data_stream_public_with_progress(std::string_view address,
                                              const DownloadFrameSink& sink) {
    impl_->do_stream("GET",
                     "/v1/data/public/" + std::string(address) + "/stream",
                     ndjson_sink(sink), json(), kNdjsonContentType);
}

UploadCostEstimate Client::data_cost(const std::vector<uint8_t>& data,
                                     PaymentMode payment_mode) {
    auto j = impl_->do_json("POST", "/v1/data/cost", json{
        {"data", detail::base64_encode(data)},
        {"payment_mode", payment_mode_wire(payment_mode)},
    });
    return UploadCostEstimate{
        j.value("cost", std::string{}),
        j.value("file_size", uint64_t{0}),
        j.value("chunk_count", uint32_t{0}),
        j.value("estimated_gas_cost_wei", std::string{}),
        j.value("payment_mode", std::string{}),
    };
}

// ---------------------------------------------------------------------------
// Chunks
// ---------------------------------------------------------------------------

PutResult Client::chunk_put(const std::vector<uint8_t>& data) {
    auto j = impl_->do_json("POST", "/v1/chunks", json{
        {"data", detail::base64_encode(data)},
    });
    return PutResult{
        .cost = j.value("cost", ""),
        .address = j.value("address", ""),
    };
}

std::vector<uint8_t> Client::chunk_get(std::string_view address) {
    auto j = impl_->do_json("GET", "/v1/chunks/" + std::string(address));
    return detail::base64_decode(j.value("data", ""));
}

PrepareChunkResult Client::prepare_chunk_upload(const std::vector<uint8_t>& data) {
    auto j = impl_->do_json("POST", "/v1/chunks/prepare", json{
        {"data", detail::base64_encode(data)},
    });

    PrepareChunkResult r;
    r.address = j.value("address", "");
    r.already_stored = j.value("already_stored", false);
    r.upload_id = j.value("upload_id", "");
    r.payment_type = j.value("payment_type", "");
    r.total_amount = j.value("total_amount", "");
    r.payment_vault_address = j.value("payment_vault_address", "");
    r.payment_token_address = j.value("payment_token_address", "");
    r.rpc_url = j.value("rpc_url", "");

    if (j.contains("payments") && j["payments"].is_array()) {
        for (const auto& p : j["payments"]) {
            if (p.is_object()) {
                r.payments.push_back(PaymentInfo{
                    .quote_hash = p.value("quote_hash", ""),
                    .rewards_address = p.value("rewards_address", ""),
                    .amount = p.value("amount", ""),
                });
            }
        }
    }
    return r;
}

std::string Client::finalize_chunk_upload(std::string_view upload_id,
                                          const std::map<std::string, std::string>& tx_hashes) {
    json hashes = json::object();
    for (const auto& [k, v] : tx_hashes) {
        hashes[k] = v;
    }
    auto j = impl_->do_json("POST", "/v1/chunks/finalize", json{
        {"upload_id", std::string(upload_id)},
        {"tx_hashes", hashes},
    });
    return j.value("address", "");
}

// ---------------------------------------------------------------------------
// Files & Directories
// ---------------------------------------------------------------------------

FilePutResult Client::file_put(std::string_view path, PaymentMode payment_mode) {
    json body = {
        {"path", std::string(path)},
        {"payment_mode", payment_mode_wire(payment_mode)},
    };
    auto j = impl_->do_json("POST", "/v1/files", body);
    return FilePutResult{
        .data_map = j.value("data_map", ""),
        .storage_cost_atto = j.value("storage_cost_atto", ""),
        .gas_cost_wei = j.value("gas_cost_wei", ""),
        .chunks_stored = j.value<std::uint64_t>("chunks_stored", 0),
        .payment_mode_used = j.value("payment_mode_used", ""),
    };
}

void Client::file_get(std::string_view data_map, std::string_view dest_path) {
    impl_->do_json("POST", "/v1/files/get", json{
        {"data_map", std::string(data_map)},
        {"dest_path", std::string(dest_path)},
    });
}

FilePutPublicResult Client::file_put_public(std::string_view path,
                                            PaymentMode payment_mode) {
    json body = {
        {"path", std::string(path)},
        {"payment_mode", payment_mode_wire(payment_mode)},
    };
    auto j = impl_->do_json("POST", "/v1/files/public", body);
    return FilePutPublicResult{
        .address = j.value("address", ""),
        .storage_cost_atto = j.value("storage_cost_atto", ""),
        .gas_cost_wei = j.value("gas_cost_wei", ""),
        .chunks_stored = j.value<std::uint64_t>("chunks_stored", 0),
        .payment_mode_used = j.value("payment_mode_used", ""),
    };
}

void Client::file_get_public(std::string_view address, std::string_view dest_path) {
    impl_->do_json("POST", "/v1/files/public/get", json{
        {"address", std::string(address)},
        {"dest_path", std::string(dest_path)},
    });
}

UploadCostEstimate Client::file_cost(std::string_view path,
                                     bool is_public,
                                     PaymentMode payment_mode) {
    auto j = impl_->do_json("POST", "/v1/files/cost", json{
        {"path", std::string(path)},
        {"is_public", is_public},
        {"payment_mode", payment_mode_wire(payment_mode)},
    });
    return UploadCostEstimate{
        j.value("cost", std::string{}),
        j.value("file_size", uint64_t{0}),
        j.value("chunk_count", uint32_t{0}),
        j.value("estimated_gas_cost_wei", std::string{}),
        j.value("payment_mode", std::string{}),
    };
}

// ---------------------------------------------------------------------------
// Wallet
// ---------------------------------------------------------------------------

WalletAddress Client::wallet_address() {
    auto j = impl_->do_json("GET", "/v1/wallet/address");
    return WalletAddress{
        .address = j.value("address", ""),
    };
}

WalletBalance Client::wallet_balance() {
    auto j = impl_->do_json("GET", "/v1/wallet/balance");
    return WalletBalance{
        .balance = j.value("balance", ""),
        .gas_balance = j.value("gas_balance", ""),
    };
}

bool Client::wallet_approve() {
    auto j = impl_->do_json("POST", "/v1/wallet/approve", json::object());
    return j.value("approved", false);
}

// ---------------------------------------------------------------------------
// Manifests (the wire mapping is in manifests_json.cpp)
// ---------------------------------------------------------------------------

BuiltManifest Client::build_manifest(const std::vector<ManifestEntryInput>& entries,
                                     const BuildManifestOptions& options) {
    auto body = detail::manifest_build_body(entries, options);
    return detail::parse_built_manifest(impl_->do_json("POST", "/v1/manifests/build", body));
}

DecodedManifest Client::decode_manifest(const std::vector<uint8_t>& manifest, bool resolve) {
    auto body = detail::manifest_decode_bytes_body(manifest, resolve);
    return detail::parse_decoded_manifest(impl_->do_json("POST", "/v1/manifests/decode", body));
}

DecodedManifest Client::decode_manifest_link(std::string_view link, bool resolve) {
    auto body = detail::manifest_decode_link_body(link, resolve);
    return detail::parse_decoded_manifest(impl_->do_json("POST", "/v1/manifests/decode", body));
}

// ---------------------------------------------------------------------------
// External Signer (Two-Phase Upload)
// ---------------------------------------------------------------------------

/// Parse a prepare-upload JSON response into PrepareUploadResult.
/// Handles both wave_batch and merkle payment types.
static PrepareUploadResult parse_prepare_response(const json& j) {
    PrepareUploadResult result;
    result.upload_id = j.value("upload_id", "");
    result.payment_type = j.value("payment_type", "");
    result.total_amount = j.value("total_amount", "");
    result.payment_vault_address = j.value("payment_vault_address", "");
    result.payment_token_address = j.value("payment_token_address", "");
    result.rpc_url = j.value("rpc_url", "");
    result.total_chunks = j.value("total_chunks", uint64_t{0});
    result.already_stored_count = j.value("already_stored_count", uint64_t{0});

    // Default to wave_batch for backward compatibility with older daemons
    if (result.payment_type.empty()) {
        result.payment_type = "wave_batch";
    }

    // Parse wave-batch payments
    if (j.contains("payments") && j["payments"].is_array()) {
        for (const auto& p : j["payments"]) {
            if (p.is_object()) {
                result.payments.push_back(PaymentInfo{
                    .quote_hash = p.value("quote_hash", ""),
                    .rewards_address = p.value("rewards_address", ""),
                    .amount = p.value("amount", ""),
                });
            }
        }
    }

    // Parse merkle fields
    if (result.payment_type == "merkle") {
        result.depth = j.value("depth", 0);
        result.merkle_payment_timestamp = j.value("merkle_payment_timestamp", uint64_t{0});

        if (j.contains("pool_commitments") && j["pool_commitments"].is_array()) {
            for (const auto& pc : j["pool_commitments"]) {
                if (!pc.is_object()) continue;
                PoolCommitmentEntry entry;
                entry.pool_hash = pc.value("pool_hash", "");
                if (pc.contains("candidates") && pc["candidates"].is_array()) {
                    for (const auto& c : pc["candidates"]) {
                        if (c.is_object()) {
                            entry.candidates.push_back(CandidateNodeEntry{
                                .rewards_address = c.value("rewards_address", ""),
                                .amount = c.value("amount", ""),
                            });
                        }
                    }
                }
                result.pool_commitments.push_back(std::move(entry));
            }
        }
    }

    return result;
}

PrepareUploadResult Client::prepare_upload(std::string_view path,
                                           std::optional<std::string> visibility) {
    json body = {{"path", std::string(path)}};
    if (visibility.has_value()) {
        body["visibility"] = *visibility;
    }
    auto j = impl_->do_json("POST", "/v1/upload/prepare", body);
    return parse_prepare_response(j);
}

PrepareUploadResult Client::prepare_upload_public(std::string_view path) {
    return prepare_upload(path, std::string("public"));
}

PrepareUploadResult Client::prepare_data_upload(const std::vector<uint8_t>& data,
                                                std::optional<std::string> visibility) {
    json body = {{"data", detail::base64_encode(data)}};
    if (visibility.has_value()) {
        body["visibility"] = *visibility;
    }
    auto j = impl_->do_json("POST", "/v1/data/prepare", body);
    return parse_prepare_response(j);
}

FinalizeUploadResult Client::finalize_upload(std::string_view upload_id,
                                               const std::map<std::string, std::string>& tx_hashes,
                                               bool store_data_map) {
    json hashes = json::object();
    for (const auto& [k, v] : tx_hashes) {
        hashes[k] = v;
    }

    auto j = impl_->do_json("POST", "/v1/upload/finalize", json{
        {"upload_id", std::string(upload_id)},
        {"tx_hashes", hashes},
        {"store_data_map", store_data_map},
    });
    return FinalizeUploadResult{
        .data_map = j.value("data_map", ""),
        .address = j.value("address", ""),
        .data_map_address = j.value("data_map_address", ""),
        .chunks_stored = j.value("chunks_stored", int64_t{0}),
    };
}

FinalizeUploadResult Client::finalize_merkle_upload(std::string_view upload_id,
                                                      std::string_view winner_pool_hash,
                                                      bool store_data_map) {
    auto j = impl_->do_json("POST", "/v1/upload/finalize", json{
        {"upload_id", std::string(upload_id)},
        {"winner_pool_hash", std::string(winner_pool_hash)},
        {"store_data_map", store_data_map},
    });
    return FinalizeUploadResult{
        .data_map = j.value("data_map", ""),
        .address = j.value("address", ""),
        .data_map_address = j.value("data_map_address", ""),
        .chunks_stored = j.value("chunks_stored", int64_t{0}),
    };
}

// ---------------------------------------------------------------------------
// Pointers
//
// A pointer's owner key lives in the daemon (`antd --pointer-keys`); a write
// names the pointer by its address. Every write pays, and every attempt pays
// again: nothing here retries a create, update, transfer or finalize. Reads
// are free to retry; a read during an update or churn can throw
// CloseGroupShortfallError.
//
// Unset values arrive as JSON `null` (`transferred_to`, a finality's
// `counter`, `state` and `majority`) and map to std::nullopt. The parsers
// read each field by type, so a null or mistyped field never escapes as a
// nlohmann::json exception; a counter that is not a decimal u64 string
// throws InternalError.
// ---------------------------------------------------------------------------

namespace {

std::string str_at(const json& j, const char* key) {
    const auto it = j.find(key);
    return it != j.end() && it->is_string() ? it->get<std::string>() : std::string{};
}

/// A string field that is absent, `null`, empty or not a string reads as
/// unset.
std::optional<std::string> opt_str_at(const json& j, const char* key) {
    auto s = str_at(j, key);
    if (s.empty()) return std::nullopt;
    return s;
}

bool bool_at(const json& j, const char* key) {
    const auto it = j.find(key);
    return it != j.end() && it->is_boolean() && it->get<bool>();
}

/// An unsigned JSON integer, or 0 when absent or of another type.
std::uint64_t u64_at(const json& j, const char* key) {
    const auto it = j.find(key);
    return it != j.end() && it->is_number_unsigned() ? it->get<std::uint64_t>() : 0;
}

std::uint32_t u32_at(const json& j, const char* key) {
    const auto v = u64_at(j, key);
    return v > std::numeric_limits<std::uint32_t>::max()
               ? std::numeric_limits<std::uint32_t>::max()
               : static_cast<std::uint32_t>(v);
}

/// The raw target kind tag. One that is absent or not a u8 reads as 0xFF, a
/// kind no SDK knows, rather than as a chunk.
std::uint8_t kind_tag_at(const json& j) {
    const auto it = j.find("kind_tag");
    if (it == j.end() || !it->is_number_unsigned()) return 0xFF;
    const auto v = it->get<std::uint64_t>();
    return v > 0xFF ? std::uint8_t{0xFF} : static_cast<std::uint8_t>(v);
}

/// A required counter: a decimal u64 string.
std::uint64_t counter_at(const json& j, const char* key) {
    return detail::parse_pointer_counter(key, str_at(j, key));
}

PointerWriteResult parse_pointer_write(const json& j) {
    return PointerWriteResult{
        .address = str_at(j, "address"),
        .state_id = str_at(j, "state_id"),
        .counter = counter_at(j, "counter"),
    };
}

PointerFinalState parse_final_state(const json& j) {
    return PointerFinalState{
        .state_id = str_at(j, "state_id"),
        .kind = str_at(j, "kind"),
        .kind_tag = kind_tag_at(j),
        .target = str_at(j, "target"),
        .holders = u32_at(j, "holders"),
        .transferred_to = opt_str_at(j, "transferred_to"),
    };
}

std::optional<PointerFinalState> final_state_at(const json& j, const char* key) {
    const auto it = j.find(key);
    if (it == j.end() || !it->is_object()) return std::nullopt;
    return parse_final_state(*it);
}

PointerFinality parse_pointer_finality(const json& j) {
    PointerFinality f;
    f.address = str_at(j, "address");
    f.group = u32_at(j, "group");
    f.answered = u32_at(j, "answered");
    f.status_raw = str_at(j, "status");
    f.status = pointer_finality_status_from_wire(f.status_raw);
    // `null` (or absent, or "") when no state is corroborated; any other
    // non-string is malformed rather than unset.
    const auto counter = j.find("counter");
    if (counter != j.end() && !counter->is_null()) {
        if (!counter->is_string()) {
            throw InternalError("invalid pointer counter: expected a decimal string");
        }
        const auto& s = counter->get_ref<const std::string&>();
        if (!s.empty()) {
            f.counter = detail::parse_pointer_counter("counter", s);
        }
    }
    f.state = final_state_at(j, "state");
    if (const auto states = j.find("states"); states != j.end() && states->is_array()) {
        for (const auto& s : *states) {
            if (s.is_object()) f.states.push_back(parse_final_state(s));
        }
    }
    f.majority = final_state_at(j, "majority");
    f.transferred_to = opt_str_at(j, "transferred_to");
    return f;
}

std::optional<PointerFinality> finality_at(const json& j) {
    const auto it = j.find("finality");
    if (it == j.end() || !it->is_object()) return std::nullopt;
    return parse_pointer_finality(*it);
}

std::string pointer_path(std::string_view address, const char* suffix = "") {
    return "/v1/pointers/" + std::string(address) + suffix;
}

}  // namespace

std::vector<PointerKey> Client::pointer_keys() {
    auto j = impl_->do_json("GET", "/v1/pointers/keys");
    std::vector<PointerKey> keys;
    if (const auto arr = j.find("keys"); arr != j.end() && arr->is_array()) {
        for (const auto& k : *arr) {
            if (k.is_object()) keys.push_back(PointerKey{.address = str_at(k, "address")});
        }
    }
    return keys;
}

PointerWriteResult Client::pointer_create(std::string_view owner, std::string_view target,
                                          PointerKind kind) {
    return parse_pointer_write(impl_->do_json("POST", "/v1/pointers", json{
        {"owner", std::string(owner)},
        {"target", std::string(target)},
        {"kind", pointer_kind_wire(kind)},
    }));
}

PointerWriteResult Client::pointer_update(std::string_view owner, std::string_view target,
                                          PointerKind kind) {
    return parse_pointer_write(impl_->do_json("POST", "/v1/pointers/update", json{
        {"owner", std::string(owner)},
        {"target", std::string(target)},
        {"kind", pointer_kind_wire(kind)},
    }));
}

PointerTransferResult Client::pointer_transfer(std::string_view owner,
                                               std::string_view recipient) {
    auto j = impl_->do_json("POST", "/v1/pointers/transfer", json{
        {"owner", std::string(owner)},
        {"recipient", std::string(recipient)},
    });
    return PointerTransferResult{
        .address = str_at(j, "address"),
        .state_id = str_at(j, "state_id"),
        .finality = finality_at(j),
        .finality_error = opt_str_at(j, "finality_error"),
    };
}

PointerRecord Client::pointer_get(std::string_view address) {
    auto j = impl_->do_json("GET", pointer_path(address));
    return PointerRecord{
        .address = str_at(j, "address"),
        .owner = str_at(j, "owner"),
        .counter = counter_at(j, "counter"),
        .kind = str_at(j, "kind"),
        .kind_tag = kind_tag_at(j),
        .target = str_at(j, "target"),
        .state_id = str_at(j, "state_id"),
        .is_final = bool_at(j, "is_final"),
        .transferred_to = opt_str_at(j, "transferred_to"),
    };
}

PointerTarget Client::pointer_resolve(std::string_view address) {
    auto j = impl_->do_json("GET", pointer_path(address, "/resolve"));
    return PointerTarget{
        .kind = str_at(j, "kind"),
        .kind_tag = kind_tag_at(j),
        .target = str_at(j, "target"),
    };
}

PointerFinality Client::pointer_finality(std::string_view address) {
    return parse_pointer_finality(impl_->do_json("GET", pointer_path(address, "/finality")));
}

PointerController Client::pointer_controller(std::string_view address) {
    auto j = impl_->do_json("GET", pointer_path(address, "/controller"));
    PointerController c;
    c.pointer = str_at(j, "pointer");
    c.frozen = bool_at(j, "frozen");
    if (const auto arr = j.find("transfers"); arr != j.end() && arr->is_array()) {
        for (const auto& t : *arr) {
            if (t.is_string()) c.transfers.push_back(t.get<std::string>());
        }
    }
    return c;
}

PointerPrepareResult Client::pointer_prepare(const PointerPrepareRequest& req) {
    json body = {{"owner", req.owner}, {"op", pointer_op_wire(req.op)}};
    if (req.op == PointerOp::Transfer) {
        body["recipient"] = req.recipient;
    } else {
        body["target"] = req.target;
        body["kind"] = pointer_kind_wire(req.kind);
    }
    if (req.include_signed_quotes) {
        body["include_signed_quotes"] = true;
    }
    auto j = impl_->do_json("POST", "/v1/pointers/prepare", body);

    PointerPrepareResult r;
    r.upload_id = str_at(j, "upload_id");
    r.op = str_at(j, "op");
    r.address = str_at(j, "address");
    r.state_id = str_at(j, "state_id");
    r.counter = counter_at(j, "counter");
    r.payment_type = str_at(j, "payment_type");
    r.total_amount = str_at(j, "total_amount");
    r.payment_vault_address = str_at(j, "payment_vault_address");
    r.payment_token_address = str_at(j, "payment_token_address");
    r.rpc_url = str_at(j, "rpc_url");
    if (const auto arr = j.find("payments"); arr != j.end() && arr->is_array()) {
        for (const auto& p : *arr) {
            if (!p.is_object()) continue;
            r.payments.push_back(PaymentInfo{
                .quote_hash = str_at(p, "quote_hash"),
                .rewards_address = str_at(p, "rewards_address"),
                .amount = str_at(p, "amount"),
            });
        }
    }
    if (const auto arr = j.find("signed_quotes"); arr != j.end() && arr->is_array()) {
        for (const auto& q : *arr) {
            if (!q.is_object()) continue;
            r.signed_quotes.push_back(SignedQuoteEntry{
                .quote_hash = str_at(q, "quote_hash"),
                .quote = str_at(q, "quote"),
                .commitment_sidecar = opt_str_at(q, "commitment_sidecar"),
            });
        }
    }
    return r;
}

PointerFinalizeResult Client::pointer_finalize(
    std::string_view upload_id, const std::map<std::string, std::string>& tx_hashes) {
    json hashes = json::object();
    for (const auto& [k, v] : tx_hashes) {
        hashes[k] = v;
    }
    auto j = impl_->do_json("POST", "/v1/pointers/finalize", json{
        {"upload_id", std::string(upload_id)},
        {"tx_hashes", hashes},
    });
    return PointerFinalizeResult{
        .address = str_at(j, "address"),
        .state_id = str_at(j, "state_id"),
        .counter = counter_at(j, "counter"),
        .finality = finality_at(j),
    };
}

}  // namespace antd
