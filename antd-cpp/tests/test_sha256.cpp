// ---------------------------------------------------------------------------
// sha256 field tests for antd::Client (REST), antd 0.17.0.
//
// A cpp-httplib stub daemon on 127.0.0.1 serves canned responses. Covers the
// upload results (data_put, data_put_public, file_put, file_put_public,
// finalize_upload and finalize_merkle_upload), each reading `sha256` when the
// key is present and std::nullopt when it is absent, `null` or empty; the
// manifest entry input (sent only when set and non-empty, as given); the
// manifest entry info on build and decode; and the daemon's 400 for a bad
// hash surfacing as BadRequestError with the message kept.
// ---------------------------------------------------------------------------

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <nlohmann/json.hpp>
#include <httplib.h>

#include <chrono>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "antd/client.hpp"
#include "antd/errors.hpp"
#include "antd/manifests.hpp"

using json = nlohmann::json;

namespace {

const std::string kSha(64, 'a');
const std::string kSha2 = std::string(32, '0') + std::string(32, 'f');

struct StubServer {
    httplib::Server svr;
    std::thread th;
    int port{0};

    std::mutex mu;
    json last_body = json::object();
    /// Merged into every upload response; tests set or clear "sha256".
    json sha_field = json::object();
    /// Merged into every manifest entry the manifest routes return.
    json entry_sha = json::object();
    /// When set, the manifest build route answers 400 with this message.
    std::string bad_request;

    void record(const httplib::Request& req) {
        std::lock_guard<std::mutex> lock(mu);
        try {
            last_body = req.body.empty() ? json::object() : json::parse(req.body);
        } catch (...) {
            last_body = json::object();
        }
    }

    json body() {
        std::lock_guard<std::mutex> lock(mu);
        return last_body;
    }

    void set_sha(json upload_sha, json entry_sha_) {
        std::lock_guard<std::mutex> lock(mu);
        sha_field = std::move(upload_sha);
        entry_sha = std::move(entry_sha_);
    }

    void upload_route(const char* path, json base) {
        svr.Post(path, [this, base](const httplib::Request& req, httplib::Response& res) {
            record(req);
            json out = base;
            {
                std::lock_guard<std::mutex> lock(mu);
                out.update(sha_field);
            }
            res.set_content(out.dump(), "application/json");
        });
    }

    json entry(const char* name) {
        json e = {{"effective_name", name}, {"path", name}, {"kind", "public"},
                  {"content_address", "cc"}};
        std::lock_guard<std::mutex> lock(mu);
        e.update(entry_sha);
        return e;
    }

    StubServer() {
        upload_route("/v1/data/public", {{"address", "pub"}, {"chunks_stored", 1}});
        upload_route("/v1/data", {{"data_map", "dm"}, {"chunks_stored", 1}});
        upload_route("/v1/files", {{"data_map", "fdm"}, {"chunks_stored", 2}});
        upload_route("/v1/files/public", {{"address", "fpub"}, {"chunks_stored", 2}});
        upload_route("/v1/upload/finalize", {{"data_map", "dm"}, {"chunks_stored", 3}});

        svr.Post("/v1/manifests/build", [this](const httplib::Request& req, httplib::Response& res) {
            record(req);
            {
                std::lock_guard<std::mutex> lock(mu);
                if (!bad_request.empty()) {
                    res.status = 400;
                    res.set_content(json{{"error", "Bad request: " + bad_request},
                                         {"code", "BAD_REQUEST"}}.dump(),
                                    "application/json");
                    return;
                }
            }
            res.set_content(json{{"manifest", "wUFOVAE="},
                                 {"entries", json::array({entry("a.txt")})}}.dump(),
                            "application/json");
        });
        svr.Post("/v1/manifests/decode", [this](const httplib::Request& req, httplib::Response& res) {
            record(req);
            res.set_content(json{{"source", "manifest"},
                                 {"entries", json::array({entry("a.txt")})}}.dump(),
                            "application/json");
        });

        port = svr.bind_to_any_port("127.0.0.1");
        th = std::thread([this] { svr.listen_after_bind(); });
        for (int i = 0; i < 100; ++i) {
            if (svr.is_running()) break;
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }

    ~StubServer() {
        svr.stop();
        if (th.joinable()) th.join();
    }

    std::string base_url() const { return "http://127.0.0.1:" + std::to_string(port); }
};

const std::vector<uint8_t> kData = {'h', 'i'};

/// Run `read` against the stub in each state: present, absent, null, empty.
template <typename Read>
void check_upload_sha(Read read) {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    stub.set_sha(json{{"sha256", kSha}}, json::object());
    CHECK(read(c) == std::optional<std::string>(kSha));

    stub.set_sha(json::object(), json::object());  // antd before 0.17.0
    CHECK_FALSE(read(c).has_value());

    stub.set_sha(json{{"sha256", nullptr}}, json::object());
    CHECK_FALSE(read(c).has_value());

    stub.set_sha(json{{"sha256", ""}}, json::object());
    CHECK_FALSE(read(c).has_value());
}

}  // namespace

TEST_CASE("data_put reads sha256, and none when absent, null or empty") {
    check_upload_sha([](antd::Client& c) { return c.data_put(kData).sha256; });
}

TEST_CASE("data_put_public reads sha256, and none when absent, null or empty") {
    check_upload_sha([](antd::Client& c) { return c.data_put_public(kData).sha256; });
}

TEST_CASE("file_put reads sha256, and none when absent, null or empty") {
    check_upload_sha([](antd::Client& c) { return c.file_put("/tmp/x").sha256; });
}

TEST_CASE("file_put_public reads sha256, and none when absent, null or empty") {
    check_upload_sha([](antd::Client& c) { return c.file_put_public("/tmp/x").sha256; });
}

TEST_CASE("finalize_upload (wave) reads sha256, and none when absent, null or empty") {
    check_upload_sha([](antd::Client& c) {
        return c.finalize_upload("up", {{"qh", "tx"}}).sha256;
    });
}

TEST_CASE("finalize_merkle_upload reads sha256, and none when absent, null or empty") {
    check_upload_sha([](antd::Client& c) {
        return c.finalize_merkle_upload("up", "pool").sha256;
    });
}

TEST_CASE("the sha256 of an upload result is passed through as the daemon sent it") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    stub.set_sha(json{{"sha256", "NOT-LOWERCASE-HEX"}}, json::object());
    CHECK(c.data_put_public(kData).sha256 == std::optional<std::string>("NOT-LOWERCASE-HEX"));
}

TEST_CASE("an upload result built without sha256 has none, and existing aggregates still compile") {
    CHECK_FALSE(antd::DataPutResult{}.sha256.has_value());
    CHECK_FALSE(antd::DataPutPublicResult{}.sha256.has_value());
    CHECK_FALSE(antd::FilePutResult{}.sha256.has_value());
    CHECK_FALSE(antd::FilePutPublicResult{}.sha256.has_value());
    CHECK_FALSE(antd::FinalizeUploadResult{}.sha256.has_value());
    // Positional construction without the new field keeps compiling: it is last.
    antd::DataPutResult r{"dm", 2, "single"};
    CHECK(r.chunks_stored == 2);
    CHECK_FALSE(r.sha256.has_value());
}

TEST_CASE("build_manifest sends sha256 on an entry that sets it, and omits it otherwise") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);

    antd::ManifestEntryInput with{.path = "a.txt", .address = "11", .sha256 = kSha2};
    antd::ManifestEntryInput none{.path = "b.txt", .address = "22"};
    antd::ManifestEntryInput empty{.path = "c.txt", .address = "33", .sha256 = std::string{}};
    // Passed through as given: no case folding, no validation.
    antd::ManifestEntryInput upper{.path = "d.txt", .address = "44", .sha256 = "ABCDEF"};
    c.build_manifest({with, none, empty, upper});

    const auto body = stub.body();
    REQUIRE(body["entries"].size() == 4);
    CHECK(body["entries"][0]["sha256"] == kSha2);
    CHECK_FALSE(body["entries"][1].contains("sha256"));
    CHECK_FALSE(body["entries"][2].contains("sha256"));
    CHECK(body["entries"][3]["sha256"] == "ABCDEF");
}

TEST_CASE("ManifestEntryInfo reads sha256 from build and decode, and none when absent or empty") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    const std::vector<antd::ManifestEntryInput> in = {{.path = "a.txt", .address = "11"}};

    stub.set_sha(json::object(), json{{"sha256", kSha}});
    CHECK(c.build_manifest(in).entries.at(0).sha256 == std::optional<std::string>(kSha));
    CHECK(c.decode_manifest_link("ant://manifest/x", false).entries.at(0).sha256 ==
          std::optional<std::string>(kSha));
    CHECK(c.decode_manifest({0xC1, 'A', 'N', 'T', 0x01}, false).entries.at(0).sha256 ==
          std::optional<std::string>(kSha));

    for (const json& absent : {json::object(), json{{"sha256", ""}}, json{{"sha256", nullptr}}}) {
        stub.set_sha(json::object(), absent);
        CHECK_FALSE(c.build_manifest(in).entries.at(0).sha256.has_value());
        CHECK_FALSE(c.decode_manifest_link("ant://manifest/x", false).entries.at(0).sha256.has_value());
    }
}

TEST_CASE("a 400 for a bad sha256 is a BadRequestError that keeps the daemon message") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    stub.bad_request = "entries[0]: invalid hex sha256: Odd number of digits";

    antd::ManifestEntryInput bad{.path = "a.txt", .address = "11", .sha256 = "zz"};
    try {
        c.build_manifest({bad});
        FAIL("expected BadRequestError");
    } catch (const antd::BadRequestError& e) {
        CHECK(e.status_code == 400);
        CHECK(std::string(e.what()).find("entries[0]: invalid hex sha256") != std::string::npos);
    }
    // The hash was sent as given, not checked client-side.
    CHECK(stub.body()["entries"][0]["sha256"] == "zz");
}
