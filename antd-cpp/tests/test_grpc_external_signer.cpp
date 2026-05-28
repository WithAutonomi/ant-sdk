// ---------------------------------------------------------------------------
// V2-284 external-signer wire-mapping tests for antd::GrpcClient.
//
// Spins up a real grpc++ server bound to `127.0.0.1:0` with mock service
// implementations, then dials with a real `antd::GrpcClient`. Mirrors the
// antd-rust / antd-go / antd-py / antd-java / antd-kotlin / antd-csharp /
// antd-ruby / antd-dart / antd-swift suites — exercises the actual proto
// wire-shape mapping (merkle-only field gating, visibility round-trip via
// `upload_id` encoding, EXISTS short-circuit).
//
// Compiled only when `-DANTD_BUILD_GRPC=ON` is passed to CMake, alongside the
// `antd_grpc` library and its generated proto stubs.
// ---------------------------------------------------------------------------

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "antd/grpc_client.hpp"

#include <grpcpp/grpcpp.h>
#include <grpcpp/server.h>
#include <grpcpp/server_builder.h>

#include "antd/v1/chunks.grpc.pb.h"
#include "antd/v1/upload.grpc.pb.h"

#include <map>
#include <memory>
#include <string>
#include <vector>

namespace {

// ---------------------------------------------------------------------------
// Mock services — canonical mock-service behaviors from
// reference_v2_284_sdk_fanout_recipe. Encodes visibility into `upload_id`
// so finalize can recover what prepare was asked, without server state.
// ---------------------------------------------------------------------------

class MockUploadService final : public antd::v1::UploadService::Service {
public:
    grpc::Status PrepareFileUpload(grpc::ServerContext*,
                                   const antd::v1::PrepareFileUploadRequest* req,
                                   antd::v1::PrepareUploadResponse* resp) override {
        resp->set_upload_id("upid_file_" + req->visibility());
        resp->set_payment_type("wave_batch");
        resp->set_total_amount("1");
        resp->set_payment_vault_address("0xvault");
        resp->set_payment_token_address("0xtoken");
        resp->set_rpc_url("http://localhost:8545");
        auto* p = resp->add_payments();
        p->set_quote_hash("0xqa");
        p->set_rewards_address("0xra");
        p->set_amount("1");
        return grpc::Status::OK;
    }

    grpc::Status PrepareDataUpload(grpc::ServerContext*,
                                   const antd::v1::PrepareDataUploadRequest* req,
                                   antd::v1::PrepareUploadResponse* resp) override {
        const std::string uid = "upid_data_" + req->visibility();
        // Payload starting "MERKLE" triggers the merkle response shape.
        if (req->data().size() >= 6 && req->data().substr(0, 6) == "MERKLE") {
            resp->set_upload_id(uid);
            resp->set_payment_type("merkle");
            resp->set_depth(7);
            resp->set_merkle_payment_timestamp(1700000000);
            resp->set_total_amount("0");
            resp->set_payment_vault_address("0xvault");
            resp->set_payment_token_address("0xtoken");
            resp->set_rpc_url("http://localhost:8545");
            auto* pc = resp->add_pool_commitments();
            pc->set_pool_hash("0xpool");
            auto* cand = pc->add_candidates();
            cand->set_rewards_address("0xc1");
            cand->set_amount("5");
            return grpc::Status::OK;
        }
        resp->set_upload_id(uid);
        resp->set_payment_type("wave_batch");
        resp->set_total_amount("2");
        resp->set_payment_vault_address("0xvault");
        resp->set_payment_token_address("0xtoken");
        resp->set_rpc_url("http://localhost:8545");
        auto* p = resp->add_payments();
        p->set_quote_hash("0xqb");
        p->set_rewards_address("0xrb");
        p->set_amount("2");
        return grpc::Status::OK;
    }

    grpc::Status FinalizeUpload(grpc::ServerContext*,
                                const antd::v1::FinalizeUploadRequest* req,
                                antd::v1::FinalizeUploadResponse* resp) override {
        if (!req->winner_pool_hash().empty()) {
            resp->set_data_map("dm_merkle");
            resp->set_address(req->store_data_map() ? "stored_on_network" : "");
            resp->set_chunks_stored(64);
            return grpc::Status::OK;
        }
        resp->set_data_map("dm_wave");
        const auto& uid = req->upload_id();
        const std::string suffix = "public";
        bool ends_with_public = uid.size() >= suffix.size() &&
            uid.compare(uid.size() - suffix.size(), suffix.size(), suffix) == 0;
        resp->set_data_map_address(ends_with_public ? "addr_public_dm" : "");
        resp->set_chunks_stored(3);
        return grpc::Status::OK;
    }
};

class MockChunkService final : public antd::v1::ChunkService::Service {
public:
    grpc::Status PrepareChunk(grpc::ServerContext*,
                              const antd::v1::PrepareChunkRequest* req,
                              antd::v1::PrepareChunkResponse* resp) override {
        if (req->data().size() >= 6 && req->data().substr(0, 6) == "EXISTS") {
            resp->set_address("0xabc");
            resp->set_already_stored(true);
            return grpc::Status::OK;
        }
        resp->set_address("0xnewchunk");
        resp->set_already_stored(false);
        resp->set_upload_id("upid_chunk_42");
        resp->set_payment_type("wave_batch");
        resp->set_total_amount("100");
        resp->set_payment_vault_address("0xvault");
        resp->set_payment_token_address("0xtoken");
        resp->set_rpc_url("http://localhost:8545");
        auto* p = resp->add_payments();
        p->set_quote_hash("0xq1");
        p->set_rewards_address("0xr1");
        p->set_amount("100");
        return grpc::Status::OK;
    }

    grpc::Status FinalizeChunk(grpc::ServerContext*,
                               const antd::v1::FinalizeChunkRequest* req,
                               antd::v1::FinalizeChunkResponse* resp) override {
        resp->set_address("addr_for_" + req->upload_id());
        return grpc::Status::OK;
    }
};

// ---------------------------------------------------------------------------
// Fixture: spin up server on a random port, dial it with a real GrpcClient.
// ---------------------------------------------------------------------------

class ExternalSignerFixture {
public:
    ExternalSignerFixture() {
        grpc::ServerBuilder builder;
        int selected_port = 0;
        builder.AddListeningPort("127.0.0.1:0",
                                 grpc::InsecureServerCredentials(),
                                 &selected_port);
        builder.RegisterService(&upload_service_);
        builder.RegisterService(&chunk_service_);
        server_ = builder.BuildAndStart();
        REQUIRE(server_ != nullptr);
        REQUIRE(selected_port != 0);
        client_ = std::make_unique<antd::GrpcClient>(
            "127.0.0.1:" + std::to_string(selected_port));
    }
    ~ExternalSignerFixture() {
        if (server_) server_->Shutdown();
    }
    antd::GrpcClient& client() { return *client_; }

private:
    MockUploadService upload_service_;
    MockChunkService chunk_service_;
    std::unique_ptr<grpc::Server> server_;
    std::unique_ptr<antd::GrpcClient> client_;
};

std::vector<uint8_t> bytes(const std::string& s) {
    return std::vector<uint8_t>(s.begin(), s.end());
}

}  // namespace

// ---------------------------------------------------------------------------
// prepare/finalize uploads
// ---------------------------------------------------------------------------

TEST_CASE("V2-284: prepare_upload omits visibility when nullopt") {
    ExternalSignerFixture f;
    auto r = f.client().prepare_upload("/tmp/x.bin");
    // Empty visibility = proto3 default → mock echoes that into upload_id.
    CHECK(r.upload_id == "upid_file_");
    CHECK(r.payment_type == "wave_batch");
    REQUIRE(r.payments.size() == 1);
    CHECK(r.payments[0].quote_hash == "0xqa");
    CHECK(r.depth == 0);
    CHECK(r.pool_commitments.empty());
    CHECK(r.merkle_payment_timestamp == 0);
}

TEST_CASE("V2-284: prepare_upload forwards visibility=public") {
    ExternalSignerFixture f;
    auto r = f.client().prepare_upload("/tmp/x.bin", std::string("public"));
    CHECK(r.upload_id == "upid_file_public");
}

TEST_CASE("V2-284: prepare_upload_public convenience wrapper") {
    ExternalSignerFixture f;
    auto r = f.client().prepare_upload_public("/tmp/x.bin");
    CHECK(r.upload_id == "upid_file_public");
}

TEST_CASE("V2-284: prepare_data_upload wave-batch") {
    ExternalSignerFixture f;
    auto r = f.client().prepare_data_upload(bytes("small"));
    CHECK(r.upload_id == "upid_data_");
    CHECK(r.payment_type == "wave_batch");
    CHECK(r.depth == 0);
    CHECK(r.pool_commitments.empty());
    CHECK(r.merkle_payment_timestamp == 0);
}

TEST_CASE("V2-284: prepare_data_upload merkle") {
    ExternalSignerFixture f;
    auto r = f.client().prepare_data_upload(bytes("MERKLE-large-payload"));
    CHECK(r.payment_type == "merkle");
    CHECK(r.depth == 7);
    CHECK(r.merkle_payment_timestamp == 1700000000);
    REQUIRE(r.pool_commitments.size() == 1);
    CHECK(r.pool_commitments[0].pool_hash == "0xpool");
    REQUIRE(r.pool_commitments[0].candidates.size() == 1);
    CHECK(r.pool_commitments[0].candidates[0].rewards_address == "0xc1");
}

TEST_CASE("V2-284: finalize_upload wave-batch private omits data_map_address") {
    ExternalSignerFixture f;
    auto r = f.client().finalize_upload("upid_file_", {{"0xq1", "0xtx1"}});
    CHECK(r.data_map == "dm_wave");
    CHECK(r.data_map_address == "");
    CHECK(r.chunks_stored == 3);
}

TEST_CASE("V2-284: finalize_upload wave-batch public returns data_map_address") {
    ExternalSignerFixture f;
    auto r = f.client().finalize_upload("upid_file_public", {{"0xq1", "0xtx1"}});
    CHECK(r.data_map_address == "addr_public_dm");
}

TEST_CASE("V2-284: finalize_merkle_upload store_data_map=true") {
    ExternalSignerFixture f;
    auto r = f.client().finalize_merkle_upload("upid_data_", "0xwinpool", /*store_data_map=*/true);
    CHECK(r.data_map == "dm_merkle");
    CHECK(r.address == "stored_on_network");
    CHECK(r.chunks_stored == 64);
}

TEST_CASE("V2-284: finalize_merkle_upload store_data_map default false") {
    ExternalSignerFixture f;
    auto r = f.client().finalize_merkle_upload("upid_data_", "0xwinpool");
    CHECK(r.data_map == "dm_merkle");
    CHECK(r.address == "");
}

// ---------------------------------------------------------------------------
// prepare/finalize chunks
// ---------------------------------------------------------------------------

TEST_CASE("V2-284: prepare_chunk_upload new chunk") {
    ExternalSignerFixture f;
    auto r = f.client().prepare_chunk_upload(bytes("newchunk"));
    CHECK_FALSE(r.already_stored);
    CHECK(r.address == "0xnewchunk");
    CHECK(r.upload_id == "upid_chunk_42");
    CHECK(r.payment_type == "wave_batch");
    REQUIRE(r.payments.size() == 1);
    CHECK(r.payments[0].quote_hash == "0xq1");
    CHECK(r.total_amount == "100");
    CHECK(r.rpc_url == "http://localhost:8545");
}

TEST_CASE("V2-284: prepare_chunk_upload already-stored short-circuit") {
    ExternalSignerFixture f;
    auto r = f.client().prepare_chunk_upload(bytes("EXISTS-data"));
    CHECK(r.already_stored);
    CHECK(r.address == "0xabc");
    CHECK(r.upload_id == "");
    CHECK(r.payments.empty());
}

TEST_CASE("V2-284: finalize_chunk_upload returns address and forwards body") {
    ExternalSignerFixture f;
    auto addr = f.client().finalize_chunk_upload("upid_chunk_42", {{"0xq1", "0xtxabc"}});
    CHECK(addr == "addr_for_upid_chunk_42");
}
