// ---------------------------------------------------------------------------
// Live sha256 test (antd 0.17.0) against a running antd with a devnet behind
// it. The manifest steps are free; the last step makes ONE paid public data
// upload per transport.
//
// Skipped unless ANTD_TEST_URL and ANTD_TEST_SHA_LINK are set (and, in a gRPC
// build, ANTD_TEST_GRPC):
//
//   ANTD_TEST_URL                       the daemon's REST base URL
//   ANTD_TEST_GRPC                      its gRPC target (gRPC builds only:
//                                       -DANTD_BUILD_GRPC=ON)
//   ANTD_TEST_SHA_LINK                  a manifest link with entries public.txt
//                                       and private.txt (sha256 recorded) and
//                                       nohash.txt (none)
//   ANTD_TEST_SHA_PUBLIC_SHA256         public.txt's plaintext SHA-256
//   ANTD_TEST_SHA_DATA_MAP_SHA256       private.txt's plaintext SHA-256
//   ANTD_TEST_SHA_PUBLIC_ADDRESS        public.txt's public data address
//
//   source ~/sha-fanout-daemon/fixtures.env
//   ./build-grpc/antd_live_sha256_tests
// ---------------------------------------------------------------------------

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <optional>
#include <string>
#include <vector>

#include "antd/client.hpp"
#include "antd/errors.hpp"
#include "antd/manifests.hpp"
#ifdef ANTD_LIVE_GRPC
#include "antd/grpc_client.hpp"
#endif

namespace {

std::string get(const char* name) {
    const char* v = std::getenv(name);
    return v != nullptr ? std::string(v) : std::string();
}

/// Lowercase hex SHA-256 (FIPS 180-4), for checking the daemon's hash of the
/// uploaded payload without a crypto dependency.
std::string sha256_hex(const std::string& msg) {
    static const std::array<std::uint32_t, 64> k = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2};
    std::array<std::uint32_t, 8> h = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    std::vector<std::uint8_t> data(msg.begin(), msg.end());
    const std::uint64_t bit_len = static_cast<std::uint64_t>(data.size()) * 8;
    data.push_back(0x80);
    while (data.size() % 64 != 56) data.push_back(0);
    for (int i = 7; i >= 0; --i) data.push_back(static_cast<std::uint8_t>(bit_len >> (i * 8)));

    auto rotr = [](std::uint32_t x, int n) { return (x >> n) | (x << (32 - n)); };
    for (std::size_t off = 0; off < data.size(); off += 64) {
        std::array<std::uint32_t, 64> w{};
        for (int i = 0; i < 16; ++i) {
            w[i] = (std::uint32_t(data[off + 4 * i]) << 24) | (std::uint32_t(data[off + 4 * i + 1]) << 16) |
                   (std::uint32_t(data[off + 4 * i + 2]) << 8) | std::uint32_t(data[off + 4 * i + 3]);
        }
        for (int i = 16; i < 64; ++i) {
            const auto s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
            const auto s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }
        auto v = h;
        for (int i = 0; i < 64; ++i) {
            const auto s1 = rotr(v[4], 6) ^ rotr(v[4], 11) ^ rotr(v[4], 25);
            const auto ch = (v[4] & v[5]) ^ (~v[4] & v[6]);
            const auto t1 = v[7] + s1 + ch + k[i] + w[i];
            const auto s0 = rotr(v[0], 2) ^ rotr(v[0], 13) ^ rotr(v[0], 22);
            const auto maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
            const auto t2 = s0 + maj;
            v[7] = v[6]; v[6] = v[5]; v[5] = v[4]; v[4] = v[3] + t1;
            v[3] = v[2]; v[2] = v[1]; v[1] = v[0]; v[0] = t1 + t2;
        }
        for (int i = 0; i < 8; ++i) h[i] += v[i];
    }
    static const char* digits = "0123456789abcdef";
    std::string out;
    for (const auto word : h) {
        for (int i = 7; i >= 0; --i) out.push_back(digits[(word >> (i * 4)) & 0xf]);
    }
    return out;
}

const antd::ManifestEntryInfo* find(const std::vector<antd::ManifestEntryInfo>& entries,
                                    const std::string& name) {
    for (const auto& en : entries) {
        if (en.path == std::optional<std::string>(name)) return &en;
    }
    return nullptr;
}

template <typename C>
void sha_round_trip(C& client, const char* transport) {
    INFO("transport " << transport);
    const auto link = get("ANTD_TEST_SHA_LINK");
    const auto public_sha = get("ANTD_TEST_SHA_PUBLIC_SHA256");
    const auto data_map_sha = get("ANTD_TEST_SHA_DATA_MAP_SHA256");
    const auto public_address = get("ANTD_TEST_SHA_PUBLIC_ADDRESS");

    // 1. Decode the fixture link without resolving.
    const auto decoded = client.decode_manifest_link(link, false);
    const auto* pub = find(decoded.entries, "public.txt");
    const auto* priv = find(decoded.entries, "private.txt");
    const auto* none = find(decoded.entries, "nohash.txt");
    REQUIRE(pub != nullptr);
    REQUIRE(priv != nullptr);
    REQUIRE(none != nullptr);
    CHECK(pub->sha256 == std::optional<std::string>(public_sha));
    CHECK(priv->sha256 == std::optional<std::string>(data_map_sha));
    CHECK_FALSE(none->sha256.has_value());

    // 2. Build a manifest with a sha256 on the entry: it comes back.
    const auto built = client.build_manifest(
        {{.path = "a.txt", .address = public_address, .sha256 = public_sha}});
    REQUIRE(built.entries.size() == 1);
    CHECK(built.entries[0].sha256 == std::optional<std::string>(public_sha));

    // 3. A malformed hash is the daemon's 400.
    try {
        (void)client.build_manifest(
            {{.path = "a.txt", .address = public_address, .sha256 = "zz"}});
        FAIL("expected BadRequestError");
    } catch (const antd::BadRequestError& err) {
        std::cout << "[" << transport << "] bad sha256: " << err.what() << "\n";
        CHECK(err.status_code == 400);
        CHECK(std::string(err.what()).find("sha256") != std::string::npos);
    }

    // 4. One paid public upload: the daemon's hash is ours.
    const auto now = std::chrono::duration_cast<std::chrono::seconds>(
                         std::chrono::system_clock::now().time_since_epoch())
                         .count();
    const std::string payload =
        "sha-fanout cpp " + std::to_string(now) + " " + transport;
    const auto put = client.data_put_public(std::vector<std::uint8_t>(payload.begin(), payload.end()));
    const auto local = sha256_hex(payload);
    std::cout << "[" << transport << "] uploaded \"" << payload << "\" local sha256 " << local
              << " returned " << put.sha256.value_or("<none>") << "\n";
    REQUIRE(put.sha256.has_value());
    CHECK(*put.sha256 == local);
}

}  // namespace

TEST_CASE("sha256 hash function matches the known vectors") {
    CHECK(sha256_hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    CHECK(sha256_hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
}

TEST_CASE("live sha256 on manifests and a public upload") {
    const auto rest_url = get("ANTD_TEST_URL");
    const auto link = get("ANTD_TEST_SHA_LINK");
#ifdef ANTD_LIVE_GRPC
    auto grpc_target = get("ANTD_TEST_GRPC");
    if (grpc_target.rfind("http://", 0) == 0) grpc_target.erase(0, 7);
    const bool ready = !rest_url.empty() && !link.empty() && !grpc_target.empty();
    const char* needed = "ANTD_TEST_URL, ANTD_TEST_GRPC and ANTD_TEST_SHA_LINK";
#else
    const bool ready = !rest_url.empty() && !link.empty();
    const char* needed = "ANTD_TEST_URL and ANTD_TEST_SHA_LINK";
#endif
    if (!ready) {
        std::cout << "skipped: set " << needed << " to run the live sha256 test\n";
        return;
    }

    antd::Client rest(rest_url, 120);
    sha_round_trip(rest, "rest");

#ifdef ANTD_LIVE_GRPC
    antd::GrpcClient grpc(grpc_target);
    sha_round_trip(grpc, "grpc");
#endif
}
