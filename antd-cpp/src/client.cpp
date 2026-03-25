#include "antd/client.hpp"

#include <nlohmann/json.hpp>
#include <httplib.h>

#include "base64.hpp"

namespace antd {

using json = nlohmann::json;

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
    };
}

// ---------------------------------------------------------------------------
// Data (Immutable)
// ---------------------------------------------------------------------------

PutResult Client::data_put_public(const std::vector<uint8_t>& data) {
    auto j = impl_->do_json("POST", "/v1/data/public", json{
        {"data", detail::base64_encode(data)},
    });
    return PutResult{
        .cost = j.value("cost", ""),
        .address = j.value("address", ""),
    };
}

std::vector<uint8_t> Client::data_get_public(std::string_view address) {
    auto j = impl_->do_json("GET", "/v1/data/public/" + std::string(address));
    return detail::base64_decode(j.value("data", ""));
}

PutResult Client::data_put_private(const std::vector<uint8_t>& data) {
    auto j = impl_->do_json("POST", "/v1/data/private", json{
        {"data", detail::base64_encode(data)},
    });
    return PutResult{
        .cost = j.value("cost", ""),
        .address = j.value("data_map", ""),
    };
}

std::vector<uint8_t> Client::data_get_private(std::string_view data_map) {
    auto j = impl_->do_json("GET",
        "/v1/data/private?data_map=" + std::string(data_map));
    return detail::base64_decode(j.value("data", ""));
}

std::string Client::data_cost(const std::vector<uint8_t>& data) {
    auto j = impl_->do_json("POST", "/v1/data/cost", json{
        {"data", detail::base64_encode(data)},
    });
    return j.value("cost", "");
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

// ---------------------------------------------------------------------------
// Graph Entries (DAG Nodes)
// ---------------------------------------------------------------------------

PutResult Client::graph_entry_put(std::string_view owner_secret_key,
                                   const std::vector<std::string>& parents,
                                   std::string_view content,
                                   const std::vector<GraphDescendant>& descendants) {
    json descs = json::array();
    for (const auto& d : descendants) {
        descs.push_back(json{{"public_key", d.public_key}, {"content", d.content}});
    }

    auto j = impl_->do_json("POST", "/v1/graph", json{
        {"owner_secret_key", std::string(owner_secret_key)},
        {"parents", parents},
        {"content", std::string(content)},
        {"descendants", descs},
    });
    return PutResult{
        .cost = j.value("cost", ""),
        .address = j.value("address", ""),
    };
}

GraphEntry Client::graph_entry_get(std::string_view address) {
    auto j = impl_->do_json("GET", "/v1/graph/" + std::string(address));

    GraphEntry entry;
    entry.owner = j.value("owner", "");
    entry.content = j.value("content", "");

    if (j.contains("parents") && j["parents"].is_array()) {
        for (const auto& p : j["parents"]) {
            if (p.is_string()) {
                entry.parents.push_back(p.get<std::string>());
            }
        }
    }

    if (j.contains("descendants") && j["descendants"].is_array()) {
        for (const auto& d : j["descendants"]) {
            if (d.is_object()) {
                entry.descendants.push_back(GraphDescendant{
                    .public_key = d.value("public_key", ""),
                    .content = d.value("content", ""),
                });
            }
        }
    }

    return entry;
}

bool Client::graph_entry_exists(std::string_view address) {
    int code = impl_->do_head("/v1/graph/" + std::string(address));
    if (code == 404) {
        return false;
    }
    if (code >= 300) {
        error_for_status(code, "graph entry exists check failed");
    }
    return true;
}

std::string Client::graph_entry_cost(std::string_view public_key) {
    auto j = impl_->do_json("POST", "/v1/graph/cost", json{
        {"public_key", std::string(public_key)},
    });
    return j.value("cost", "");
}

// ---------------------------------------------------------------------------
// Files & Directories
// ---------------------------------------------------------------------------

PutResult Client::file_upload_public(std::string_view path) {
    auto j = impl_->do_json("POST", "/v1/files/upload/public", json{
        {"path", std::string(path)},
    });
    return PutResult{
        .cost = j.value("cost", ""),
        .address = j.value("address", ""),
    };
}

void Client::file_download_public(std::string_view address, std::string_view dest_path) {
    impl_->do_json("POST", "/v1/files/download/public", json{
        {"address", std::string(address)},
        {"dest_path", std::string(dest_path)},
    });
}

PutResult Client::dir_upload_public(std::string_view path) {
    auto j = impl_->do_json("POST", "/v1/dirs/upload/public", json{
        {"path", std::string(path)},
    });
    return PutResult{
        .cost = j.value("cost", ""),
        .address = j.value("address", ""),
    };
}

void Client::dir_download_public(std::string_view address, std::string_view dest_path) {
    impl_->do_json("POST", "/v1/dirs/download/public", json{
        {"address", std::string(address)},
        {"dest_path", std::string(dest_path)},
    });
}

Archive Client::archive_get_public(std::string_view address) {
    auto j = impl_->do_json("GET", "/v1/archives/public/" + std::string(address));

    Archive archive;
    if (j.contains("entries") && j["entries"].is_array()) {
        for (const auto& e : j["entries"]) {
            if (e.is_object()) {
                archive.entries.push_back(ArchiveEntry{
                    .path = e.value("path", ""),
                    .address = e.value("address", ""),
                    .created = e.value("created", int64_t{0}),
                    .modified = e.value("modified", int64_t{0}),
                    .size = e.value("size", int64_t{0}),
                });
            }
        }
    }

    return archive;
}

PutResult Client::archive_put_public(const Archive& archive) {
    json entries = json::array();
    for (const auto& e : archive.entries) {
        entries.push_back(json{
            {"path", e.path},
            {"address", e.address},
            {"created", e.created},
            {"modified", e.modified},
            {"size", e.size},
        });
    }

    auto j = impl_->do_json("POST", "/v1/archives/public", json{
        {"entries", entries},
    });
    return PutResult{
        .cost = j.value("cost", ""),
        .address = j.value("address", ""),
    };
}

std::string Client::file_cost(std::string_view path, bool is_public, bool include_archive) {
    auto j = impl_->do_json("POST", "/v1/cost/file", json{
        {"path", std::string(path)},
        {"is_public", is_public},
        {"include_archive", include_archive},
    });
    return j.value("cost", "");
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

}  // namespace antd
