// ---------------------------------------------------------------------------
// Manifest API tests for antd::Client (REST) and antd::AsyncClient.
//
// A cpp-httplib stub daemon on 127.0.0.1 serves canned /v1/manifests
// responses; the tests drive the real Client request/response path: the
// base64 round trip of the `.ant` bytes, request bodies (the `embed_roots`
// default, omitted unset fields), unset sizes reading as std::nullopt rather
// than 0, the both-or-neither entry check made before anything is sent, and
// the 400 mapping to BadRequestError.
// ---------------------------------------------------------------------------

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <nlohmann/json.hpp>
#include <httplib.h>

#include <chrono>
#include <cstdint>
#include <limits>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "antd/async_client.hpp"
#include "antd/client.hpp"
#include "antd/errors.hpp"
#include "antd/manifests.hpp"

using json = nlohmann::json;

namespace {

/// The five-byte `.ant` header; "wUFOVAE=" is its base64.
const std::vector<uint8_t> kHeader = {0xC1, 'A', 'N', 'T', 0x01};
const char* const kHeaderB64 = "wUFOVAE=";

/// Every byte value, so the base64 round trip covers the whole alphabet and
/// all three padding cases (256 % 3 == 1; 255 and 254 bytes for the others).
std::vector<uint8_t> all_bytes(std::size_t n = 256) {
    std::vector<uint8_t> out(n);
    for (std::size_t i = 0; i < n; ++i) out[i] = static_cast<uint8_t>(i);
    return out;
}

void reply(httplib::Response& res, const json& body) {
    res.set_content(body.dump(), "application/json");
}

struct StubServer {
    httplib::Server svr;
    std::thread th;
    int port{0};

    std::mutex mu;
    int requests{0};
    std::string last_path;
    json last_body = json::object();
    /// What POST /v1/manifests/build returns; tests replace it.
    json build_response;
    /// What POST /v1/manifests/decode returns; tests replace it.
    json decode_response;
    /// When set, both routes answer 400 with this message.
    std::string bad_request;

    void record(const httplib::Request& req) {
        std::lock_guard<std::mutex> lock(mu);
        ++requests;
        last_path = req.path;
        try {
            last_body = req.body.empty() ? json::object() : json::parse(req.body);
        } catch (...) {
            last_body = json::object();
        }
    }

    bool answer_bad_request(httplib::Response& res) {
        std::lock_guard<std::mutex> lock(mu);
        if (bad_request.empty()) return false;
        res.status = 400;
        reply(res, {{"error", bad_request}, {"code", "BAD_REQUEST"}});
        return true;
    }

    StubServer() {
        build_response = {
            {"manifest", kHeaderB64},
            {"link", "ant://manifest/wUFOVAE"},
            {"entries", json::array({
                {{"effective_name", "a.txt"}, {"path", "a.txt"}, {"size", 10},
                 {"kind", "embedded"}, {"content_address", "cc"}, {"exact_size", 10}},
                {{"effective_name", "11"}, {"kind", "public"}, {"content_address", "11"}},
            })},
        };
        decode_response = {
            {"source", "manifest"},
            {"name", "album"},
            {"torrent_info_hash_v2", "bb"},
            {"entries", json::array({
                {{"effective_name", "a.txt"}, {"path", "a.txt"}, {"kind", "embedded"},
                 {"content_address", "cc"}, {"data_map", "abcd"}, {"exact_size", 3}},
                {{"effective_name", "b"}, {"path", "b"}, {"kind", "public"},
                 {"content_address", "dd"}, {"error", "Record not found: gone"}},
            })},
        };

        svr.Post("/v1/manifests/build", [this](const httplib::Request& req, httplib::Response& res) {
            record(req);
            if (answer_bad_request(res)) return;
            std::lock_guard<std::mutex> lock(mu);
            reply(res, build_response);
        });
        svr.Post("/v1/manifests/decode", [this](const httplib::Request& req, httplib::Response& res) {
            record(req);
            if (answer_bad_request(res)) return;
            std::lock_guard<std::mutex> lock(mu);
            reply(res, decode_response);
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

    json body() {
        std::lock_guard<std::mutex> lock(mu);
        return last_body;
    }

    std::string path() {
        std::lock_guard<std::mutex> lock(mu);
        return last_path;
    }

    int count() {
        std::lock_guard<std::mutex> lock(mu);
        return requests;
    }

    void set_build_response(json j) {
        std::lock_guard<std::mutex> lock(mu);
        build_response = std::move(j);
    }

    void set_decode_response(json j) {
        std::lock_guard<std::mutex> lock(mu);
        decode_response = std::move(j);
    }

    void set_bad_request(std::string msg) {
        std::lock_guard<std::mutex> lock(mu);
        bad_request = std::move(msg);
    }
};

}  // namespace

// ---------------------------------------------------------------------------
// build_manifest
// ---------------------------------------------------------------------------

TEST_CASE("build_manifest sends entries and options, and returns raw bytes") {
    StubServer s;
    antd::Client client(s.base_url());

    antd::BuildManifestOptions opts;
    opts.name = "album";
    opts.keep_shrunk_data_maps = true;
    const auto res = client.build_manifest(
        {
            {.path = "a.txt", .size = 10, .data_map = "abcd"},
            {.address = "11"},
        },
        opts);

    CHECK(s.path() == "/v1/manifests/build");
    const auto body = s.body();
    CHECK(body["name"] == "album");
    CHECK(body["embed_roots"] == false);
    CHECK_FALSE(body.contains("torrent_info_hashes"));
    REQUIRE(body["entries"].size() == 2);
    const auto& first = body["entries"][0];
    CHECK(first["path"] == "a.txt");
    CHECK(first["data_map"] == "abcd");
    CHECK(first["size"] == 10);
    CHECK_FALSE(first.contains("address"));
    const auto& second = body["entries"][1];
    CHECK(second["address"] == "11");
    CHECK_FALSE(second.contains("path"));
    CHECK_FALSE(second.contains("size"));
    CHECK_FALSE(second.contains("data_map"));

    CHECK(res.manifest == kHeader);
    CHECK(res.link == "ant://manifest/wUFOVAE");
    REQUIRE(res.entries.size() == 2);
    const auto& a = res.entries[0];
    CHECK(a.effective_name == "a.txt");
    CHECK(a.path == std::optional<std::string>("a.txt"));
    CHECK(a.kind == "embedded");
    CHECK(a.content_address == "cc");
    CHECK(a.size == std::optional<std::uint64_t>(10));
    CHECK(a.exact_size == std::optional<std::uint64_t>(10));
    const auto& p = res.entries[1];
    CHECK(p.kind == "public");
    CHECK(p.effective_name == "11");
    CHECK_FALSE(p.path.has_value());
    CHECK_FALSE(p.size.has_value());
    CHECK_FALSE(p.exact_size.has_value());
    CHECK(p.data_map.empty());
    CHECK(p.error.empty());
}

TEST_CASE("build_manifest embeds roots by default and omits unset options") {
    StubServer s;
    s.set_build_response({{"manifest", ""}, {"entries", json::array()}});
    antd::Client client(s.base_url());

    const auto res = client.build_manifest({{.address = "11"}});

    const auto body = s.body();
    CHECK(body["embed_roots"] == true);
    CHECK_FALSE(body.contains("name"));
    CHECK_FALSE(body.contains("torrent_info_hashes"));
    // A response without a link (it did not fit 1,500 bytes) reads as "".
    CHECK(res.link.empty());
    CHECK(res.manifest.empty());
    CHECK(res.entries.empty());
}

TEST_CASE("build_manifest sends torrent info hashes") {
    StubServer s;
    antd::Client client(s.base_url());
    const std::string v1(40, 'a');
    const std::string v2(64, 'b');

    antd::BuildManifestOptions opts;
    opts.torrent_info_hashes = {v1, v2};
    (void)client.build_manifest({{.address = "11"}}, opts);

    CHECK(s.body()["torrent_info_hashes"] == json::array({v1, v2}));
    CHECK(s.body()["embed_roots"] == true);
}

TEST_CASE("build_manifest refuses an entry with both or neither source before sending") {
    StubServer s;
    antd::Client client(s.base_url());

    const std::vector<antd::ManifestEntryInput> both = {
        {.address = "11"},
        {.data_map = "aa", .address = "bb"},
    };
    const std::vector<antd::ManifestEntryInput> neither = {{.path = "x.txt"}};

    const std::string prefix = "antd error 400: ";
    const std::vector<antd::ManifestEntryInput> two_bad = {
        {.data_map = "aa", .address = "bb"},
        {.address = "11"},
        {.path = "x.txt"},
    };
    struct Case {
        const std::vector<antd::ManifestEntryInput>* in;
        const char* msg;
    };
    const Case cases[] = {
        {&both, "1 invalid entries: entries[1]: give data_map or address, not both"},
        {&neither, "1 invalid entries: entries[0]: needs a data_map or an address"},
        {&two_bad,
         "2 invalid entries: entries[0]: give data_map or address, not both; "
         "entries[2]: needs a data_map or an address"},
    };
    for (const auto& c : cases) {
        try {
            (void)client.build_manifest(*c.in);
            FAIL("expected BadRequestError");
        } catch (const antd::BadRequestError& e) {
            CHECK(e.status_code == 400);
            CHECK(std::string(e.what()) == prefix + c.msg);
        }
    }
    // An empty string counts as unset, and past 20 the rest are counted.
    std::vector<antd::ManifestEntryInput> many(22);
    try {
        (void)client.build_manifest(many);
        FAIL("expected BadRequestError");
    } catch (const antd::BadRequestError& e) {
        const std::string m = e.what();
        CHECK(m.rfind(prefix + "22 invalid entries: entries[0]: needs a data_map or an address; ", 0) == 0);
        CHECK(m.find("entries[19]: needs") != std::string::npos);
        CHECK(m.find("entries[20]") == std::string::npos);
        CHECK(m.size() >= 12);
        CHECK(m.substr(m.size() - 12) == "; and 2 more");
    }
    CHECK(s.count() == 0);
}

TEST_CASE("an unset size reads as nullopt, and a recorded 0 as 0") {
    StubServer s;
    s.set_build_response({
        {"manifest", kHeaderB64},
        {"entries", json::array({
            {{"effective_name", "zero"}, {"kind", "public"}, {"size", 0}, {"exact_size", 0}},
            {{"effective_name", "null"}, {"kind", "public"}, {"size", nullptr},
             {"exact_size", nullptr}},
            {{"effective_name", "absent"}, {"kind", "public"}},
            {{"effective_name", "negative"}, {"kind", "public"}, {"size", -1}},
            {{"effective_name", "string"}, {"kind", "public"}, {"size", "10"}},
            {{"effective_name", "big"}, {"kind", "public"},
             {"size", std::numeric_limits<std::uint64_t>::max()}},
        })},
    });
    antd::Client client(s.base_url());

    const auto res = client.build_manifest({{.address = "11"}});
    REQUIRE(res.entries.size() == 6);
    CHECK(res.entries[0].size == std::optional<std::uint64_t>(0));
    CHECK(res.entries[0].exact_size == std::optional<std::uint64_t>(0));
    for (std::size_t i = 1; i < 5; ++i) {
        INFO(res.entries[i].effective_name);
        CHECK_FALSE(res.entries[i].size.has_value());
        CHECK_FALSE(res.entries[i].exact_size.has_value());
    }
    CHECK(res.entries[5].size ==
          std::optional<std::uint64_t>(std::numeric_limits<std::uint64_t>::max()));
}

TEST_CASE("build_manifest sends an explicit size of 0") {
    StubServer s;
    antd::Client client(s.base_url());
    (void)client.build_manifest({{.size = 0, .address = "11"}});
    REQUIRE(s.body()["entries"][0].contains("size"));
    CHECK(s.body()["entries"][0]["size"] == 0);
}

TEST_CASE("a build response with invalid base64 is an InternalError") {
    StubServer s;
    s.set_build_response({{"manifest", "not base64!"}, {"entries", json::array()}});
    antd::Client client(s.base_url());
    CHECK_THROWS_AS(client.build_manifest({{.address = "11"}}), antd::InternalError);
}

// ---------------------------------------------------------------------------
// decode_manifest / decode_manifest_link
// ---------------------------------------------------------------------------

TEST_CASE("decode_manifest sends base64 bytes and parses the response") {
    StubServer s;
    antd::Client client(s.base_url());

    const auto res = client.decode_manifest(kHeader, true);

    CHECK(s.path() == "/v1/manifests/decode");
    CHECK(s.body()["manifest"] == kHeaderB64);
    CHECK(s.body()["resolve"] == true);
    CHECK_FALSE(s.body().contains("link"));

    CHECK(res.source == "manifest");
    CHECK(res.name == std::optional<std::string>("album"));
    CHECK(res.torrent_info_hash_v1.empty());
    CHECK(res.torrent_info_hash_v2 == "bb");
    REQUIRE(res.entries.size() == 2);
    CHECK(res.entries[0].data_map == "abcd");
    CHECK(res.entries[0].exact_size == std::optional<std::uint64_t>(3));
    CHECK_FALSE(res.entries[0].size.has_value());
    CHECK(res.entries[0].error.empty());
    CHECK(res.entries[1].error == "Record not found: gone");
    CHECK_FALSE(res.entries[1].exact_size.has_value());
    CHECK(res.entries[1].data_map.empty());
}

TEST_CASE("decode_manifest_link sends the link and no bytes") {
    StubServer s;
    s.set_decode_response({
        {"source", "file_link"},
        {"entries", json::array({
            {{"effective_name", "42"}, {"kind", "public"}, {"content_address", "42"}},
        })},
    });
    antd::Client client(s.base_url());

    const auto res = client.decode_manifest_link("ant://manifest/wUFOVAE");

    CHECK(s.body()["link"] == "ant://manifest/wUFOVAE");
    CHECK(s.body()["resolve"] == false);
    CHECK_FALSE(s.body().contains("manifest"));
    CHECK(res.source == "file_link");
    CHECK_FALSE(res.name.has_value());
    REQUIRE(res.entries.size() == 1);
    CHECK_FALSE(res.entries[0].path.has_value());
}

TEST_CASE("the .ant bytes survive the base64 round trip") {
    for (std::size_t n : {256u, 255u, 254u, 1u}) {
        INFO("n = " << n);
        StubServer s;
        antd::Client client(s.base_url());
        const auto bytes = all_bytes(n);

        (void)client.decode_manifest(bytes);
        const json sent = s.body()["manifest"];
        REQUIRE(sent.is_string());

        // Hand the base64 the client sent back as a build response.
        s.set_build_response({{"manifest", sent}, {"entries", json::array()}});
        const auto built = client.build_manifest({{.address = "11"}});
        CHECK(built.manifest == bytes);
    }
}

TEST_CASE("empty bytes or an empty link are refused before sending") {
    StubServer s;
    antd::Client client(s.base_url());
    for (int i = 0; i < 2; ++i) {
        try {
            if (i == 0) (void)client.decode_manifest({});
            else (void)client.decode_manifest_link("");
            FAIL("expected BadRequestError");
        } catch (const antd::BadRequestError& e) {
            CHECK(e.status_code == 400);
            CHECK(std::string(e.what()) ==
                  "antd error 400: needs a manifest (base64 .ant bytes) or a link");
        }
    }
    CHECK(s.count() == 0);
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

TEST_CASE("a 400 is a BadRequestError that keeps the daemon's message") {
    StubServer s;
    s.set_bad_request("Bad request: entries[0]: invalid path \"../x\"");
    antd::Client client(s.base_url());

    try {
        (void)client.build_manifest({{.path = "../x", .address = "11"}});
        FAIL("expected BadRequestError");
    } catch (const antd::BadRequestError& e) {
        CHECK(std::string(e.what()).find("entries[0]: invalid path") != std::string::npos);
    }
    CHECK_THROWS_AS(client.decode_manifest(std::vector<uint8_t>{'n', 'o'}),
                    antd::BadRequestError);
    CHECK_THROWS_AS(client.decode_manifest_link("nope"), antd::BadRequestError);
}

// ---------------------------------------------------------------------------
// AsyncClient
// ---------------------------------------------------------------------------

TEST_CASE("AsyncClient manifest methods") {
    StubServer s;
    antd::AsyncClient client(s.base_url());

    auto built = client.build_manifest({{.path = "a.txt", .data_map = "abcd"}}).get();
    CHECK(built.manifest == kHeader);
    CHECK(s.body()["embed_roots"] == true);

    auto decoded = client.decode_manifest(kHeader, true).get();
    CHECK(s.body()["manifest"] == kHeaderB64);
    CHECK(decoded.name == std::optional<std::string>("album"));

    auto linked = client.decode_manifest_link("ant://manifest/wUFOVAE", true).get();
    CHECK(s.body()["link"] == "ant://manifest/wUFOVAE");
    CHECK(s.body()["resolve"] == true);
    CHECK(linked.entries.size() == 2);

    const int before = s.count();
    auto bad = client.build_manifest(std::vector<antd::ManifestEntryInput>{antd::ManifestEntryInput{}});
    CHECK_THROWS_AS(bad.get(), antd::BadRequestError);
    CHECK(s.count() == before);
}
