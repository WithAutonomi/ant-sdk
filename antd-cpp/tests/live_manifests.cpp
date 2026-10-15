// ---------------------------------------------------------------------------
// Live manifest build and decode against a running antd with a devnet behind
// it. Nothing is uploaded or paid for: the manifests describe fixtures that
// are already on the network.
//
// Skipped unless ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES are set (and,
// in a gRPC build, ANTD_TEST_GRPC). The rest are read when present:
//
//   ANTD_TEST_URL                     the daemon's REST base URL
//   ANTD_TEST_GRPC                    its gRPC target (gRPC builds only:
//                                     -DANTD_BUILD_GRPC=ON)
//   ANTD_TEST_MANIFEST_ADDRESSES      two public data addresses, comma-separated
//   ANTD_TEST_MANIFEST_SIZES          their exact plaintext sizes, comma-separated
//   ANTD_TEST_MANIFEST_DATA_MAP       a private upload's hex DataMap
//   ANTD_TEST_MANIFEST_DATA_MAP_SIZE  its exact plaintext size
//   ANTD_TEST_MANIFEST_LINK           an ant://manifest/ link of those three
//
//   export ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051
//   ANTD_TEST_MANIFEST_ADDRESSES=<hex>,<hex> ./build-grpc/antd_live_manifest_tests
// ---------------------------------------------------------------------------

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <map>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

#include <httplib.h>

#include "antd/client.hpp"
#include "antd/errors.hpp"
#include "antd/manifests.hpp"
#ifdef ANTD_LIVE_GRPC
#include "antd/grpc_client.hpp"
#endif

namespace {

struct Fixture {
    std::string path;
    std::string address;   // public entries
    std::string data_map;  // the embedded entry
    std::optional<std::uint64_t> size;
};

struct Env {
    std::string rest;
    std::string grpc;
    std::vector<Fixture> fixtures;
    std::string link;
};

std::string get(const char* name) {
    const char* v = std::getenv(name);
    return v != nullptr ? std::string(v) : std::string();
}

std::string trim(std::string s) {
    s.erase(0, s.find_first_not_of(" \t"));
    s.erase(s.find_last_not_of(" \t") + 1);
    return s;
}

/// Lowercase bare hex: the daemon accepts a 0x prefix but returns bare hex.
std::string normalise(std::string s) {
    s = trim(std::move(s));
    if (s.rfind("0x", 0) == 0 || s.rfind("0X", 0) == 0) s.erase(0, 2);
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

std::vector<std::string> split(const std::string& s) {
    std::vector<std::string> out;
    std::stringstream in(s);
    std::string item;
    while (std::getline(in, item, ',')) {
        item = trim(item);
        if (!item.empty()) out.push_back(item);
    }
    return out;
}

std::optional<std::uint64_t> to_u64(const std::string& s) {
    std::uint64_t v = 0;
    if (s.empty() || !antd::detail::parse_decimal_u64(s, v)) return std::nullopt;
    return v;
}

std::optional<Env> env() {
    Env e;
    e.rest = get("ANTD_TEST_URL");
    const auto addresses = split(get("ANTD_TEST_MANIFEST_ADDRESSES"));
    if (e.rest.empty() || addresses.empty()) return std::nullopt;
#ifdef ANTD_LIVE_GRPC
    e.grpc = get("ANTD_TEST_GRPC");
    if (e.grpc.empty()) return std::nullopt;
    if (e.grpc.rfind("http://", 0) == 0) e.grpc.erase(0, 7);
#endif
    const auto sizes = split(get("ANTD_TEST_MANIFEST_SIZES"));
    for (std::size_t i = 0; i < addresses.size(); ++i) {
        e.fixtures.push_back(Fixture{
            .path = "live/public-" + std::to_string(i) + ".txt",
            .address = normalise(addresses[i]),
            .data_map = {},
            .size = i < sizes.size() ? to_u64(sizes[i]) : std::nullopt,
        });
    }
    if (const auto dm = trim(get("ANTD_TEST_MANIFEST_DATA_MAP")); !dm.empty()) {
        e.fixtures.push_back(Fixture{
            .path = "live/private.bin",
            .address = {},
            .data_map = dm,
            .size = to_u64(trim(get("ANTD_TEST_MANIFEST_DATA_MAP_SIZE"))),
        });
    }
    e.link = trim(get("ANTD_TEST_MANIFEST_LINK"));
    return e;
}

std::vector<antd::ManifestEntryInput> inputs(const Env& e) {
    std::vector<antd::ManifestEntryInput> out;
    for (const auto& f : e.fixtures) {
        out.push_back({.path = f.path, .size = std::nullopt, .data_map = f.data_map,
                       .address = f.address});
    }
    return out;
}

const antd::ManifestEntryInfo* find(const std::vector<antd::ManifestEntryInfo>& entries,
                                    const std::string& name) {
    for (const auto& en : entries) {
        if (en.effective_name == name) return &en;
    }
    return nullptr;
}

/// The built manifest names every fixture under its path, with the right
/// kind, and a public entry's content address is its address.
void check_built(const Env& e, const antd::BuiltManifest& built) {
    CHECK_FALSE(built.manifest.empty());
    CHECK_FALSE(built.link.empty());
    CHECK(built.link.rfind("ant://manifest/", 0) == 0);
    REQUIRE(built.entries.size() == e.fixtures.size());
    for (const auto& f : e.fixtures) {
        INFO("entry " << f.path);
        const auto* en = find(built.entries, f.path);
        REQUIRE(en != nullptr);
        CHECK(en->path == std::optional<std::string>(f.path));
        // No size was given, so none is recorded.
        CHECK_FALSE(en->size.has_value());
        if (f.data_map.empty()) {
            CHECK(en->kind == "public");
            CHECK(en->content_address == f.address);
        } else {
            CHECK(en->kind == "embedded");
            CHECK(en->content_address.size() == 64);
        }
    }
}

/// A resolving decode reports each fixture's exact size, and the DataMap
/// entry decodes as embedded with its DataMap.
void check_decoded(const Env& e, const antd::DecodedManifest& d) {
    CHECK(d.source == "manifest");
    CHECK(d.name == std::optional<std::string>("live"));
    REQUIRE(d.entries.size() == e.fixtures.size());
    for (const auto& f : e.fixtures) {
        INFO("entry " << f.path);
        const auto* en = find(d.entries, f.path);
        REQUIRE(en != nullptr);
        CHECK(en->error.empty());
        REQUIRE(en->exact_size.has_value());
        if (f.size) CHECK(*en->exact_size == *f.size);
        if (f.data_map.empty()) {
            CHECK(en->kind == "public");
            CHECK(en->data_map.empty());
        } else {
            CHECK(en->kind == "embedded");
            CHECK_FALSE(en->data_map.empty());
        }
    }
}

/// The fixture link: a manifest of the same three uploads (under its own
/// paths), each resolving to one of the fixture sizes.
void check_fixture_link(const Env& e, const antd::DecodedManifest& d) {
    CHECK(d.source == "manifest");
    REQUIRE(d.entries.size() == e.fixtures.size());
    std::vector<std::uint64_t> want;
    for (const auto& f : e.fixtures) {
        if (f.size) want.push_back(*f.size);
    }
    std::vector<std::uint64_t> got;
    int embedded = 0;
    for (const auto& en : d.entries) {
        CHECK(en.error.empty());
        REQUIRE(en.exact_size.has_value());
        got.push_back(*en.exact_size);
        if (en.kind == "embedded") {
            ++embedded;
            CHECK_FALSE(en.data_map.empty());
        }
    }
    CHECK(embedded == 1);
    if (want.size() == got.size()) {
        std::sort(want.begin(), want.end());
        std::sort(got.begin(), got.end());
        CHECK(got == want);
    }
}

template <typename C>
void round_trip(const Env& e, C& client, const char* transport) {
    INFO("transport " << transport);
    antd::BuildManifestOptions opts;
    opts.name = "live";
    const auto built = client.build_manifest(inputs(e), opts);
    check_built(e, built);
    std::cout << "[" << transport << "] built " << built.manifest.size() << " bytes, link "
              << built.link.size() << " chars\n";

    check_decoded(e, client.decode_manifest(built.manifest, true));
    check_decoded(e, client.decode_manifest_link(built.link, true));

    // Without resolve, a public entry has no exact size (its DataMap is not
    // fetched), and it reads as nullopt, not 0.
    const auto unresolved = client.decode_manifest(built.manifest, false);
    for (const auto& en : unresolved.entries) {
        if (en.kind == "public") CHECK_FALSE(en.exact_size.has_value());
    }

    if (!e.link.empty()) {
        check_fixture_link(e, client.decode_manifest_link(e.link, true));
    }

    // Refused before sending: both sources on one entry. The message is the
    // daemon's own, so it equals what the daemon says for the same request.
    try {
        (void)client.build_manifest({{.data_map = "aa", .address = e.fixtures[0].address}});
        FAIL("expected BadRequestError");
    } catch (const antd::BadRequestError& err) {
        CHECK(err.status_code == 400);
        CHECK(std::string(err.what()) ==
              "antd error 400: 1 invalid entries: entries[0]: give data_map or address, not both");
    }
    {
        // The daemon's answer, for the same mistake sent past the client check.
        httplib::Client raw(e.rest);
        const std::string body = "{\"entries\":[{\"data_map\":\"aa\",\"address\":\"" +
                                 e.fixtures[0].address + "\"}]}";
        auto res = raw.Post("/v1/manifests/build", body, "application/json");
        REQUIRE(res);
        CHECK(res->status == 400);
        CHECK(res->body.find("1 invalid entries: entries[0]: give data_map or address, not both") !=
              std::string::npos);
    }
    // Refused by the daemon, which names the entry.
    try {
        (void)client.build_manifest({{.address = e.fixtures[0].address},
                                     {.path = "../x", .address = e.fixtures[0].address}});
        FAIL("expected BadRequestError");
    } catch (const antd::BadRequestError& err) {
        std::cout << "[" << transport << "] bad path: " << err.what() << "\n";
        CHECK(std::string(err.what()).find("entries[1]") != std::string::npos);
    }
    CHECK_THROWS_AS(client.decode_manifest(std::vector<uint8_t>{'n', 'o', 'p', 'e'}),
                    antd::BadRequestError);
}

}  // namespace

TEST_CASE("live manifest build and decode") {
    const auto e = env();
    if (!e) {
#ifdef ANTD_LIVE_GRPC
        const char* needed = "ANTD_TEST_URL, ANTD_TEST_GRPC and ANTD_TEST_MANIFEST_ADDRESSES";
#else
        const char* needed = "ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES";
#endif
        std::cout << "skipped: set " << needed << " to run the live manifest test\n";
        return;
    }

    antd::Client rest(e->rest, 120);
    round_trip(*e, rest, "rest");

#ifdef ANTD_LIVE_GRPC
    antd::GrpcClient grpc(e->grpc);
    round_trip(*e, grpc, "grpc");

    // Both transports build the same bytes from the same input.
    antd::BuildManifestOptions opts;
    opts.name = "live";
    CHECK(rest.build_manifest(inputs(*e), opts).manifest ==
          grpc.build_manifest(inputs(*e), opts).manifest);
#endif
}
