#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <nlohmann/json.hpp>
#include <httplib.h>

#include <chrono>
#include <future>
#include <thread>

#include "antd/async_client.hpp"
#include "antd/errors.hpp"
#include "antd/models.hpp"

using json = nlohmann::json;

namespace {

// Minimal in-process stub server: register every route an AsyncClient
// smoke-test might hit, return a canned JSON body. Parsing edge cases are
// covered by test_client.cpp on the sync Client.
struct StubServer {
    httplib::Server svr;
    std::thread th;
    int port{0};

    json last_prepare_body = json::object();
    json last_data_prepare_body = json::object();
    json last_finalize_body = json::object();
    json last_wallet_approve_body = json::object();

    StubServer() {
        svr.Get("/health", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"status":"ok","network":"local","version":"0.8.0",
                              "evm_network":"local","uptime_seconds":42,"build_commit":"dead",
                              "payment_token_address":"0xt","payment_vault_address":"0xv"})",
                            "application/json");
        });

        // --- Wallet ---
        svr.Get("/v1/wallet/address", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"address":"0xwallet"})", "application/json");
        });
        svr.Get("/v1/wallet/balance", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"balance":"1234","gas_balance":"5678"})", "application/json");
        });
        svr.Post("/v1/wallet/approve", [this](const httplib::Request& req, httplib::Response& res) {
            try { last_wallet_approve_body = json::parse(req.body); } catch (...) {}
            res.set_content(R"({"approved":true})", "application/json");
        });

        // --- External-signer prepare/finalize ---
        svr.Post("/v1/upload/prepare", [this](const httplib::Request& req, httplib::Response& res) {
            try { last_prepare_body = json::parse(req.body); } catch (...) {}
            res.set_content(R"({"upload_id":"up1","payment_type":"wave_batch",
                              "payments":[{"quote_hash":"qh1","rewards_address":"ra1","amount":"100"}],
                              "total_amount":"100","payment_vault_address":"0xv",
                              "payment_token_address":"0xt","rpc_url":"http://localhost:8545"})",
                            "application/json");
        });
        svr.Post("/v1/data/prepare", [this](const httplib::Request& req, httplib::Response& res) {
            try { last_data_prepare_body = json::parse(req.body); } catch (...) {}
            res.set_content(R"({"upload_id":"dup1","payment_type":"wave_batch",
                              "payments":[],"total_amount":"0","payment_vault_address":"0xv2",
                              "payment_token_address":"0xt2","rpc_url":"http://localhost:8545"})",
                            "application/json");
        });
        svr.Post("/v1/upload/finalize", [this](const httplib::Request& req, httplib::Response& res) {
            try { last_finalize_body = json::parse(req.body); } catch (...) {}
            res.set_content(R"({"address":"addrfin","chunks_stored":3,
                              "data_map":"dm","data_map_address":"dma"})",
                            "application/json");
        });

        // --- Existing async (smoke coverage) ---
        svr.Post("/v1/chunks", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"cost":"50","address":"chk1"})", "application/json");
        });
        svr.Get(R"(/v1/chunks/(\w+))", [](const httplib::Request&, httplib::Response& res) {
            // base64("chunk-bytes") = "Y2h1bmstYnl0ZXM="
            res.set_content(R"({"data":"Y2h1bmstYnl0ZXM="})", "application/json");
        });
        svr.Post("/v1/chunks/prepare", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"address":"chk2","already_stored":false,"upload_id":"cup1",
                              "payment_type":"wave_batch",
                              "payments":[{"quote_hash":"qh2","rewards_address":"ra2","amount":"75"}],
                              "total_amount":"75","payment_vault_address":"0xv",
                              "payment_token_address":"0xt","rpc_url":"http://localhost:8545"})",
                            "application/json");
        });
        svr.Post("/v1/chunks/finalize", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"address":"chkfin"})", "application/json");
        });
        svr.Post("/v1/data", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"data_map":"dmap","chunks_stored":2,"payment_mode_used":"single"})",
                            "application/json");
        });
        svr.Post("/v1/data/get", [](const httplib::Request&, httplib::Response& res) {
            // base64("private-bytes") = "cHJpdmF0ZS1ieXRlcw=="
            res.set_content(R"({"data":"cHJpdmF0ZS1ieXRlcw=="})", "application/json");
        });
        svr.Post("/v1/data/public", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"address":"pubaddr","chunks_stored":2,"payment_mode_used":"single"})",
                            "application/json");
        });
        svr.Get(R"(/v1/data/public/(\w+))", [](const httplib::Request&, httplib::Response& res) {
            // base64("public-bytes") = "cHVibGljLWJ5dGVz"
            res.set_content(R"({"data":"cHVibGljLWJ5dGVz"})", "application/json");
        });
        svr.Post("/v1/data/cost", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"cost":"500","file_size":100,"chunk_count":1,
                              "estimated_gas_cost_wei":"21000","payment_mode":"single"})",
                            "application/json");
        });
        svr.Post("/v1/files", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"data_map":"fdmap","storage_cost_atto":"1000",
                              "gas_cost_wei":"21000","chunks_stored":4,"payment_mode_used":"single"})",
                            "application/json");
        });
        svr.Post("/v1/files/get", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({})", "application/json");
        });
        svr.Post("/v1/files/public", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"address":"fpub","storage_cost_atto":"2000",
                              "gas_cost_wei":"21000","chunks_stored":4,"payment_mode_used":"single"})",
                            "application/json");
        });
        svr.Post("/v1/files/public/get", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({})", "application/json");
        });
        svr.Post("/v1/files/cost", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"cost":"3000","file_size":200,"chunk_count":2,
                              "estimated_gas_cost_wei":"42000","payment_mode":"single"})",
                            "application/json");
        });

        port = svr.bind_to_any_port("127.0.0.1");
        th = std::thread([this] { svr.listen_after_bind(); });
        // Wait until the server reports running (httplib does this synchronously
        // once listen_after_bind starts, but give the OS a tick).
        for (int i = 0; i < 50 && !svr.is_running(); ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }

    ~StubServer() {
        svr.stop();
        if (th.joinable()) th.join();
    }

    std::string base_url() const {
        return "http://127.0.0.1:" + std::to_string(port);
    }
};

}  // namespace

// ---------------------------------------------------------------------------
// Sanity: every async method returns a std::future that resolves correctly
// ---------------------------------------------------------------------------

TEST_CASE("async health round-trip") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    auto h = c.health().get();
    CHECK(h.ok);
    CHECK(h.network == "local");
}

// --- Wallet (newly added in V2-287) ---

TEST_CASE("async wallet_address returns address") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    CHECK(c.wallet_address().get().address == "0xwallet");
}

TEST_CASE("async wallet_balance returns balance + gas") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    auto b = c.wallet_balance().get();
    CHECK(b.balance == "1234");
    CHECK(b.gas_balance == "5678");
}

TEST_CASE("async wallet_approve returns true on success") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    CHECK(c.wallet_approve().get() == true);
}

// --- External-signer prepare/finalize (newly added in V2-287) ---

TEST_CASE("async prepare_upload (no visibility) forwards path") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    auto r = c.prepare_upload("/tmp/file.bin").get();
    CHECK(r.upload_id == "up1");
    CHECK(r.payment_type == "wave_batch");
    CHECK(s.last_prepare_body["path"] == "/tmp/file.bin");
    CHECK_FALSE(s.last_prepare_body.contains("visibility"));
}

TEST_CASE("async prepare_upload with visibility forwards both") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    auto r = c.prepare_upload("/tmp/file.bin", std::string("public")).get();
    CHECK(r.upload_id == "up1");
    CHECK(s.last_prepare_body["visibility"] == "public");
}

TEST_CASE("async prepare_upload_public is equivalent to visibility=public") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    auto r = c.prepare_upload_public("/tmp/file.bin").get();
    CHECK(r.upload_id == "up1");
    CHECK(s.last_prepare_body["visibility"] == "public");
}

TEST_CASE("async prepare_data_upload base64-encodes data") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    std::vector<uint8_t> data{'h','e','l','l','o'};
    auto r = c.prepare_data_upload(data).get();
    CHECK(r.upload_id == "dup1");
    CHECK(r.payments.empty());
    CHECK(s.last_data_prepare_body.contains("data"));
}

TEST_CASE("async finalize_upload returns data_map + data_map_address") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    std::map<std::string, std::string> hashes{{"qh1", "tx1"}};
    auto r = c.finalize_upload("up1", hashes).get();
    CHECK(r.address == "addrfin");
    CHECK(r.chunks_stored == 3);
    CHECK(r.data_map == "dm");
    CHECK(r.data_map_address == "dma");
    CHECK(s.last_finalize_body["upload_id"] == "up1");
}

TEST_CASE("async finalize_merkle_upload forwards winner_pool_hash") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    auto r = c.finalize_merkle_upload("up1", "0xwinner").get();
    CHECK(r.address == "addrfin");
    CHECK(s.last_finalize_body["winner_pool_hash"] == "0xwinner");
}

// --- Existing async methods (smoke coverage — previously untested) ---

TEST_CASE("async chunk_put + chunk_get round-trip") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    std::vector<uint8_t> data{'h','i'};
    auto put = c.chunk_put(data).get();
    CHECK(put.address == "chk1");
    CHECK(put.cost == "50");
    auto got = c.chunk_get("chk1").get();
    CHECK(std::string(got.begin(), got.end()) == "chunk-bytes");
}

TEST_CASE("async prepare_chunk_upload + finalize_chunk_upload") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    std::vector<uint8_t> data{'h','i'};
    auto prep = c.prepare_chunk_upload(data).get();
    CHECK(prep.address == "chk2");
    CHECK_FALSE(prep.already_stored);
    auto fin = c.finalize_chunk_upload("cup1", {{"qh2","tx2"}}).get();
    CHECK(fin == "chkfin");
}

TEST_CASE("async data_put + data_get round-trip") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    std::vector<uint8_t> data{'h','i'};
    auto put = c.data_put(data).get();
    CHECK(put.data_map == "dmap");
    CHECK(put.chunks_stored == 2);
    auto got = c.data_get("dmap").get();
    CHECK(std::string(got.begin(), got.end()) == "private-bytes");
}

TEST_CASE("async data_put_public + data_get_public round-trip") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    std::vector<uint8_t> data{'h','i'};
    auto put = c.data_put_public(data).get();
    CHECK(put.address == "pubaddr");
    auto got = c.data_get_public("pubaddr").get();
    CHECK(std::string(got.begin(), got.end()) == "public-bytes");
}

TEST_CASE("async data_cost") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    auto est = c.data_cost({'h','i'}).get();
    CHECK(est.cost == "500");
    CHECK(est.file_size == 100);
}

TEST_CASE("async file_put + file_get round-trip") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    auto put = c.file_put("/tmp/x").get();
    CHECK(put.data_map == "fdmap");
    CHECK(put.storage_cost_atto == "1000");
    c.file_get("fdmap", "/tmp/dst").get();  // void: should not throw
}

TEST_CASE("async file_put_public + file_get_public round-trip") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    auto put = c.file_put_public("/tmp/x").get();
    CHECK(put.address == "fpub");
    c.file_get_public("fpub", "/tmp/dst").get();  // void
}

TEST_CASE("async file_cost") {
    StubServer s;
    antd::AsyncClient c(s.base_url());
    auto est = c.file_cost("/tmp/x", true).get();
    CHECK(est.cost == "3000");
    CHECK(est.file_size == 200);
}

// ---------------------------------------------------------------------------
// Exception propagation: future.get() rethrows
// ---------------------------------------------------------------------------

TEST_CASE("async errors propagate through future.get()") {
    // No server running — connection should fail and propagate.
    antd::AsyncClient c("http://127.0.0.1:1");  // port 1, unbound
    auto f = c.health();
    CHECK_THROWS(f.get());
}
