// ---------------------------------------------------------------------------
// ManifestService wire-mapping tests for antd::GrpcClient.
//
// Spins up a real grpc++ server bound to `127.0.0.1:0` with a mock
// ManifestService, then dials it with a real `antd::GrpcClient`. Covers the
// Build and Decode request and response mapping (raw `.ant` bytes, proto3
// `optional` presence for unset sizes and paths, the `embed_roots` default),
// the both-or-neither entry check made before any RPC, INVALID_ARGUMENT as
// BadRequestError, and the raised message limits: a 5 MiB manifest goes both
// ways through the client, where gRPC's default 4 MiB receive limit refuses
// it.
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

#include "antd/v1/manifests.grpc.pb.h"
#include "manifests_grpc.hpp"

#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace {

namespace v1 = antd::v1;

/// The five-byte `.ant` header.
const std::vector<uint8_t> kHeader = {0xC1, 'A', 'N', 'T', 0x01};

/// Past gRPC's 4 MiB default receive limit.
constexpr std::size_t kBig = 5 * 1024 * 1024;

std::string as_string(const std::vector<uint8_t>& v) { return {v.begin(), v.end()}; }

class MockManifestService final : public v1::ManifestService::Service {
public:
    std::mutex mu;
    int calls{0};
    v1::BuildManifestRequest last_build;
    v1::DecodeManifestRequest last_decode;

    grpc::Status Build(grpc::ServerContext*, const v1::BuildManifestRequest* req,
                       v1::BuildManifestResponse* resp) override {
        {
            std::lock_guard<std::mutex> lock(mu);
            ++calls;
            last_build = *req;
        }
        for (int i = 0; i < req->entries_size(); ++i) {
            if (req->entries(i).path() == "../x") {
                return grpc::Status(grpc::StatusCode::INVALID_ARGUMENT,
                                    "Bad request: entries[" + std::to_string(i) +
                                        "]: invalid path \"../x\"");
            }
        }
        if (req->name() == "big") {
            resp->set_manifest(std::string(kBig, '\x5a'));
            return grpc::Status::OK;
        }
        resp->set_manifest(as_string(kHeader));
        resp->set_link("ant://manifest/wUFOVAE");
        auto* a = resp->add_entries();
        a->set_effective_name("a.txt");
        a->set_path("a.txt");
        a->set_size(10);
        a->set_kind("embedded");
        a->set_content_address("cc");
        a->set_exact_size(10);
        auto* p = resp->add_entries();
        p->set_effective_name("11");
        p->set_kind("public");
        p->set_content_address("11");
        auto* z = resp->add_entries();
        z->set_effective_name("zero");
        z->set_path("zero");
        z->set_size(0);
        z->set_kind("public");
        z->set_content_address("22");
        z->set_exact_size(0);
        return grpc::Status::OK;
    }

    grpc::Status Decode(grpc::ServerContext*, const v1::DecodeManifestRequest* req,
                        v1::DecodeManifestResponse* resp) override {
        {
            std::lock_guard<std::mutex> lock(mu);
            ++calls;
            last_decode = *req;
        }
        resp->set_source("manifest");
        switch (req->input_case()) {
            case v1::DecodeManifestRequest::kManifest:
                if (req->manifest() == "nope") {
                    return grpc::Status(grpc::StatusCode::INVALID_ARGUMENT,
                                        "Bad request: not a manifest: missing or invalid header");
                }
                resp->set_name(req->manifest().size() > 4 * 1024 * 1024 ? "big" : "bytes");
                {
                    auto* e = resp->add_entries();
                    e->set_effective_name("a.txt");
                    e->set_path("a.txt");
                    e->set_kind("embedded");
                    e->set_content_address("cc");
                    e->set_data_map("abcd");
                    e->set_exact_size(3);
                    auto* f = resp->add_entries();
                    f->set_effective_name("b");
                    f->set_path("b");
                    f->set_kind("public");
                    f->set_content_address("dd");
                    f->set_error("Record not found: gone");
                }
                break;
            case v1::DecodeManifestRequest::kLink: {
                resp->set_source("file_link");
                auto* e = resp->add_entries();
                e->set_effective_name(req->link());
                e->set_kind("public");
                e->set_content_address(req->link());
                break;
            }
            default:
                return grpc::Status(grpc::StatusCode::INVALID_ARGUMENT,
                                    "needs a manifest (.ant bytes) or a link");
        }
        if (req->resolve()) resp->set_torrent_info_hash_v1("resolved");
        return grpc::Status::OK;
    }
};

class ManifestFixture {
public:
    ManifestFixture() {
        grpc::ServerBuilder builder;
        builder.AddListeningPort("127.0.0.1:0", grpc::InsecureServerCredentials(), &port_);
        // As the daemon does: accept a large Decode request.
        builder.SetMaxReceiveMessageSize(64 * 1024 * 1024);
        builder.SetMaxSendMessageSize(64 * 1024 * 1024);
        builder.RegisterService(&service_);
        server_ = builder.BuildAndStart();
        REQUIRE(server_ != nullptr);
        REQUIRE(port_ != 0);
        client_ = std::make_unique<antd::GrpcClient>(target());
    }
    ~ManifestFixture() {
        if (server_) server_->Shutdown();
    }
    std::string target() const { return "127.0.0.1:" + std::to_string(port_); }
    antd::GrpcClient& client() { return *client_; }
    MockManifestService& service() { return service_; }
    int calls() {
        std::lock_guard<std::mutex> lock(service_.mu);
        return service_.calls;
    }
    v1::BuildManifestRequest last_build() {
        std::lock_guard<std::mutex> lock(service_.mu);
        return service_.last_build;
    }
    v1::DecodeManifestRequest last_decode() {
        std::lock_guard<std::mutex> lock(service_.mu);
        return service_.last_decode;
    }

private:
    int port_{0};
    MockManifestService service_;
    std::unique_ptr<grpc::Server> server_;
    std::unique_ptr<antd::GrpcClient> client_;
};

}  // namespace

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------

TEST_CASE("grpc build_manifest maps entries and options") {
    ManifestFixture f;
    antd::BuildManifestOptions opts;
    opts.name = "album";
    opts.torrent_info_hashes = {std::string(40, 'a')};
    const auto res = f.client().build_manifest(
        {
            {.path = "a.txt", .size = 10, .data_map = "abcd"},
            {.address = "11"},
        },
        opts);

    const auto req = f.last_build();
    CHECK(req.has_name());
    CHECK(req.name() == "album");
    REQUIRE(req.torrent_info_hashes_size() == 1);
    CHECK(req.torrent_info_hashes(0) == std::string(40, 'a'));
    // The default embeds roots, and it is sent rather than left to the daemon.
    CHECK(req.has_embed_roots());
    CHECK(req.embed_roots());
    REQUIRE(req.entries_size() == 2);
    const auto& first = req.entries(0);
    CHECK(first.has_path());
    CHECK(first.path() == "a.txt");
    CHECK(first.has_size());
    CHECK(first.size() == 10);
    CHECK(first.source_case() == v1::ManifestEntryInput::kDataMap);
    CHECK(first.data_map() == "abcd");
    const auto& second = req.entries(1);
    CHECK_FALSE(second.has_path());
    CHECK_FALSE(second.has_size());
    CHECK(second.source_case() == v1::ManifestEntryInput::kAddress);
    CHECK(second.address() == "11");

    CHECK(res.manifest == kHeader);
    CHECK(res.link == "ant://manifest/wUFOVAE");
    REQUIRE(res.entries.size() == 3);
    CHECK(res.entries[0].path == std::optional<std::string>("a.txt"));
    CHECK(res.entries[0].size == std::optional<std::uint64_t>(10));
    CHECK(res.entries[0].exact_size == std::optional<std::uint64_t>(10));
    CHECK(res.entries[0].kind == "embedded");
    // Unset optionals read as nullopt; a present 0 reads as 0.
    CHECK_FALSE(res.entries[1].path.has_value());
    CHECK_FALSE(res.entries[1].size.has_value());
    CHECK_FALSE(res.entries[1].exact_size.has_value());
    CHECK(res.entries[1].effective_name == "11");
    CHECK(res.entries[2].size == std::optional<std::uint64_t>(0));
    CHECK(res.entries[2].exact_size == std::optional<std::uint64_t>(0));
}

TEST_CASE("grpc build_manifest: defaults, keep_shrunk_data_maps and an explicit size 0") {
    ManifestFixture f;
    (void)f.client().build_manifest({{.size = 0, .address = "11"}});
    auto req = f.last_build();
    CHECK_FALSE(req.has_name());
    CHECK(req.torrent_info_hashes_size() == 0);
    CHECK(req.has_embed_roots());
    CHECK(req.embed_roots());
    REQUIRE(req.entries_size() == 1);
    CHECK(req.entries(0).has_size());
    CHECK(req.entries(0).size() == 0);

    antd::BuildManifestOptions keep;
    keep.keep_shrunk_data_maps = true;
    (void)f.client().build_manifest({{.address = "11"}}, keep);
    req = f.last_build();
    CHECK(req.has_embed_roots());
    CHECK_FALSE(req.embed_roots());
}

TEST_CASE("grpc build_manifest refuses an ambiguous entry before any RPC") {
    ManifestFixture f;
    CHECK_THROWS_AS(f.client().build_manifest({{.data_map = "aa", .address = "bb"}}),
                    antd::BadRequestError);
    CHECK_THROWS_AS(f.client().build_manifest({{.address = "11"}, {.path = "x"}}),
                    antd::BadRequestError);
    CHECK(f.calls() == 0);
}

// ---------------------------------------------------------------------------
// Decode
// ---------------------------------------------------------------------------

TEST_CASE("grpc decode_manifest sends raw bytes") {
    ManifestFixture f;
    const auto res = f.client().decode_manifest(kHeader, true);

    const auto req = f.last_decode();
    CHECK(req.input_case() == v1::DecodeManifestRequest::kManifest);
    CHECK(req.manifest() == as_string(kHeader));
    CHECK(req.resolve());

    CHECK(res.source == "manifest");
    CHECK(res.name == std::optional<std::string>("bytes"));
    CHECK(res.torrent_info_hash_v1 == "resolved");
    CHECK(res.torrent_info_hash_v2.empty());
    REQUIRE(res.entries.size() == 2);
    CHECK(res.entries[0].data_map == "abcd");
    CHECK(res.entries[0].exact_size == std::optional<std::uint64_t>(3));
    CHECK_FALSE(res.entries[0].size.has_value());
    CHECK(res.entries[1].error == "Record not found: gone");
    CHECK_FALSE(res.entries[1].exact_size.has_value());
}

TEST_CASE("grpc decode_manifest_link sends the link") {
    ManifestFixture f;
    const std::string addr(64, '4');
    const auto res = f.client().decode_manifest_link(addr);

    const auto req = f.last_decode();
    CHECK(req.input_case() == v1::DecodeManifestRequest::kLink);
    CHECK(req.link() == addr);
    CHECK_FALSE(req.resolve());

    CHECK(res.source == "file_link");
    CHECK_FALSE(res.name.has_value());
    CHECK(res.torrent_info_hash_v1.empty());
    REQUIRE(res.entries.size() == 1);
    CHECK(res.entries[0].content_address == addr);
    CHECK_FALSE(res.entries[0].path.has_value());
}

TEST_CASE("grpc decode refuses empty input before any RPC") {
    ManifestFixture f;
    CHECK_THROWS_AS(f.client().decode_manifest({}), antd::BadRequestError);
    CHECK_THROWS_AS(f.client().decode_manifest_link(""), antd::BadRequestError);
    CHECK(f.calls() == 0);
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

TEST_CASE("grpc INVALID_ARGUMENT is a BadRequestError that keeps the message") {
    ManifestFixture f;
    try {
        (void)f.client().build_manifest({{.path = "../x", .address = "11"}});
        FAIL("expected BadRequestError");
    } catch (const antd::BadRequestError& e) {
        CHECK(std::string(e.what()).find("entries[0]: invalid path") != std::string::npos);
    }
    CHECK_THROWS_AS(f.client().decode_manifest(std::vector<uint8_t>{'n', 'o', 'p', 'e'}),
                    antd::BadRequestError);
}

// ---------------------------------------------------------------------------
// Message limits
// ---------------------------------------------------------------------------

TEST_CASE("the manifest channel arguments raise both message limits") {
    const auto args = antd::detail::manifest_channel_arguments();
    const grpc_channel_args c = args.c_channel_args();
    std::optional<int> recv;
    std::optional<int> send;
    for (std::size_t i = 0; i < c.num_args; ++i) {
        const grpc_arg& a = c.args[i];
        if (a.type != GRPC_ARG_INTEGER) continue;
        if (std::strcmp(a.key, GRPC_ARG_MAX_RECEIVE_MESSAGE_LENGTH) == 0) recv = a.value.integer;
        if (std::strcmp(a.key, GRPC_ARG_MAX_SEND_MESSAGE_LENGTH) == 0) send = a.value.integer;
    }
    CHECK(antd::detail::kMaxManifestGrpcMessageBytes == 256 * 1024 * 1024);
    CHECK(recv == std::optional<int>(antd::detail::kMaxManifestGrpcMessageBytes));
    CHECK(send == std::optional<int>(antd::detail::kMaxManifestGrpcMessageBytes));
}

TEST_CASE("a manifest past 4 MiB goes both ways through the client") {
    ManifestFixture f;

    // The control: on a channel with gRPC's defaults, the same Build
    // response is refused, so the client's success below is the raised limit.
    {
        auto stub = v1::ManifestService::NewStub(
            grpc::CreateChannel(f.target(), grpc::InsecureChannelCredentials()));
        grpc::ClientContext ctx;
        v1::BuildManifestRequest req;
        req.set_name("big");
        req.add_entries()->set_address("11");
        v1::BuildManifestResponse resp;
        const auto status = stub->Build(&ctx, req, &resp);
        CHECK(status.error_code() == grpc::StatusCode::RESOURCE_EXHAUSTED);
    }

    antd::BuildManifestOptions opts;
    opts.name = "big";
    const auto built = f.client().build_manifest({{.address = "11"}}, opts);
    CHECK(built.manifest.size() == kBig);

    const auto decoded = f.client().decode_manifest(built.manifest);
    CHECK(decoded.name == std::optional<std::string>("big"));
    CHECK(f.last_decode().manifest().size() == kBig);
}
