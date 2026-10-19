// ---------------------------------------------------------------------------
// Live pointer round trip against a running antd with a devnet behind it.
//
// Skipped unless these are set:
//
//   ANTD_TEST_URL             the daemon's REST base URL, e.g. http://127.0.0.1:8082
//   ANTD_TEST_GRPC            its gRPC target, e.g. 127.0.0.1:50051 (gRPC builds
//                             only: -DANTD_BUILD_GRPC=ON)
//   ANTD_TEST_POINTER_OWNERS  two comma-separated pointer addresses the daemon
//                             holds keys for (antd --pointer-keys) and that have
//                             never been written. The test creates both,
//                             transfers the first to the second, and leaves the
//                             second with a prepared write awaiting payment, so
//                             each pair can be used once.
//
// Every write is paid by the daemon's wallet, so run it against a devnet:
//
//   export ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051
//   ANTD_TEST_POINTER_OWNERS=<hex>,<hex> ./build-grpc/antd_live_pointer_tests
// ---------------------------------------------------------------------------

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <iostream>
#include <optional>
#include <string>
#include <vector>

#include "antd/client.hpp"
#include "antd/errors.hpp"
#include "antd/models.hpp"
#ifdef ANTD_LIVE_GRPC
#include "antd/grpc_client.hpp"
#endif

namespace {

struct Env {
    std::string rest;
    std::string grpc;
    std::string first;
    std::string second;
};

/// Lowercase bare hex: the daemon accepts a 0x prefix but returns bare hex.
std::string normalise(std::string s) {
    s.erase(0, s.find_first_not_of(" \t"));
    s.erase(s.find_last_not_of(" \t") + 1);
    if (s.rfind("0x", 0) == 0 || s.rfind("0X", 0) == 0) s.erase(0, 2);
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

std::optional<Env> env() {
    const char* rest = std::getenv("ANTD_TEST_URL");
    const char* owners = std::getenv("ANTD_TEST_POINTER_OWNERS");
    if (rest == nullptr || owners == nullptr) return std::nullopt;
    Env e;
    e.rest = rest;
#ifdef ANTD_LIVE_GRPC
    const char* grpc = std::getenv("ANTD_TEST_GRPC");
    if (grpc == nullptr) return std::nullopt;
    e.grpc = grpc;
    if (e.grpc.rfind("http://", 0) == 0) e.grpc.erase(0, 7);
#endif
    const std::string pair = owners;
    const auto comma = pair.find(',');
    if (comma == std::string::npos) return std::nullopt;
    e.first = normalise(pair.substr(0, comma));
    e.second = normalise(pair.substr(comma + 1));
    return e;
}

std::vector<uint8_t> bytes(const std::string& s) { return {s.begin(), s.end()}; }

}  // namespace

TEST_CASE("live pointer round trip") {
    const auto e = env();
    if (!e) {
#ifdef ANTD_LIVE_GRPC
        const std::string needed = "ANTD_TEST_URL, ANTD_TEST_GRPC and ANTD_TEST_POINTER_OWNERS";
#else
        const std::string needed = "ANTD_TEST_URL and ANTD_TEST_POINTER_OWNERS";
#endif
        MESSAGE("live_pointers: set " << needed << " to run");
        return;
    }
    const std::string& a = e->first;
    const std::string& b = e->second;
    antd::Client rest(e->rest, 300);
#ifdef ANTD_LIVE_GRPC
    antd::GrpcClient grpc(e->grpc);
#endif

    // Both owners must be writable through this daemon.
    std::vector<std::string> keys;
    for (const auto& k : rest.pointer_keys()) keys.push_back(normalise(k.address));
    auto holds = [&](const std::string& addr) {
        return std::find(keys.begin(), keys.end(), addr) != keys.end();
    };
    REQUIRE_MESSAGE(holds(a), "daemon holds no key for " << a);
    REQUIRE_MESSAGE(holds(b), "daemon holds no key for " << b);

    // Real targets, so the chain can be followed back to bytes.
    const auto one_bytes = bytes("antd-cpp pointer target one");
    const auto two_bytes = bytes("antd-cpp pointer target two");
    const std::string one = rest.data_put_public(one_bytes).address;
    const std::string two = rest.data_put_public(two_bytes).address;

    // --- REST: create, read, update ---
    bool fresh = false;
    try {
        rest.pointer_get(a);
    } catch (const antd::NotFoundError&) {
        fresh = true;
    }
    REQUIRE_MESSAGE(fresh, "owner " << a << " has been written before; use a fresh pair");

    auto w = rest.pointer_create(a, one);
    CHECK(w.counter == 0);
    CHECK(normalise(w.address) == a);
    CHECK_THROWS_AS(rest.pointer_create(a, two), antd::AlreadyExistsError);

    auto r = rest.pointer_get(a);
    CHECK(r.counter == 0);
    CHECK(r.target == one);
    CHECK_FALSE(r.is_final);
    CHECK(r.target_kind() == antd::PointerKind::Chunk);
    CHECK(r.owner.size() == 2 * 1952);
    CHECK_FALSE(r.transferred_to.has_value());
    auto res = rest.pointer_resolve(a);
    CHECK(res.target == one);
    CHECK(rest.data_get_public(res.target) == one_bytes);

    w = rest.pointer_update(a, two);
    CHECK(w.counter == 1);
    CHECK(rest.pointer_resolve(a).target == two);
    auto f = rest.pointer_finality(a);
    CHECK(f.status == antd::PointerFinalityStatus::Open);
    REQUIRE(f.counter.has_value());
    CHECK(*f.counter == 1);
    CHECK(f.answered == f.group);

    // --- the second owner: a write, then a read (over gRPC when built) ---
#ifdef ANTD_LIVE_GRPC
    w = grpc.pointer_create(b, one);
    CHECK(w.counter == 0);
    r = grpc.pointer_get(b);
#else
    w = rest.pointer_create(b, one);
    CHECK(w.counter == 0);
    r = rest.pointer_get(b);
#endif
    CHECK(r.counter == 0);
    CHECK(r.target == one);

    // --- transfer a -> b ---
    auto t = rest.pointer_transfer(a, b);
    REQUIRE_MESSAGE(t.finality.has_value(),
                    "the close group should answer after the transfer: "
                        << t.finality_error.value_or("(no error)"));
    CHECK(t.finality->status == antd::PointerFinalityStatus::Final);
    REQUIRE(t.finality->transferred_to.has_value());
    CHECK(normalise(*t.finality->transferred_to) == b);
    r = rest.pointer_get(a);
    CHECK(r.is_final);
    CHECK(r.counter == antd::kPointerFinalCounter);
    REQUIRE(r.transferred_to.has_value());
    CHECK(normalise(*r.transferred_to) == b);
    auto c = rest.pointer_controller(a);
    CHECK(normalise(c.pointer) == b);
    REQUIRE(c.transfers.size() == 1);
    CHECK(normalise(c.transfers[0]) == b);
    CHECK_FALSE(c.frozen);
    // a now resolves through b.
#ifdef ANTD_LIVE_GRPC
    CHECK(grpc.pointer_resolve(a).target == one);
    CHECK(grpc.pointer_finality(a).is_final());
#else
    CHECK(rest.pointer_resolve(a).target == one);
    CHECK(rest.pointer_finality(a).is_final());
#endif

    // A final pointer refuses every write, before anything is paid.
    CHECK_THROWS_AS(rest.pointer_update(a, one), antd::PointerFinalError);
#ifdef ANTD_LIVE_GRPC
    CHECK_THROWS_AS(grpc.pointer_update(a, one), antd::PointerFinalError);
#endif
    CHECK_THROWS_AS(rest.pointer_transfer(a, b), antd::PointerFinalError);

    // --- external signer, up to the quote ---
    // Last: the prepared write blocks b's other writes until it expires.
    auto p = rest.pointer_prepare(antd::PointerPrepareRequest::update(b, two));
    CHECK(p.op == "update");
    CHECK(p.counter == 1);
    CHECK(p.payment_type == "wave_batch");
    CHECK_FALSE(p.payments.empty());
    CHECK_FALSE(p.upload_id.empty());
    CHECK_THROWS_AS(rest.pointer_update(b, two), antd::ConflictError);
#ifdef ANTD_LIVE_GRPC
    CHECK_THROWS_AS(grpc.pointer_prepare(antd::PointerPrepareRequest::update(b, two)),
                    antd::ConflictError);
#endif
    // A finalize without the payment is refused and keeps the session.
    CHECK_THROWS_AS(rest.pointer_finalize(p.upload_id, {}), antd::BadRequestError);
    CHECK_THROWS_AS(rest.pointer_update(b, two), antd::ConflictError);

    std::cout << "live_pointers: round trip passed for " << a << " -> " << b << "\n";
}
