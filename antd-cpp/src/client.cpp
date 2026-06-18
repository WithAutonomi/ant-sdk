#include "antd/client.hpp"

#include <nlohmann/json.hpp>
#include <httplib.h>

#include "base64.hpp"

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
            std::string msg = res->body;
            try {
                auto err_json = json::parse(res->body);
                if (err_json.contains("error") && err_json["error"].is_string()) {
                    msg = err_json["error"].get<std::string>();
                }
            } catch (...) {
                // Use raw body as message.
            }
            error_for_status(res->status, msg);
        }

        if (res->body.empty()) {
            return json::object();
        }

        return json::parse(res->body);
    }

    /// Perform a streaming request, forwarding each chunk of a 2xx response
    /// body to `sink` as it arrives (constant memory). Mirrors do_json's
    /// non-2xx handling: the error body is buffered and parsed for {"error"}.
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
            std::string msg = error_body;
            try {
                auto err_json = json::parse(error_body);
                if (err_json.contains("error") && err_json["error"].is_string()) {
                    msg = err_json["error"].get<std::string>();
                }
            } catch (...) {
                // Use raw body as message.
            }
            error_for_status(status, msg);
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

}  // namespace antd
