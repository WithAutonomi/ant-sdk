// ---------------------------------------------------------------------------
// PointerService wire-mapping tests for antd::GrpcClient.
//
// Spins up a real grpc++ server bound to `127.0.0.1:0` with a mock
// PointerService, then dials it with a real `antd::GrpcClient`. Covers every
// pointer RPC's request and response mapping (decimal-string counters, "" and
// absent messages for unset values, base64 for signed-quote bytes) and the
// error mapping by the `x-antd-error-code` trailer, which counts only when it
// agrees with the status code.
//
// Compiled only when `-DANTD_BUILD_GRPC=ON` is passed to CMake, alongside the
// `antd_grpc` library and its generated proto stubs.
// ---------------------------------------------------------------------------

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "antd/errors.hpp"
#include "antd/grpc_client.hpp"

#include <grpcpp/grpcpp.h>
#include <grpcpp/server.h>
#include <grpcpp/server_builder.h>

#include "antd/v1/pointers.grpc.pb.h"

#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace {

namespace v1 = antd::v1;

const std::string kA(64, 'a');
const std::string kB(64, 'b');
const std::string kT1(64, '1');
const std::string kT2(64, '2');
const std::string kState(64, 'c');
const char* const kFinal = "18446744073709551615";

/// A failed status with the daemon's error code in the trailers.
grpc::Status tagged(grpc::ServerContext* ctx, grpc::StatusCode code, const std::string& tag,
                    const std::string& message) {
    ctx->AddTrailingMetadata("x-antd-error-code", tag);
    return grpc::Status(code, message);
}

void set_final_state(v1::PointerFinalState* s, const std::string& target, std::uint32_t holders,
                     const std::string& transferred_to) {
    s->set_state_id(kState);
    s->set_kind("pointer");
    s->set_kind_tag(1);
    s->set_target(target);
    s->set_holders(holders);
    s->set_transferred_to(transferred_to);
}

class MockPointerService final : public v1::PointerService::Service {
public:
    std::mutex mu;
    v1::PointerWriteRequest last_write;
    v1::PointerTransferRequest last_transfer;
    v1::PreparePointerRequest last_prepare;
    v1::FinalizePointerRequest last_finalize;

    grpc::Status ListKeys(grpc::ServerContext*, const v1::ListPointerKeysRequest*,
                          v1::ListPointerKeysResponse* resp) override {
        resp->add_keys()->set_address(kA);
        resp->add_keys()->set_address(kB);
        return grpc::Status::OK;
    }

    grpc::Status Create(grpc::ServerContext* ctx, const v1::PointerWriteRequest* req,
                        v1::PointerWriteResponse* resp) override {
        return write(ctx, req, resp, "0");
    }

    grpc::Status Update(grpc::ServerContext* ctx, const v1::PointerWriteRequest* req,
                        v1::PointerWriteResponse* resp) override {
        return write(ctx, req, resp, "1");
    }

    grpc::Status Transfer(grpc::ServerContext* ctx, const v1::PointerTransferRequest* req,
                          v1::PointerTransferResponse* resp) override {
        {
            std::lock_guard<std::mutex> lock(mu);
            last_transfer = *req;
        }
        if (req->owner() == "final") {
            return tagged(ctx, grpc::StatusCode::FAILED_PRECONDITION, "POINTER_FINAL",
                          "Pointer is final: transferred");
        }
        resp->set_address(kA);
        resp->set_state_id(kState);
        if (req->owner() == "unchecked") {
            resp->set_finality_error("Close group shortfall: 4 of 7 answered");
            return grpc::Status::OK;
        }
        auto* f = resp->mutable_finality();
        f->set_address(kA);
        f->set_group(7);
        f->set_answered(7);
        f->set_status("final");
        set_final_state(f->mutable_state(), kB, 7, kB);
        f->set_transferred_to(kB);
        return grpc::Status::OK;
    }

    grpc::Status Get(grpc::ServerContext*, const v1::GetPointerRequest* req,
                     v1::PointerRecord* resp) override {
        const auto& addr = req->address();
        if (addr == "missing") {
            return grpc::Status(grpc::StatusCode::NOT_FOUND, "Record not found: no pointer");
        }
        resp->set_address(kA);
        resp->set_owner(std::string(2 * 1952, 'e'));
        resp->set_state_id(kState);
        if (addr == "transferred") {
            resp->set_counter(kFinal);
            resp->set_kind("pointer");
            resp->set_kind_tag(1);
            resp->set_target(kB);
            resp->set_is_final(true);
            resp->set_transferred_to(kB);
            return grpc::Status::OK;
        }
        if (addr == "wide_tag") {
            resp->set_counter("3");
            resp->set_kind("unknown");
            resp->set_kind_tag(300);
            return grpc::Status::OK;
        }
        if (addr == "neg" || addr == "space" || addr == "empty" || addr == "overflow") {
            const std::map<std::string, std::string> bad = {
                {"neg", "-1"}, {"space", " 1"}, {"empty", ""},
                {"overflow", "18446744073709551616"},
            };
            resp->set_counter(bad.at(addr));
            return grpc::Status::OK;
        }
        resp->set_counter("1");
        resp->set_kind("chunk");
        resp->set_kind_tag(0);
        resp->set_target(kT2);
        return grpc::Status::OK;
    }

    grpc::Status Resolve(grpc::ServerContext*, const v1::ResolvePointerRequest*,
                         v1::PointerResolved* resp) override {
        resp->set_kind("chunk");
        resp->set_kind_tag(0);
        resp->set_target(kT1);
        return grpc::Status::OK;
    }

    grpc::Status Finality(grpc::ServerContext* ctx, const v1::PointerFinalityRequest* req,
                          v1::PointerFinality* resp) override {
        const auto& addr = req->address();
        if (addr == "shortfall") {
            return tagged(ctx, grpc::StatusCode::UNAVAILABLE, "CLOSE_GROUP_SHORTFALL",
                          "Close group shortfall: only 2 of 7 answered");
        }
        if (addr == "untagged_unavailable") {
            return grpc::Status(grpc::StatusCode::UNAVAILABLE, "transport closed");
        }
        resp->set_address(kA);
        resp->set_group(7);
        resp->set_answered(7);
        if (addr == "forked") {
            resp->set_status("forked");
            set_final_state(resp->add_states(), kB, 5, kB);
            set_final_state(resp->add_states(), kT2, 2, "");
            set_final_state(resp->mutable_majority(), kB, 5, kB);
            return grpc::Status::OK;
        }
        if (addr == "no_counter") {
            resp->set_status("open");
            return grpc::Status::OK;
        }
        if (addr == "bad_counter") {
            resp->set_status("open");
            resp->set_counter("-1");
            return grpc::Status::OK;
        }
        if (addr == "unknown_status") {
            resp->set_status("contested");
            return grpc::Status::OK;
        }
        resp->set_status("open");
        resp->set_counter("1");
        return grpc::Status::OK;
    }

    grpc::Status Controller(grpc::ServerContext*, const v1::PointerControllerRequest*,
                            v1::PointerController* resp) override {
        resp->set_pointer(kB);
        resp->add_transfers(kB);
        resp->set_frozen(false);
        return grpc::Status::OK;
    }

    grpc::Status Prepare(grpc::ServerContext* ctx, const v1::PreparePointerRequest* req,
                         v1::PreparePointerResponse* resp) override {
        {
            std::lock_guard<std::mutex> lock(mu);
            last_prepare = *req;
        }
        if (req->owner() == "pending") {
            return tagged(ctx, grpc::StatusCode::ABORTED, "CONFLICT",
                          "Conflict: a prepared write awaits payment");
        }
        resp->set_upload_id("pup_1");
        resp->set_op(req->op());
        resp->set_address(req->owner());
        resp->set_state_id(kState);
        resp->set_counter(req->op() == "transfer" ? kFinal : "2");
        resp->set_payment_type("wave_batch");
        auto* p = resp->add_payments();
        p->set_quote_hash("0xq1");
        p->set_rewards_address("0xr1");
        p->set_amount("123");
        resp->set_total_amount("123");
        resp->set_payment_vault_address("0xvault");
        resp->set_payment_token_address("0xtoken");
        resp->set_rpc_url("http://rpc.local");
        if (req->include_signed_quotes()) {
            auto* q = resp->add_signed_quotes();
            q->set_quote_hash("0xq1");
            q->set_quote("quote");
            q->set_commitment_sidecar("side");
            auto* q2 = resp->add_signed_quotes();
            q2->set_quote_hash("0xq2");
            q2->set_quote("quote2");
        }
        return grpc::Status::OK;
    }

    grpc::Status Finalize(grpc::ServerContext* ctx, const v1::FinalizePointerRequest* req,
                          v1::FinalizePointerResponse* resp) override {
        {
            std::lock_guard<std::mutex> lock(mu);
            last_finalize = *req;
        }
        if (req->upload_id() == "retained") {
            return tagged(ctx, grpc::StatusCode::UNAVAILABLE, "CLOSE_GROUP_SHORTFALL",
                          "Close group shortfall: stored on 4 of 7 (paid attempt retained: call "
                          "finalize again with the same upload_id to store it against the same "
                          "payment)");
        }
        resp->set_address(kA);
        resp->set_state_id(kState);
        resp->set_counter("5");
        if (req->upload_id() == "transfer") {
            resp->set_counter(kFinal);
            auto* f = resp->mutable_finality();
            f->set_address(kA);
            f->set_group(7);
            f->set_answered(6);
            f->set_status("unconfirmed");
            set_final_state(f->mutable_state(), kB, 6, kB);
        }
        return grpc::Status::OK;
    }

private:
    grpc::Status write(grpc::ServerContext* ctx, const v1::PointerWriteRequest* req,
                       v1::PointerWriteResponse* resp, const char* counter) {
        {
            std::lock_guard<std::mutex> lock(mu);
            last_write = *req;
        }
        const auto& owner = req->owner();
        if (owner == "exists") {
            return grpc::Status(grpc::StatusCode::ALREADY_EXISTS, "Already exists: pointer");
        }
        if (owner == "final") {
            return tagged(ctx, grpc::StatusCode::FAILED_PRECONDITION, "POINTER_FINAL",
                          "Pointer is final: transferred");
        }
        if (owner == "forked") {
            return tagged(ctx, grpc::StatusCode::FAILED_PRECONDITION, "POINTER_FORKED",
                          "Pointer is forked: two finals");
        }
        if (owner == "pending") {
            return tagged(ctx, grpc::StatusCode::ABORTED, "CONFLICT",
                          "Conflict: a prepared write awaits payment");
        }
        if (owner == "unpaid") {
            return grpc::Status(grpc::StatusCode::FAILED_PRECONDITION,
                                "Payment error: wallet not configured");
        }
        // Tags that disagree with the status code are not trusted.
        if (owner == "conflict_on_precondition") {
            return tagged(ctx, grpc::StatusCode::FAILED_PRECONDITION, "CONFLICT", "no funds");
        }
        if (owner == "final_on_aborted") {
            return tagged(ctx, grpc::StatusCode::ABORTED, "POINTER_FINAL", "aborted");
        }
        if (owner == "unknown_tag") {
            return tagged(ctx, grpc::StatusCode::FAILED_PRECONDITION, "SOMETHING_NEW", "x");
        }
        if (owner == "bad_counter") {
            resp->set_address(kA);
            resp->set_counter("1e3");
            return grpc::Status::OK;
        }
        resp->set_address(owner);
        resp->set_state_id(kState);
        resp->set_counter(counter);
        return grpc::Status::OK;
    }
};

class PointerFixture {
public:
    PointerFixture() {
        grpc::ServerBuilder builder;
        int selected_port = 0;
        builder.AddListeningPort("127.0.0.1:0", grpc::InsecureServerCredentials(),
                                 &selected_port);
        builder.RegisterService(&service_);
        server_ = builder.BuildAndStart();
        REQUIRE(server_ != nullptr);
        REQUIRE(selected_port != 0);
        client_ = std::make_unique<antd::GrpcClient>("127.0.0.1:" +
                                                     std::to_string(selected_port));
    }
    ~PointerFixture() {
        if (server_) server_->Shutdown();
    }
    antd::GrpcClient& client() { return *client_; }
    MockPointerService& service() { return service_; }

private:
    MockPointerService service_;
    std::unique_ptr<grpc::Server> server_;
    std::unique_ptr<antd::GrpcClient> client_;
};

}  // namespace

// ---------------------------------------------------------------------------
// Methods
// ---------------------------------------------------------------------------

TEST_CASE("grpc pointer_keys") {
    PointerFixture f;
    auto keys = f.client().pointer_keys();
    REQUIRE(keys.size() == 2);
    CHECK(keys[0].address == kA);
    CHECK(keys[1].address == kB);
}

TEST_CASE("grpc pointer_create / pointer_update forward owner, target and kind") {
    PointerFixture f;
    auto w = f.client().pointer_create(kA, kT1);
    CHECK(w.address == kA);
    CHECK(w.state_id == kState);
    CHECK(w.counter == 0);
    {
        std::lock_guard<std::mutex> lock(f.service().mu);
        CHECK(f.service().last_write.owner() == kA);
        CHECK(f.service().last_write.target() == kT1);
        CHECK(f.service().last_write.kind() == "chunk");
    }
    auto u = f.client().pointer_update(kA, kB, antd::PointerKind::Pointer);
    CHECK(u.counter == 1);
    std::lock_guard<std::mutex> lock(f.service().mu);
    CHECK(f.service().last_write.kind() == "pointer");
}

TEST_CASE("grpc pointer_transfer reads the finality, or keeps its error") {
    PointerFixture f;
    auto t = f.client().pointer_transfer(kA, kB);
    {
        std::lock_guard<std::mutex> lock(f.service().mu);
        CHECK(f.service().last_transfer.owner() == kA);
        CHECK(f.service().last_transfer.recipient() == kB);
    }
    CHECK(t.address == kA);
    CHECK_FALSE(t.finality_error.has_value());
    REQUIRE(t.finality.has_value());
    CHECK(t.finality->is_final());
    CHECK(t.finality->status_raw == "final");
    CHECK_FALSE(t.finality->counter.has_value());
    REQUIRE(t.finality->state.has_value());
    CHECK(t.finality->state->holders == 7);
    REQUIRE(t.finality->state->transferred_to.has_value());
    CHECK(*t.finality->state->transferred_to == kB);
    CHECK_FALSE(t.finality->majority.has_value());
    REQUIRE(t.finality->transferred_to.has_value());
    CHECK(*t.finality->transferred_to == kB);

    auto u = f.client().pointer_transfer("unchecked", kB);
    CHECK_FALSE(u.finality.has_value());
    REQUIRE(u.finality_error.has_value());
    CHECK(u.finality_error->find("shortfall") != std::string::npos);
}

TEST_CASE("grpc pointer_get: final counter, and empty strings read as unset") {
    PointerFixture f;
    auto r = f.client().pointer_get("transferred");
    CHECK(r.counter == antd::kPointerFinalCounter);
    CHECK(r.is_final);
    CHECK(r.owner.size() == 2 * 1952);
    CHECK(r.target_kind() == antd::PointerKind::Pointer);
    REQUIRE(r.transferred_to.has_value());
    CHECK(*r.transferred_to == kB);

    auto open = f.client().pointer_get(kA);
    CHECK(open.counter == 1);
    CHECK_FALSE(open.is_final);
    CHECK(open.target == kT2);
    CHECK_FALSE(open.transferred_to.has_value());

    auto wide = f.client().pointer_get("wide_tag");
    CHECK(wide.kind_tag == 0xFF);
    CHECK_FALSE(wide.target_kind().has_value());

    CHECK_THROWS_AS(f.client().pointer_get("missing"), antd::NotFoundError);
}

TEST_CASE("grpc pointer_get: a malformed counter is an error, never zero") {
    PointerFixture f;
    for (const std::string addr : {"neg", "space", "empty", "overflow"}) {
        CAPTURE(addr);
        CHECK_THROWS_AS(f.client().pointer_get(addr), antd::InternalError);
    }
    CHECK_THROWS_AS(f.client().pointer_create("bad_counter", kT1), antd::InternalError);
}

TEST_CASE("grpc pointer_resolve and pointer_controller") {
    PointerFixture f;
    auto t = f.client().pointer_resolve(kA);
    CHECK(t.kind == "chunk");
    CHECK(t.kind_tag == 0);
    CHECK(t.target == kT1);
    auto c = f.client().pointer_controller(kA);
    CHECK(c.pointer == kB);
    CHECK(c.transfers == std::vector<std::string>{kB});
    CHECK_FALSE(c.frozen);
}

TEST_CASE("grpc pointer_finality: open, unset counter, forked and unknown statuses") {
    PointerFixture f;
    auto open = f.client().pointer_finality(kA);
    CHECK(open.status == antd::PointerFinalityStatus::Open);
    CHECK(open.group == 7);
    CHECK(open.answered == 7);
    REQUIRE(open.counter.has_value());
    CHECK(*open.counter == 1);
    CHECK_FALSE(open.state.has_value());
    CHECK_FALSE(open.majority.has_value());
    CHECK_FALSE(open.transferred_to.has_value());

    CHECK_FALSE(f.client().pointer_finality("no_counter").counter.has_value());
    CHECK_THROWS_AS(f.client().pointer_finality("bad_counter"), antd::InternalError);

    auto forked = f.client().pointer_finality("forked");
    CHECK(forked.status == antd::PointerFinalityStatus::Forked);
    REQUIRE(forked.states.size() == 2);
    CHECK(forked.states[0].holders == 5);
    CHECK(forked.states[1].target == kT2);
    CHECK_FALSE(forked.states[1].transferred_to.has_value());
    REQUIRE(forked.majority.has_value());
    CHECK(forked.majority->target == kB);

    auto unknown = f.client().pointer_finality("unknown_status");
    CHECK(unknown.status == antd::PointerFinalityStatus::Unknown);
    CHECK(unknown.status_raw == "contested");
}

TEST_CASE("grpc pointer_prepare forwards the op's fields and base64s signed quotes") {
    PointerFixture f;
    auto req = antd::PointerPrepareRequest::create(kA, kT1);
    req.include_signed_quotes = true;
    auto p = f.client().pointer_prepare(req);
    {
        std::lock_guard<std::mutex> lock(f.service().mu);
        const auto& sent = f.service().last_prepare;
        CHECK(sent.owner() == kA);
        CHECK(sent.op() == "create");
        CHECK(sent.target() == kT1);
        CHECK(sent.kind() == "chunk");
        CHECK(sent.recipient().empty());
        CHECK(sent.include_signed_quotes());
    }
    CHECK(p.upload_id == "pup_1");
    CHECK(p.op == "create");
    CHECK(p.counter == 2);
    CHECK(p.payment_type == "wave_batch");
    REQUIRE(p.payments.size() == 1);
    CHECK(p.payments[0].quote_hash == "0xq1");
    CHECK(p.payments[0].amount == "123");
    CHECK(p.total_amount == "123");
    CHECK(p.payment_vault_address == "0xvault");
    CHECK(p.payment_token_address == "0xtoken");
    CHECK(p.rpc_url == "http://rpc.local");
    REQUIRE(p.signed_quotes.size() == 2);
    CHECK(p.signed_quotes[0].quote_hash == "0xq1");
    CHECK(p.signed_quotes[0].quote == "cXVvdGU=");
    REQUIRE(p.signed_quotes[0].commitment_sidecar.has_value());
    CHECK(*p.signed_quotes[0].commitment_sidecar == "c2lkZQ==");
    CHECK(p.signed_quotes[1].quote == "cXVvdGUy");
    CHECK_FALSE(p.signed_quotes[1].commitment_sidecar.has_value());

    auto t = f.client().pointer_prepare(antd::PointerPrepareRequest::transfer(kA, kB));
    {
        std::lock_guard<std::mutex> lock(f.service().mu);
        const auto& sent = f.service().last_prepare;
        CHECK(sent.op() == "transfer");
        CHECK(sent.recipient() == kB);
        CHECK(sent.target().empty());
        CHECK(sent.kind().empty());
        CHECK_FALSE(sent.include_signed_quotes());
    }
    CHECK(t.counter == antd::kPointerFinalCounter);
    CHECK(t.signed_quotes.empty());
}

TEST_CASE("grpc pointer_finalize forwards upload_id and tx_hashes") {
    PointerFixture f;
    auto r = f.client().pointer_finalize("pup_1", {{"0xq1", "0xtx1"}});
    {
        std::lock_guard<std::mutex> lock(f.service().mu);
        CHECK(f.service().last_finalize.upload_id() == "pup_1");
        REQUIRE(f.service().last_finalize.tx_hashes().size() == 1);
        CHECK(f.service().last_finalize.tx_hashes().at("0xq1") == "0xtx1");
    }
    CHECK(r.counter == 5);
    CHECK_FALSE(r.finality.has_value());

    auto t = f.client().pointer_finalize("transfer", {{"0xq1", "0xtx1"}});
    CHECK(t.counter == antd::kPointerFinalCounter);
    REQUIRE(t.finality.has_value());
    CHECK(t.finality->status == antd::PointerFinalityStatus::Unconfirmed);
    CHECK(t.finality->answered == 6);
}

// ---------------------------------------------------------------------------
// Errors by the x-antd-error-code trailer
// ---------------------------------------------------------------------------

TEST_CASE("grpc trailer POINTER_FINAL -> PointerFinalError, not PaymentError") {
    PointerFixture f;
    try {
        f.client().pointer_update("final", kT1);
        FAIL("should have thrown");
    } catch (const antd::PaymentError&) {
        FAIL("a tagged POINTER_FINAL must not read as PaymentError");
    } catch (const antd::PointerFinalError& e) {
        CHECK(e.status_code == 409);
        CHECK(std::string(e.what()).find("Pointer is final") != std::string::npos);
    }
    CHECK_THROWS_AS(f.client().pointer_transfer("final", kB), antd::PointerFinalError);
}

TEST_CASE("grpc trailer POINTER_FORKED -> PointerForkedError, a ForkError") {
    PointerFixture f;
    CHECK_THROWS_AS(f.client().pointer_update("forked", kT1), antd::PointerForkedError);
    CHECK_THROWS_AS(f.client().pointer_update("forked", kT1), antd::ForkError);
}

TEST_CASE("grpc trailer CONFLICT -> ConflictError") {
    PointerFixture f;
    CHECK_THROWS_AS(f.client().pointer_update("pending", kT1), antd::ConflictError);
    CHECK_THROWS_AS(f.client().pointer_prepare(antd::PointerPrepareRequest::update("pending", kT1)),
                    antd::ConflictError);
}

TEST_CASE("grpc trailer CLOSE_GROUP_SHORTFALL -> CloseGroupShortfallError") {
    PointerFixture f;
    try {
        f.client().pointer_finality("shortfall");
        FAIL("should have thrown");
    } catch (const antd::NetworkError&) {
        FAIL("a tagged shortfall must not read as NetworkError");
    } catch (const antd::CloseGroupShortfallError& e) {
        CHECK(e.status_code == 503);
        CHECK_FALSE(e.retryable);
    }
    try {
        f.client().pointer_finalize("retained", {{"0xq1", "0xtx1"}});
        FAIL("should have thrown");
    } catch (const antd::CloseGroupShortfallError& e) {
        CHECK(e.retryable);
    }
}

TEST_CASE("grpc untagged or mismatched statuses keep the code mapping") {
    PointerFixture f;
    CHECK_THROWS_AS(f.client().pointer_create("exists", kT1), antd::AlreadyExistsError);
    CHECK_THROWS_AS(f.client().pointer_update("unpaid", kT1), antd::PaymentError);
    CHECK_THROWS_AS(f.client().pointer_update("conflict_on_precondition", kT1),
                    antd::PaymentError);
    CHECK_THROWS_AS(f.client().pointer_update("unknown_tag", kT1), antd::PaymentError);
    CHECK_THROWS_AS(f.client().pointer_finality("untagged_unavailable"), antd::NetworkError);
    try {
        f.client().pointer_update("final_on_aborted", kT1);
        FAIL("should have thrown");
    } catch (const antd::PointerFinalError&) {
        FAIL("POINTER_FINAL on ABORTED must not be trusted");
    } catch (const antd::AntdError& e) {
        CHECK(e.status_code == static_cast<int>(grpc::StatusCode::ABORTED));
    }
}
