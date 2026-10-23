// ---------------------------------------------------------------------------
// sha256 field tests for antd::GrpcClient (antd 0.17.0).
//
// Spins up a real grpc++ server bound to `127.0.0.1:0` with mock Data, File,
// Upload and Manifest services, then dials it with a real `antd::GrpcClient`.
// Covers the upload results (PutData, PutPublicData, PutFile, PutFilePublic
// and FinalizeUpload), each reading `sha256` when set and std::nullopt when
// the proto3 string is "" (its zero value, so also an antd before 0.17.0);
// the manifest entry input (`optional string`, set only when given and
// non-empty, so presence is meaningful); the manifest entry info (plain
// string, "" reads as none); and INVALID_ARGUMENT for a bad hash as
// BadRequestError.
//
// Compiled only when `-DANTD_BUILD_GRPC=ON` is passed to CMake, alongside the
// `antd_grpc` library and its generated proto stubs.
// ---------------------------------------------------------------------------

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "antd/errors.hpp"
#include "antd/grpc_client.hpp"
#include "antd/manifests.hpp"

#include <grpc/grpc.h>
#include <grpcpp/grpcpp.h>
#include <grpcpp/server.h>
#include <grpcpp/server_builder.h>

#include "antd/v1/data.grpc.pb.h"
#include "antd/v1/files.grpc.pb.h"
#include "antd/v1/manifests.grpc.pb.h"
#include "antd/v1/upload.grpc.pb.h"

#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace {

namespace v1 = antd::v1;

const std::string kSha(64, 'a');
const std::string kSha2 = std::string(32, '0') + std::string(32, 'f');

/// What the mocks answer: the sha256 every response carries ("" leaves the
/// proto3 string at its zero value), and the last manifest build request.
struct MockState {
    std::mutex mu;
    std::string sha;
    v1::BuildManifestRequest last_build;
};

class MockData final : public v1::DataService::Service {
public:
    explicit MockData(MockState* s) : s_(s) {}
    grpc::Status Put(grpc::ServerContext*, const v1::PutDataRequest*,
                     v1::PutDataResponse* resp) override {
        resp->set_data_map("dm");
        resp->set_sha256(sha());
        return grpc::Status::OK;
    }
    grpc::Status PutPublic(grpc::ServerContext*, const v1::PutPublicDataRequest*,
                           v1::PutPublicDataResponse* resp) override {
        resp->set_address("pub");
        resp->set_sha256(sha());
        return grpc::Status::OK;
    }

private:
    std::string sha() {
        std::lock_guard<std::mutex> lock(s_->mu);
        return s_->sha;
    }
    MockState* s_;
};

class MockFiles final : public v1::FileService::Service {
public:
    explicit MockFiles(MockState* s) : s_(s) {}
    grpc::Status Put(grpc::ServerContext*, const v1::PutFileRequest*,
                     v1::PutFileResponse* resp) override {
        resp->set_data_map("fdm");
        resp->set_sha256(sha());
        return grpc::Status::OK;
    }
    grpc::Status PutPublic(grpc::ServerContext*, const v1::PutFileRequest*,
                           v1::PutFilePublicResponse* resp) override {
        resp->set_address("fpub");
        resp->set_sha256(sha());
        return grpc::Status::OK;
    }

private:
    std::string sha() {
        std::lock_guard<std::mutex> lock(s_->mu);
        return s_->sha;
    }
    MockState* s_;
};

class MockUpload final : public v1::UploadService::Service {
public:
    explicit MockUpload(MockState* s) : s_(s) {}
    grpc::Status FinalizeUpload(grpc::ServerContext*, const v1::FinalizeUploadRequest*,
                                v1::FinalizeUploadResponse* resp) override {
        resp->set_data_map("dm");
        resp->set_chunks_stored(3);
        std::lock_guard<std::mutex> lock(s_->mu);
        resp->set_sha256(s_->sha);
        return grpc::Status::OK;
    }

private:
    MockState* s_;
};

class MockManifests final : public v1::ManifestService::Service {
public:
    explicit MockManifests(MockState* s) : s_(s) {}
    grpc::Status Build(grpc::ServerContext*, const v1::BuildManifestRequest* req,
                       v1::BuildManifestResponse* resp) override {
        std::lock_guard<std::mutex> lock(s_->mu);
        s_->last_build = *req;
        for (int i = 0; i < req->entries_size(); ++i) {
            if (req->entries(i).has_sha256() && req->entries(i).sha256() == "zz") {
                return grpc::Status(grpc::StatusCode::INVALID_ARGUMENT,
                                    "Bad request: entries[" + std::to_string(i) +
                                        "]: invalid hex sha256: Odd number of digits");
            }
        }
        resp->set_manifest("\xC1" "ANT\x01");
        add_entry(resp->add_entries());
        return grpc::Status::OK;
    }
    grpc::Status Decode(grpc::ServerContext*, const v1::DecodeManifestRequest*,
                        v1::DecodeManifestResponse* resp) override {
        std::lock_guard<std::mutex> lock(s_->mu);
        resp->set_source("manifest");
        add_entry(resp->add_entries());
        return grpc::Status::OK;
    }

private:
    void add_entry(v1::ManifestEntryInfo* e) {
        e->set_effective_name("a.txt");
        e->set_path("a.txt");
        e->set_kind("public");
        e->set_content_address("cc");
        e->set_sha256(s_->sha);
    }
    MockState* s_;
};

class Fixture {
public:
    Fixture() : data_(&state_), files_(&state_), upload_(&state_), manifests_(&state_) {
        grpc::ServerBuilder builder;
        builder.AddListeningPort("127.0.0.1:0", grpc::InsecureServerCredentials(), &port_);
        builder.RegisterService(&data_);
        builder.RegisterService(&files_);
        builder.RegisterService(&upload_);
        builder.RegisterService(&manifests_);
        server_ = builder.BuildAndStart();
        REQUIRE(server_ != nullptr);
        REQUIRE(port_ != 0);
        client_ = std::make_unique<antd::GrpcClient>("127.0.0.1:" + std::to_string(port_));
    }
    ~Fixture() {
        if (server_) server_->Shutdown();
    }
    antd::GrpcClient& client() { return *client_; }
    void set_sha(std::string s) {
        std::lock_guard<std::mutex> lock(state_.mu);
        state_.sha = std::move(s);
    }
    v1::BuildManifestRequest last_build() {
        std::lock_guard<std::mutex> lock(state_.mu);
        return state_.last_build;
    }

private:
    int port_{0};
    MockState state_;
    MockData data_;
    MockFiles files_;
    MockUpload upload_;
    MockManifests manifests_;
    std::unique_ptr<grpc::Server> server_;
    std::unique_ptr<antd::GrpcClient> client_;
};

const std::vector<uint8_t> kData = {'h', 'i'};

/// Run `read` against the mock with a hash set, then with the proto3 zero
/// value (""), which is also what an antd before 0.17.0 sends.
template <typename Read>
void check_upload_sha(Read read) {
    Fixture f;
    f.set_sha(kSha);
    CHECK(read(f.client()) == std::optional<std::string>(kSha));
    f.set_sha("");
    CHECK_FALSE(read(f.client()).has_value());
}

}  // namespace

TEST_CASE("grpc data_put reads sha256, and none when empty") {
    check_upload_sha([](antd::GrpcClient& c) { return c.data_put(kData).sha256; });
}

TEST_CASE("grpc data_put_public reads sha256, and none when empty") {
    check_upload_sha([](antd::GrpcClient& c) { return c.data_put_public(kData).sha256; });
}

TEST_CASE("grpc file_put reads sha256, and none when empty") {
    check_upload_sha([](antd::GrpcClient& c) { return c.file_put("/tmp/x").sha256; });
}

TEST_CASE("grpc file_put_public reads sha256, and none when empty") {
    check_upload_sha([](antd::GrpcClient& c) { return c.file_put_public("/tmp/x").sha256; });
}

TEST_CASE("grpc finalize_upload (wave) reads sha256, and none when empty") {
    check_upload_sha([](antd::GrpcClient& c) {
        return c.finalize_upload("up", {{"qh", "tx"}}).sha256;
    });
}

TEST_CASE("grpc finalize_merkle_upload reads sha256, and none when empty") {
    check_upload_sha([](antd::GrpcClient& c) {
        return c.finalize_merkle_upload("up", "pool").sha256;
    });
}

TEST_CASE("grpc build_manifest sets sha256 only on an entry that gives one") {
    Fixture f;
    (void)f.client().build_manifest({
        {.path = "a.txt", .address = "11", .sha256 = kSha2},
        {.path = "b.txt", .address = "22"},
        {.path = "c.txt", .address = "33", .sha256 = std::string{}},
        // Passed through as given: no case folding, no validation.
        {.path = "d.txt", .address = "44", .sha256 = "ABCDEF"},
    });
    const auto req = f.last_build();
    REQUIRE(req.entries_size() == 4);
    CHECK(req.entries(0).has_sha256());
    CHECK(req.entries(0).sha256() == kSha2);
    CHECK_FALSE(req.entries(1).has_sha256());
    CHECK_FALSE(req.entries(2).has_sha256());
    CHECK(req.entries(3).has_sha256());
    CHECK(req.entries(3).sha256() == "ABCDEF");
}

TEST_CASE("grpc ManifestEntryInfo reads sha256 from build and decode, and none when empty") {
    Fixture f;
    const std::vector<antd::ManifestEntryInput> in = {{.path = "a.txt", .address = "11"}};

    f.set_sha(kSha);
    CHECK(f.client().build_manifest(in).entries.at(0).sha256 == std::optional<std::string>(kSha));
    CHECK(f.client().decode_manifest_link("ant://manifest/x").entries.at(0).sha256 ==
          std::optional<std::string>(kSha));
    CHECK(f.client().decode_manifest({0xC1, 'A', 'N', 'T', 0x01}).entries.at(0).sha256 ==
          std::optional<std::string>(kSha));

    f.set_sha("");
    CHECK_FALSE(f.client().build_manifest(in).entries.at(0).sha256.has_value());
    CHECK_FALSE(f.client().decode_manifest_link("ant://manifest/x").entries.at(0).sha256.has_value());
}

TEST_CASE("grpc INVALID_ARGUMENT for a bad sha256 is a BadRequestError that keeps the message") {
    Fixture f;
    try {
        (void)f.client().build_manifest({{.path = "a.txt", .address = "11", .sha256 = "zz"}});
        FAIL("expected BadRequestError");
    } catch (const antd::BadRequestError& e) {
        CHECK(e.status_code == 400);
        CHECK(std::string(e.what()).find("entries[0]: invalid hex sha256") != std::string::npos);
    }
    // The hash was sent as given, not checked client-side.
    CHECK(f.last_build().entries(0).sha256() == "zz");
}
