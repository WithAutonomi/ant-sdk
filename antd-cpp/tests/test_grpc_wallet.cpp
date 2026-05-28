// ---------------------------------------------------------------------------
// V2-286 WalletService wire-mapping tests for antd::GrpcClient.
//
// Spins up a real grpc++ server bound to `127.0.0.1:0` with a mock
// WalletService implementation, then dials with a real `antd::GrpcClient`.
// Mirrors the antd-rust / antd-go / antd-py / antd-java / antd-kotlin /
// antd-csharp / antd-ruby / antd-dart / antd-swift suites.
//
// Compiled only when `-DANTD_BUILD_GRPC=ON` is passed to CMake, alongside the
// `antd_grpc` library and its generated proto stubs.
// ---------------------------------------------------------------------------

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "antd/grpc_client.hpp"
#include "antd/errors.hpp"

#include <grpcpp/grpcpp.h>
#include <grpcpp/server.h>
#include <grpcpp/server_builder.h>

#include "antd/v1/wallet.grpc.pb.h"

#include <memory>
#include <string>

namespace {

// --- Mock services ----------------------------------------------------------

class MockWalletService final : public antd::v1::WalletService::Service {
public:
    grpc::Status GetAddress(grpc::ServerContext*,
                            const antd::v1::GetWalletAddressRequest*,
                            antd::v1::GetWalletAddressResponse* resp) override {
        resp->set_address("0xabc1234567890abcdef1234567890abcdef123456");
        return grpc::Status::OK;
    }

    grpc::Status GetBalance(grpc::ServerContext*,
                            const antd::v1::GetWalletBalanceRequest*,
                            antd::v1::GetWalletBalanceResponse* resp) override {
        resp->set_balance("1000000000000000000");
        resp->set_gas_balance("500000000000000000");
        return grpc::Status::OK;
    }

    grpc::Status Approve(grpc::ServerContext*,
                         const antd::v1::WalletApproveRequest*,
                         antd::v1::WalletApproveResponse* resp) override {
        resp->set_approved(true);
        return grpc::Status::OK;
    }
};

class UnconfiguredWalletService final : public antd::v1::WalletService::Service {
public:
    grpc::Status GetAddress(grpc::ServerContext*,
                            const antd::v1::GetWalletAddressRequest*,
                            antd::v1::GetWalletAddressResponse*) override {
        return grpc::Status(grpc::StatusCode::FAILED_PRECONDITION,
                            "wallet not configured — set AUTONOMI_WALLET_KEY");
    }

    grpc::Status GetBalance(grpc::ServerContext*,
                            const antd::v1::GetWalletBalanceRequest*,
                            antd::v1::GetWalletBalanceResponse*) override {
        return grpc::Status(grpc::StatusCode::FAILED_PRECONDITION,
                            "wallet not configured — set AUTONOMI_WALLET_KEY");
    }

    grpc::Status Approve(grpc::ServerContext*,
                         const antd::v1::WalletApproveRequest*,
                         antd::v1::WalletApproveResponse*) override {
        return grpc::Status(grpc::StatusCode::FAILED_PRECONDITION,
                            "wallet not configured — set AUTONOMI_WALLET_KEY");
    }
};

template <typename Service>
class Fixture {
public:
    Fixture() {
        grpc::ServerBuilder builder;
        int selected_port = 0;
        builder.AddListeningPort("127.0.0.1:0",
                                 grpc::InsecureServerCredentials(),
                                 &selected_port);
        builder.RegisterService(&service_);
        server_ = builder.BuildAndStart();
        REQUIRE(server_ != nullptr);
        REQUIRE(selected_port != 0);
        client_ = std::make_unique<antd::GrpcClient>(
            "127.0.0.1:" + std::to_string(selected_port));
    }
    ~Fixture() {
        if (server_) server_->Shutdown();
    }
    antd::GrpcClient& client() { return *client_; }

private:
    Service service_;
    std::unique_ptr<grpc::Server> server_;
    std::unique_ptr<antd::GrpcClient> client_;
};

}  // namespace

TEST_CASE("V2-286: wallet_address returns address") {
    Fixture<MockWalletService> f;
    auto r = f.client().wallet_address();
    CHECK(r.address == "0xabc1234567890abcdef1234567890abcdef123456");
}

TEST_CASE("V2-286: wallet_balance returns balances") {
    Fixture<MockWalletService> f;
    auto r = f.client().wallet_balance();
    CHECK(r.balance == "1000000000000000000");
    CHECK(r.gas_balance == "500000000000000000");
}

TEST_CASE("V2-286: wallet_approve returns true") {
    Fixture<MockWalletService> f;
    CHECK(f.client().wallet_approve());
}

TEST_CASE("V2-286: wallet_address unconfigured throws PaymentError") {
    Fixture<UnconfiguredWalletService> f;
    try {
        (void)f.client().wallet_address();
        FAIL("expected antd::PaymentError");
    } catch (const antd::PaymentError& e) {
        CHECK(std::string(e.what()).find("wallet not configured") != std::string::npos);
    } catch (const std::exception& e) {
        FAIL("expected PaymentError, got: " << e.what());
    }
}
