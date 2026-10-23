// ---------------------------------------------------------------------------
// Pointer API tests for antd::Client (REST) and antd::AsyncClient.
//
// A cpp-httplib stub daemon on 127.0.0.1 serves canned /v1/pointers
// responses; the tests drive the real Client request/response path: request
// bodies, response parsing (decimal-string counters, `null` for unset
// values), and the error-code mapping (POINTER_FINAL, POINTER_FORKED,
// CONFLICT and CLOSE_GROUP_SHORTFALL against the 409/503 status mapping).
// ---------------------------------------------------------------------------

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <nlohmann/json.hpp>
#include <httplib.h>

#include <chrono>
#include <cstdint>
#include <limits>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "antd/async_client.hpp"
#include "antd/client.hpp"
#include "antd/errors.hpp"
#include "antd/models.hpp"

using json = nlohmann::json;

namespace {

const std::string kA(64, 'a');
const std::string kB(64, 'b');
const std::string kT1(64, '1');
const std::string kT2(64, '2');
const std::string kState(64, 'c');

json final_state(const std::string& target, std::uint32_t holders,
                 const json& transferred_to = nullptr) {
    return json{
        {"state_id", kState},
        {"kind", "pointer"},
        {"kind_tag", 1},
        {"target", target},
        {"holders", holders},
        {"transferred_to", transferred_to},
    };
}

void reply(httplib::Response& res, const json& body) {
    res.set_content(body.dump(), "application/json");
}

void reply_error(httplib::Response& res, int status, const std::string& code,
                 const std::string& message, const json& extra = json::object()) {
    res.status = status;
    json body = {{"error", message}, {"code", code}};
    for (const auto& [k, v] : extra.items()) body[k] = v;
    res.set_content(body.dump(), "application/json");
}

/// Counters the daemon must never send; each must throw, never read as 0.
const std::map<std::string, json> kBadCounters = {
    {"neg", "-1"},
    {"space", " 1"},
    {"plus", "+1"},
    {"empty", ""},
    {"hex", "0x10"},
    {"frac", "1.0"},
    {"overflow", "18446744073709551616"},
    {"number", 1},
    {"null", nullptr},
};

struct StubServer {
    httplib::Server svr;
    std::thread th;
    int port{0};

    std::mutex mu;
    std::string last_path;
    json last_body = json::object();

    void record(const httplib::Request& req) {
        std::lock_guard<std::mutex> lock(mu);
        last_path = req.path;
        try {
            last_body = req.body.empty() ? json::object() : json::parse(req.body);
        } catch (...) {
            last_body = json::object();
        }
    }

    StubServer() {
        // Registered before the /v1/pointers/{addr} pattern, which would
        // otherwise match it.
        svr.Get("/v1/pointers/keys", [this](const httplib::Request& req, httplib::Response& res) {
            record(req);
            reply(res, {{"keys", json::array({{{"address", kA}}, {{"address", kB}}})}});
        });

        auto write = [this](const httplib::Request& req, httplib::Response& res,
                            const char* counter) {
            record(req);
            const json body = json::parse(req.body);
            const std::string owner = body.value("owner", "");
            if (owner == "exists") {
                return reply_error(res, 409, "ALREADY_EXISTS", "Already exists: pointer exists");
            }
            if (owner == "final") {
                return reply_error(res, 409, "POINTER_FINAL", "Pointer is final: transferred");
            }
            if (owner == "forked") {
                return reply_error(res, 409, "POINTER_FORKED", "Pointer is forked: two finals");
            }
            if (owner == "pending") {
                return reply_error(res, 409, "CONFLICT", "Conflict: a prepared write awaits payment");
            }
            if (owner == "bare409") {
                res.status = 409;
                return reply(res, {{"error", "exists"}});
            }
            if (owner == "shortfall") {
                return reply_error(res, 503, "CLOSE_GROUP_SHORTFALL",
                                   "Close group shortfall: only 3 of 7 answered");
            }
            if (owner == "unknown_owner") {
                return reply_error(res, 400, "BAD_REQUEST", "Bad request: no key for owner");
            }
            if (auto it = kBadCounters.find(owner); it != kBadCounters.end()) {
                return reply(res, {{"address", kA}, {"state_id", kState}, {"counter", it->second}});
            }
            if (owner == "no_counter") {
                return reply(res, {{"address", kA}, {"state_id", kState}});
            }
            reply(res, {{"address", owner}, {"state_id", kState}, {"counter", counter}});
        };
        svr.Post("/v1/pointers", [write](const httplib::Request& req, httplib::Response& res) {
            write(req, res, "0");
        });
        svr.Post("/v1/pointers/update",
                 [write](const httplib::Request& req, httplib::Response& res) {
                     write(req, res, "1");
                 });

        svr.Post("/v1/pointers/transfer", [this](const httplib::Request& req,
                                                 httplib::Response& res) {
            record(req);
            const json body = json::parse(req.body);
            if (body.value("owner", "") == "final") {
                return reply_error(res, 409, "POINTER_FINAL", "Pointer is final: transferred");
            }
            if (body.value("owner", "") == "unchecked") {
                return reply(res, {
                    {"address", kA},
                    {"state_id", kState},
                    {"finality", nullptr},
                    {"finality_error", "Close group shortfall: 4 of 7 answered"},
                });
            }
            reply(res, {
                {"address", kA},
                {"state_id", kState},
                {"finality", {
                    {"address", kA},
                    {"group", 7},
                    {"answered", 7},
                    {"status", "final"},
                    {"counter", nullptr},
                    {"state", final_state(kB, 7, kB)},
                    {"states", json::array()},
                    {"majority", nullptr},
                    {"transferred_to", kB},
                }},
            });
        });

        svr.Get(R"(/v1/pointers/([^/]+)/resolve)",
                [this](const httplib::Request& req, httplib::Response& res) {
                    record(req);
                    if (req.matches[1] == "missing") {
                        return reply_error(res, 404, "NOT_FOUND", "Record not found: pointer");
                    }
                    reply(res, {{"kind", "chunk"}, {"kind_tag", 0}, {"target", kT1}});
                });

        svr.Get(R"(/v1/pointers/([^/]+)/finality)", [this](const httplib::Request& req,
                                                           httplib::Response& res) {
            record(req);
            const std::string addr = req.matches[1];
            json f = {
                {"address", kA},
                {"group", 7},
                {"answered", 7},
                {"status", "open"},
                {"counter", "1"},
                {"state", nullptr},
                {"states", json::array()},
                {"majority", nullptr},
                {"transferred_to", nullptr},
            };
            if (addr == "forked") {
                f["status"] = "forked";
                f["counter"] = nullptr;
                f["states"] = json::array({final_state(kB, 5, kB), final_state(kT2, 2)});
                f["majority"] = final_state(kB, 5, kB);
            } else if (addr == "unknown_status") {
                f["status"] = "contested";
            } else if (addr == "no_counter") {
                f["counter"] = nullptr;
                f["answered"] = 5;
            } else if (addr == "absent_counter") {
                f.erase("counter");
            } else if (addr == "empty_counter") {
                f["counter"] = "";
            } else if (addr == "numeric_counter") {
                f["counter"] = 1;
            } else if (addr == "bad_counter") {
                f["counter"] = "-1";
            } else if (addr == "shortfall") {
                return reply_error(res, 503, "CLOSE_GROUP_SHORTFALL",
                                   "Close group shortfall: only 2 of 7 answered");
            }
            reply(res, f);
        });

        svr.Get(R"(/v1/pointers/([^/]+)/controller)",
                [this](const httplib::Request& req, httplib::Response& res) {
                    record(req);
                    reply(res, {{"pointer", kB}, {"transfers", json::array({kB})}, {"frozen", false}});
                });

        svr.Get(R"(/v1/pointers/([^/]+))", [this](const httplib::Request& req,
                                                  httplib::Response& res) {
            record(req);
            const std::string addr = req.matches[1];
            if (addr == "missing") {
                return reply_error(res, 404, "NOT_FOUND", "Record not found: no pointer");
            }
            if (addr == "transferred") {
                return reply(res, {
                    {"address", kA},
                    {"owner", std::string(2 * 1952, 'e')},
                    {"counter", "18446744073709551615"},
                    {"kind", "pointer"},
                    {"kind_tag", 1},
                    {"target", kB},
                    {"state_id", kState},
                    {"is_final", true},
                    {"transferred_to", kB},
                });
            }
            if (addr == "odd_kind") {
                return reply(res, {
                    {"address", kA}, {"owner", "ee"}, {"counter", "3"}, {"kind", "unknown"},
                    {"kind_tag", 7}, {"target", kT1}, {"state_id", kState}, {"is_final", false},
                    {"transferred_to", nullptr},
                });
            }
            if (auto it = kBadCounters.find(addr); it != kBadCounters.end()) {
                return reply(res, {{"address", kA}, {"counter", it->second}, {"is_final", false}});
            }
            reply(res, {
                {"address", addr},
                {"owner", "ee"},
                {"counter", "1"},
                {"kind", "chunk"},
                {"kind_tag", 0},
                {"target", kT2},
                {"state_id", kState},
                {"is_final", false},
                {"transferred_to", nullptr},
            });
        });

        svr.Post("/v1/pointers/prepare", [this](const httplib::Request& req,
                                                httplib::Response& res) {
            record(req);
            const json body = json::parse(req.body);
            if (body.value("owner", "") == "pending") {
                return reply_error(res, 409, "CONFLICT", "Conflict: a prepared write awaits payment");
            }
            json resp = {
                {"upload_id", "pup_1"},
                {"op", body.value("op", "")},
                {"address", body.value("owner", "")},
                {"state_id", kState},
                {"counter", body.value("op", "") == "transfer" ? "18446744073709551615" : "2"},
                {"payment_type", "wave_batch"},
                {"payments", json::array({{
                    {"quote_hash", "0xq1"}, {"rewards_address", "0xr1"}, {"amount", "123"},
                }})},
                {"total_amount", "123"},
                {"payment_vault_address", "0xvault"},
                {"payment_token_address", "0xtoken"},
                {"rpc_url", "http://rpc.local"},
            };
            if (body.value("include_signed_quotes", false)) {
                resp["signed_quotes"] = json::array({
                    {{"quote_hash", "0xq1"}, {"quote", "cXVvdGU="}, {"commitment_sidecar", "c2lkZQ=="}},
                    {{"quote_hash", "0xq2"}, {"quote", "cXVvdGUy"}},
                });
            }
            reply(res, resp);
        });

        svr.Post("/v1/pointers/finalize", [this](const httplib::Request& req,
                                                 httplib::Response& res) {
            record(req);
            const json body = json::parse(req.body);
            const std::string uid = body.value("upload_id", "");
            if (uid == "retained") {
                return reply_error(res, 503, "CLOSE_GROUP_SHORTFALL",
                                   "Close group shortfall: stored on 4 of 7 (paid attempt "
                                   "retained: call finalize again with the same upload_id to "
                                   "store it against the same payment)",
                                   {{"retryable", true}});
            }
            if (uid == "retryable_string") {
                return reply_error(res, 503, "CLOSE_GROUP_SHORTFALL", "Close group shortfall",
                                   {{"retryable", "true"}});
            }
            if (uid == "unpaid") {
                return reply_error(res, 400, "BAD_REQUEST", "Bad request: missing tx hash");
            }
            json resp = {{"address", kA}, {"state_id", kState}, {"counter", "5"}};
            if (uid == "transfer") {
                resp["counter"] = "18446744073709551615";
                resp["finality"] = {
                    {"address", kA}, {"group", 7}, {"answered", 6}, {"status", "unconfirmed"},
                    {"counter", nullptr}, {"state", final_state(kB, 6, kB)},
                    {"states", json::array()}, {"majority", nullptr}, {"transferred_to", nullptr},
                };
            }
            reply(res, resp);
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
};

}  // namespace

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

TEST_CASE("pointer kind / op / finality status wire strings") {
    CHECK(antd::pointer_kind_wire(antd::PointerKind::Chunk) == "chunk");
    CHECK(antd::pointer_kind_wire(antd::PointerKind::Pointer) == "pointer");
    CHECK(antd::pointer_kind_from_tag(0) == antd::PointerKind::Chunk);
    CHECK(antd::pointer_kind_from_tag(1) == antd::PointerKind::Pointer);
    CHECK_FALSE(antd::pointer_kind_from_tag(2).has_value());
    CHECK(antd::pointer_op_wire(antd::PointerOp::Create) == "create");
    CHECK(antd::pointer_op_wire(antd::PointerOp::Update) == "update");
    CHECK(antd::pointer_op_wire(antd::PointerOp::Transfer) == "transfer");
    CHECK(antd::pointer_finality_status_from_wire("open") == antd::PointerFinalityStatus::Open);
    CHECK(antd::pointer_finality_status_from_wire("settling") ==
          antd::PointerFinalityStatus::Settling);
    CHECK(antd::pointer_finality_status_from_wire("unconfirmed") ==
          antd::PointerFinalityStatus::Unconfirmed);
    CHECK(antd::pointer_finality_status_from_wire("final") == antd::PointerFinalityStatus::Final);
    CHECK(antd::pointer_finality_status_from_wire("forked") == antd::PointerFinalityStatus::Forked);
    CHECK(antd::pointer_finality_status_from_wire("Final") == antd::PointerFinalityStatus::Unknown);
    CHECK(antd::pointer_finality_status_from_wire("") == antd::PointerFinalityStatus::Unknown);
    CHECK(antd::kPointerFinalCounter == std::numeric_limits<std::uint64_t>::max());
}

TEST_CASE("PointerPrepareRequest builders") {
    auto c = antd::PointerPrepareRequest::create(kA, kT1, antd::PointerKind::Pointer);
    CHECK(c.op == antd::PointerOp::Create);
    CHECK(c.owner == kA);
    CHECK(c.target == kT1);
    CHECK(c.kind == antd::PointerKind::Pointer);
    auto u = antd::PointerPrepareRequest::update(kA, kT2);
    CHECK(u.op == antd::PointerOp::Update);
    CHECK(u.kind == antd::PointerKind::Chunk);
    auto t = antd::PointerPrepareRequest::transfer(kA, kB);
    CHECK(t.op == antd::PointerOp::Transfer);
    CHECK(t.recipient == kB);
    CHECK(t.target.empty());
    CHECK_FALSE(t.include_signed_quotes);
}

// ---------------------------------------------------------------------------
// Methods
// ---------------------------------------------------------------------------

TEST_CASE("pointer_keys lists the addresses the daemon holds keys for") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto keys = c.pointer_keys();
    REQUIRE(keys.size() == 2);
    CHECK(keys[0].address == kA);
    CHECK(keys[1].address == kB);
}

TEST_CASE("pointer_create posts owner, target and kind and reads a decimal counter") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto w = c.pointer_create(kA, kT1);
    CHECK(stub.path() == "/v1/pointers");
    CHECK(stub.body() == json{{"owner", kA}, {"target", kT1}, {"kind", "chunk"}});
    CHECK(w.address == kA);
    CHECK(w.state_id == kState);
    CHECK(w.counter == 0);

    c.pointer_create(kA, kB, antd::PointerKind::Pointer);
    CHECK(stub.body().value("kind", "") == "pointer");
}

TEST_CASE("pointer_update posts to /update") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto w = c.pointer_update(kA, kT2);
    CHECK(stub.path() == "/v1/pointers/update");
    CHECK(stub.body() == json{{"owner", kA}, {"target", kT2}, {"kind", "chunk"}});
    CHECK(w.counter == 1);
}

TEST_CASE("pointer_get reads a transferred record at the final counter") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto r = c.pointer_get("transferred");
    CHECK(stub.path() == "/v1/pointers/transferred");
    CHECK(r.address == kA);
    CHECK(r.owner.size() == 2 * 1952);
    CHECK(r.counter == antd::kPointerFinalCounter);
    CHECK(r.counter == 18446744073709551615ULL);
    CHECK(r.kind == "pointer");
    CHECK(r.kind_tag == 1);
    CHECK(r.target_kind() == antd::PointerKind::Pointer);
    CHECK(r.target == kB);
    CHECK(r.is_final);
    REQUIRE(r.transferred_to.has_value());
    CHECK(*r.transferred_to == kB);
}

TEST_CASE("pointer_get maps a null transferred_to to nullopt") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto r = c.pointer_get(kA);
    CHECK(r.counter == 1);
    CHECK(r.kind == "chunk");
    CHECK(r.target_kind() == antd::PointerKind::Chunk);
    CHECK_FALSE(r.is_final);
    CHECK_FALSE(r.transferred_to.has_value());
}

TEST_CASE("pointer_get keeps an unknown kind's raw tag") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto r = c.pointer_get("odd_kind");
    CHECK(r.kind == "unknown");
    CHECK(r.kind_tag == 7);
    CHECK_FALSE(r.target_kind().has_value());
}

TEST_CASE("pointer_get on an address with no pointer -> NotFoundError") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    CHECK_THROWS_AS(c.pointer_get("missing"), antd::NotFoundError);
}

TEST_CASE("pointer_resolve follows the chain to its target") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto t = c.pointer_resolve(kA);
    CHECK(stub.path() == "/v1/pointers/" + kA + "/resolve");
    CHECK(t.kind == "chunk");
    CHECK(t.kind_tag == 0);
    CHECK(t.target == kT1);
    CHECK_THROWS_AS(c.pointer_resolve("missing"), antd::NotFoundError);
}

TEST_CASE("pointer_finality open: counter set, nulls unset") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto f = c.pointer_finality(kA);
    CHECK(stub.path() == "/v1/pointers/" + kA + "/finality");
    CHECK(f.address == kA);
    CHECK(f.group == 7);
    CHECK(f.answered == 7);
    CHECK(f.status == antd::PointerFinalityStatus::Open);
    CHECK(f.status_raw == "open");
    CHECK_FALSE(f.is_final());
    REQUIRE(f.counter.has_value());
    CHECK(*f.counter == 1);
    CHECK_FALSE(f.state.has_value());
    CHECK(f.states.empty());
    CHECK_FALSE(f.majority.has_value());
    CHECK_FALSE(f.transferred_to.has_value());
}

TEST_CASE("pointer_finality: a null, absent or empty counter is unset, not zero") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    for (const std::string addr : {"no_counter", "absent_counter", "empty_counter"}) {
        CAPTURE(addr);
        auto f = c.pointer_finality(addr);
        CHECK_FALSE(f.counter.has_value());
    }
}

TEST_CASE("pointer_finality: a counter that is not a decimal string throws") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    CHECK_THROWS_AS(c.pointer_finality("numeric_counter"), antd::InternalError);
    CHECK_THROWS_AS(c.pointer_finality("bad_counter"), antd::InternalError);
}

TEST_CASE("pointer_finality forked: every final state and the majority") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto f = c.pointer_finality("forked");
    CHECK(f.status == antd::PointerFinalityStatus::Forked);
    CHECK_FALSE(f.counter.has_value());
    REQUIRE(f.states.size() == 2);
    CHECK(f.states[0].target == kB);
    CHECK(f.states[0].holders == 5);
    REQUIRE(f.states[0].transferred_to.has_value());
    CHECK(*f.states[0].transferred_to == kB);
    CHECK(f.states[1].target == kT2);
    CHECK(f.states[1].holders == 2);
    CHECK_FALSE(f.states[1].transferred_to.has_value());
    REQUIRE(f.majority.has_value());
    CHECK(f.majority->holders == 5);
    CHECK(f.majority->kind_tag == 1);
}

TEST_CASE("pointer_finality keeps a status this SDK does not know") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto f = c.pointer_finality("unknown_status");
    CHECK(f.status == antd::PointerFinalityStatus::Unknown);
    CHECK(f.status_raw == "contested");
    CHECK_FALSE(f.is_final());
}

TEST_CASE("pointer_controller lists the transfers") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto ctl = c.pointer_controller(kA);
    CHECK(stub.path() == "/v1/pointers/" + kA + "/controller");
    CHECK(ctl.pointer == kB);
    CHECK(ctl.transfers == std::vector<std::string>{kB});
    CHECK_FALSE(ctl.frozen);
}

TEST_CASE("pointer_transfer posts owner and recipient and reads the finality") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto t = c.pointer_transfer(kA, kB);
    CHECK(stub.path() == "/v1/pointers/transfer");
    CHECK(stub.body() == json{{"owner", kA}, {"recipient", kB}});
    CHECK(t.address == kA);
    CHECK(t.state_id == kState);
    CHECK_FALSE(t.finality_error.has_value());
    REQUIRE(t.finality.has_value());
    CHECK(t.finality->is_final());
    CHECK_FALSE(t.finality->counter.has_value());
    REQUIRE(t.finality->state.has_value());
    CHECK(t.finality->state->holders == 7);
    REQUIRE(t.finality->transferred_to.has_value());
    CHECK(*t.finality->transferred_to == kB);
}

TEST_CASE("pointer_transfer whose finality check failed keeps the error, not a finality") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto t = c.pointer_transfer("unchecked", kB);
    CHECK_FALSE(t.finality.has_value());
    REQUIRE(t.finality_error.has_value());
    CHECK(t.finality_error->find("shortfall") != std::string::npos);
}

TEST_CASE("pointer_prepare create sends target and kind, not a recipient") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto p = c.pointer_prepare(antd::PointerPrepareRequest::create(kA, kT1));
    CHECK(stub.path() == "/v1/pointers/prepare");
    CHECK(stub.body() == json{{"owner", kA}, {"op", "create"}, {"target", kT1}, {"kind", "chunk"}});
    CHECK(p.upload_id == "pup_1");
    CHECK(p.op == "create");
    CHECK(p.address == kA);
    CHECK(p.state_id == kState);
    CHECK(p.counter == 2);
    CHECK(p.payment_type == "wave_batch");
    REQUIRE(p.payments.size() == 1);
    CHECK(p.payments[0].quote_hash == "0xq1");
    CHECK(p.payments[0].rewards_address == "0xr1");
    CHECK(p.payments[0].amount == "123");
    CHECK(p.total_amount == "123");
    CHECK(p.payment_vault_address == "0xvault");
    CHECK(p.payment_token_address == "0xtoken");
    CHECK(p.rpc_url == "http://rpc.local");
    CHECK(p.signed_quotes.empty());
}

TEST_CASE("pointer_prepare update with kind pointer and signed quotes") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto req = antd::PointerPrepareRequest::update(kA, kB, antd::PointerKind::Pointer);
    req.include_signed_quotes = true;
    auto p = c.pointer_prepare(req);
    CHECK(stub.body() == json{{"owner", kA}, {"op", "update"}, {"target", kB},
                              {"kind", "pointer"}, {"include_signed_quotes", true}});
    REQUIRE(p.signed_quotes.size() == 2);
    CHECK(p.signed_quotes[0].quote_hash == "0xq1");
    CHECK(p.signed_quotes[0].quote == "cXVvdGU=");
    REQUIRE(p.signed_quotes[0].commitment_sidecar.has_value());
    CHECK(*p.signed_quotes[0].commitment_sidecar == "c2lkZQ==");
    CHECK_FALSE(p.signed_quotes[1].commitment_sidecar.has_value());
}

TEST_CASE("pointer_prepare transfer sends a recipient, not a target") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto p = c.pointer_prepare(antd::PointerPrepareRequest::transfer(kA, kB));
    CHECK(stub.body() == json{{"owner", kA}, {"op", "transfer"}, {"recipient", kB}});
    CHECK(p.op == "transfer");
    CHECK(p.counter == antd::kPointerFinalCounter);
}

TEST_CASE("pointer_finalize posts upload_id and tx_hashes") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto r = c.pointer_finalize("pup_1", {{"0xq1", "0xtx1"}});
    CHECK(stub.path() == "/v1/pointers/finalize");
    CHECK(stub.body() == json{{"upload_id", "pup_1"}, {"tx_hashes", {{"0xq1", "0xtx1"}}}});
    CHECK(r.address == kA);
    CHECK(r.counter == 5);
    CHECK_FALSE(r.finality.has_value());

    c.pointer_finalize("empty", {});
    CHECK(stub.body() == json{{"upload_id", "empty"}, {"tx_hashes", json::object()}});
}

TEST_CASE("pointer_finalize of a transfer reads its finality") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    auto r = c.pointer_finalize("transfer", {{"0xq1", "0xtx1"}});
    CHECK(r.counter == antd::kPointerFinalCounter);
    REQUIRE(r.finality.has_value());
    CHECK(r.finality->status == antd::PointerFinalityStatus::Unconfirmed);
    CHECK(r.finality->answered == 6);
    REQUIRE(r.finality->state.has_value());
    CHECK(r.finality->state->holders == 6);
}

// ---------------------------------------------------------------------------
// Counters
// ---------------------------------------------------------------------------

TEST_CASE("a malformed counter is an error, never zero") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    for (const auto& [owner, counter] : kBadCounters) {
        CAPTURE(owner);
        CHECK_THROWS_AS(c.pointer_create(owner, kT1), antd::InternalError);
        CHECK_THROWS_AS(c.pointer_get(owner), antd::InternalError);
    }
    CHECK_THROWS_AS(c.pointer_update("no_counter", kT1), antd::InternalError);
}

TEST_CASE("parse_pointer_counter accepts digits only, up to 2^64-1") {
    using antd::detail::parse_pointer_counter;
    CHECK(parse_pointer_counter("counter", "0") == 0);
    CHECK(parse_pointer_counter("counter", "42") == 42);
    CHECK(parse_pointer_counter("counter", "18446744073709551615") == antd::kPointerFinalCounter);
    for (const char* bad : {"", "-1", "-0", "+1", " 1", "1 ", "\t1", "1\n", "0x1", "1e3", "1.0",
                            "18446744073709551616", "99999999999999999999999", "abc"}) {
        CAPTURE(bad);
        CHECK_THROWS_AS(parse_pointer_counter("counter", bad), antd::InternalError);
    }
    try {
        parse_pointer_counter("counter", "-1");
        FAIL("should have thrown");
    } catch (const antd::InternalError& e) {
        CHECK(std::string(e.what()).find("invalid pointer counter \"-1\"") != std::string::npos);
    }
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

TEST_CASE("POINTER_FINAL is a PointerFinalError, not an AlreadyExistsError") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    try {
        c.pointer_update("final", kT1);
        FAIL("should have thrown");
    } catch (const antd::AlreadyExistsError&) {
        FAIL("POINTER_FINAL must not read as AlreadyExistsError");
    } catch (const antd::PointerFinalError& e) {
        CHECK(e.status_code == 409);
        CHECK(std::string(e.what()).find("Pointer is final") != std::string::npos);
    }
    CHECK_THROWS_AS(c.pointer_transfer("final", kB), antd::PointerFinalError);
}

TEST_CASE("POINTER_FORKED is a PointerForkedError, catchable as ForkError") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    CHECK_THROWS_AS(c.pointer_update("forked", kT1), antd::PointerForkedError);
    CHECK_THROWS_AS(c.pointer_update("forked", kT1), antd::ForkError);
    try {
        c.pointer_update("forked", kT1);
    } catch (const antd::AlreadyExistsError&) {
        FAIL("POINTER_FORKED must not read as AlreadyExistsError");
    } catch (const antd::AntdError& e) {
        CHECK(e.status_code == 409);
    }
}

TEST_CASE("CONFLICT is a ConflictError, not an AlreadyExistsError") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    try {
        c.pointer_update("pending", kT1);
        FAIL("should have thrown");
    } catch (const antd::AlreadyExistsError&) {
        FAIL("CONFLICT must not read as AlreadyExistsError");
    } catch (const antd::ConflictError& e) {
        CHECK(e.status_code == 409);
    }
    CHECK_THROWS_AS(c.pointer_prepare(antd::PointerPrepareRequest::update("pending", kT1)),
                    antd::ConflictError);
}

TEST_CASE("ALREADY_EXISTS and a bare 409 keep mapping to AlreadyExistsError") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    CHECK_THROWS_AS(c.pointer_create("exists", kT1), antd::AlreadyExistsError);
    CHECK_THROWS_AS(c.pointer_create("bare409", kT1), antd::AlreadyExistsError);
}

TEST_CASE("an unknown owner is a BadRequestError") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    CHECK_THROWS_AS(c.pointer_create("unknown_owner", kT1), antd::BadRequestError);
}

TEST_CASE("CLOSE_GROUP_SHORTFALL on a read or write is a 503, not retryable") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    for (int i = 0; i < 2; ++i) {
        try {
            if (i == 0) {
                c.pointer_finality("shortfall");
            } else {
                c.pointer_update("shortfall", kT1);
            }
            FAIL("should have thrown");
        } catch (const antd::ServiceUnavailableError&) {
            FAIL("CLOSE_GROUP_SHORTFALL must be its own type");
        } catch (const antd::CloseGroupShortfallError& e) {
            CHECK(e.status_code == 503);
            CHECK_FALSE(e.retryable);
        }
    }
}

TEST_CASE("CLOSE_GROUP_SHORTFALL from a finalize that kept the paid state is retryable") {
    StubServer stub;
    antd::Client c(stub.base_url(), 5);
    try {
        c.pointer_finalize("retained", {{"0xq1", "0xtx1"}});
        FAIL("should have thrown");
    } catch (const antd::CloseGroupShortfallError& e) {
        CHECK(e.status_code == 503);
        CHECK(e.retryable);
    }
    // Only a JSON boolean true counts.
    try {
        c.pointer_finalize("retryable_string", {});
        FAIL("should have thrown");
    } catch (const antd::CloseGroupShortfallError& e) {
        CHECK_FALSE(e.retryable);
    }
    CHECK_THROWS_AS(c.pointer_finalize("unpaid", {}), antd::BadRequestError);
}

TEST_CASE("throw_for_error_code maps only the four codes") {
    CHECK_THROWS_AS(antd::throw_for_error_code("POINTER_FINAL", "m"), antd::PointerFinalError);
    CHECK_THROWS_AS(antd::throw_for_error_code("POINTER_FORKED", "m"), antd::PointerForkedError);
    CHECK_THROWS_AS(antd::throw_for_error_code("CONFLICT", "m"), antd::ConflictError);
    CHECK_THROWS_AS(antd::throw_for_error_code("CLOSE_GROUP_SHORTFALL", "m"),
                    antd::CloseGroupShortfallError);
    for (const char* other : {"ALREADY_EXISTS", "NOT_FOUND", "PARTIAL_UPLOAD", "", "conflict"}) {
        CAPTURE(other);
        CHECK_NOTHROW(antd::throw_for_error_code(other, "m"));
    }
}

// ---------------------------------------------------------------------------
// AsyncClient
// ---------------------------------------------------------------------------

TEST_CASE("AsyncClient pointer methods run the Client calls") {
    StubServer stub;
    antd::AsyncClient c(stub.base_url(), 5);
    CHECK(c.pointer_keys().get().size() == 2);
    CHECK(c.pointer_create(kA, kT1).get().counter == 0);
    CHECK(c.pointer_update(kA, kT2, antd::PointerKind::Pointer).get().counter == 1);
    CHECK(stub.body().value("kind", "") == "pointer");
    CHECK(c.pointer_get("transferred").get().counter == antd::kPointerFinalCounter);
    CHECK(c.pointer_resolve(kA).get().target == kT1);
    CHECK(c.pointer_finality(kA).get().status == antd::PointerFinalityStatus::Open);
    CHECK(c.pointer_controller(kA).get().pointer == kB);
    CHECK(c.pointer_transfer(kA, kB).get().finality.has_value());
    CHECK(c.pointer_prepare(antd::PointerPrepareRequest::transfer(kA, kB)).get().op == "transfer");
    CHECK(c.pointer_finalize("pup_1", {{"0xq1", "0xtx1"}}).get().counter == 5);
    auto failed = c.pointer_update("final", kT1);
    CHECK_THROWS_AS(failed.get(), antd::PointerFinalError);
}
