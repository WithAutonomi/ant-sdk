#include "antd/grpc_client.hpp"

#include <grpcpp/grpcpp.h>

// Proto-generated headers — produced by protoc + grpc_cpp_plugin.
// Run `protoc` against antd/proto/antd/v1/*.proto or let the CMake
// antd_grpc target handle compilation automatically.
#include "antd/v1/health.grpc.pb.h"
#include "antd/v1/data.grpc.pb.h"
#include "antd/v1/chunks.grpc.pb.h"
#include "antd/v1/graph.grpc.pb.h"
#include "antd/v1/files.grpc.pb.h"

namespace antd {

// ---------------------------------------------------------------------------
// Helper: translate gRPC status to AntdError
// ---------------------------------------------------------------------------

static void check_status(const grpc::Status& status) {
    if (status.ok()) {
        return;
    }
    switch (status.error_code()) {
        case grpc::StatusCode::INVALID_ARGUMENT:
            throw BadRequestError(status.error_message());
        case grpc::StatusCode::NOT_FOUND:
            throw NotFoundError(status.error_message());
        case grpc::StatusCode::ALREADY_EXISTS:
            throw AlreadyExistsError(status.error_message());
        case grpc::StatusCode::RESOURCE_EXHAUSTED:
            throw TooLargeError(status.error_message());
        case grpc::StatusCode::INTERNAL:
            throw InternalError(status.error_message());
        case grpc::StatusCode::UNAVAILABLE:
            throw NetworkError(status.error_message());
        case grpc::StatusCode::FAILED_PRECONDITION:
            throw PaymentError(status.error_message());
        default:
            throw AntdError(static_cast<int>(status.error_code()),
                            status.error_message());
    }
}

// ---------------------------------------------------------------------------
// Impl (pimpl hides gRPC stubs from the public header)
// ---------------------------------------------------------------------------

struct GrpcClient::Impl {
    std::shared_ptr<grpc::Channel> channel;
    std::unique_ptr<antd::v1::HealthService::Stub> health_stub;
    std::unique_ptr<antd::v1::DataService::Stub> data_stub;
    std::unique_ptr<antd::v1::ChunkService::Stub> chunk_stub;
    std::unique_ptr<antd::v1::GraphService::Stub> graph_stub;
    std::unique_ptr<antd::v1::FileService::Stub> file_stub;

    explicit Impl(const std::string& target)
        : channel(grpc::CreateChannel(target, grpc::InsecureChannelCredentials())),
          health_stub(antd::v1::HealthService::NewStub(channel)),
          data_stub(antd::v1::DataService::NewStub(channel)),
          chunk_stub(antd::v1::ChunkService::NewStub(channel)),
          graph_stub(antd::v1::GraphService::NewStub(channel)),
          file_stub(antd::v1::FileService::NewStub(channel)) {}
};

// ---------------------------------------------------------------------------
// GrpcClient lifetime
// ---------------------------------------------------------------------------

GrpcClient::GrpcClient(const std::string& target)
    : impl_(std::make_unique<Impl>(target)) {}

GrpcClient::~GrpcClient() = default;
GrpcClient::GrpcClient(GrpcClient&&) noexcept = default;
GrpcClient& GrpcClient::operator=(GrpcClient&&) noexcept = default;

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

HealthStatus GrpcClient::health() {
    grpc::ClientContext ctx;
    antd::v1::HealthCheckRequest req;
    antd::v1::HealthCheckResponse resp;
    check_status(impl_->health_stub->Check(&ctx, req, &resp));
    return HealthStatus{
        .ok = resp.status() == "ok",
        .network = resp.network(),
        .version = resp.version(),
        .evm_network = resp.evm_network(),
        .uptime_seconds = resp.uptime_seconds(),
        .build_commit = resp.build_commit(),
        .payment_token_address = resp.payment_token_address(),
        .payment_vault_address = resp.payment_vault_address(),
    };
}

// ---------------------------------------------------------------------------
// Data (Immutable)
// ---------------------------------------------------------------------------

PutResult GrpcClient::data_put_public(const std::vector<uint8_t>& data) {
    grpc::ClientContext ctx;
    antd::v1::PutPublicDataRequest req;
    req.set_data(data.data(), data.size());
    antd::v1::PutPublicDataResponse resp;
    check_status(impl_->data_stub->PutPublic(&ctx, req, &resp));
    return PutResult{
        .cost = resp.cost().atto_tokens(),
        .address = resp.address(),
    };
}

std::vector<uint8_t> GrpcClient::data_get_public(std::string_view address) {
    grpc::ClientContext ctx;
    antd::v1::GetPublicDataRequest req;
    req.set_address(std::string(address));
    antd::v1::GetPublicDataResponse resp;
    check_status(impl_->data_stub->GetPublic(&ctx, req, &resp));
    const auto& d = resp.data();
    return std::vector<uint8_t>(d.begin(), d.end());
}

PutResult GrpcClient::data_put_private(const std::vector<uint8_t>& data) {
    grpc::ClientContext ctx;
    antd::v1::PutPrivateDataRequest req;
    req.set_data(data.data(), data.size());
    antd::v1::PutPrivateDataResponse resp;
    check_status(impl_->data_stub->PutPrivate(&ctx, req, &resp));
    return PutResult{
        .cost = resp.cost().atto_tokens(),
        .address = resp.data_map(),
    };
}

std::vector<uint8_t> GrpcClient::data_get_private(std::string_view data_map) {
    grpc::ClientContext ctx;
    antd::v1::GetPrivateDataRequest req;
    req.set_data_map(std::string(data_map));
    antd::v1::GetPrivateDataResponse resp;
    check_status(impl_->data_stub->GetPrivate(&ctx, req, &resp));
    const auto& d = resp.data();
    return std::vector<uint8_t>(d.begin(), d.end());
}

std::string GrpcClient::data_cost(const std::vector<uint8_t>& data) {
    grpc::ClientContext ctx;
    antd::v1::DataCostRequest req;
    req.set_data(data.data(), data.size());
    antd::v1::Cost resp;
    check_status(impl_->data_stub->GetCost(&ctx, req, &resp));
    return resp.atto_tokens();
}

// ---------------------------------------------------------------------------
// Chunks
// ---------------------------------------------------------------------------

PutResult GrpcClient::chunk_put(const std::vector<uint8_t>& data) {
    grpc::ClientContext ctx;
    antd::v1::PutChunkRequest req;
    req.set_data(data.data(), data.size());
    antd::v1::PutChunkResponse resp;
    check_status(impl_->chunk_stub->Put(&ctx, req, &resp));
    return PutResult{
        .cost = resp.cost().atto_tokens(),
        .address = resp.address(),
    };
}

std::vector<uint8_t> GrpcClient::chunk_get(std::string_view address) {
    grpc::ClientContext ctx;
    antd::v1::GetChunkRequest req;
    req.set_address(std::string(address));
    antd::v1::GetChunkResponse resp;
    check_status(impl_->chunk_stub->Get(&ctx, req, &resp));
    const auto& d = resp.data();
    return std::vector<uint8_t>(d.begin(), d.end());
}

// ---------------------------------------------------------------------------
// Files & Directories
// ---------------------------------------------------------------------------

FileUploadResult GrpcClient::file_upload_public(std::string_view path) {
    grpc::ClientContext ctx;
    antd::v1::UploadFileRequest req;
    req.set_path(std::string(path));
    antd::v1::UploadPublicResponse resp;
    check_status(impl_->file_stub->UploadPublic(&ctx, req, &resp));
    return FileUploadResult{
        .address = resp.address(),
        .storage_cost_atto = resp.storage_cost_atto(),
        .gas_cost_wei = resp.gas_cost_wei(),
        .chunks_stored = resp.chunks_stored(),
        .payment_mode_used = resp.payment_mode_used(),
    };
}

void GrpcClient::file_download_public(std::string_view address,
                                       std::string_view dest_path) {
    grpc::ClientContext ctx;
    antd::v1::DownloadPublicRequest req;
    req.set_address(std::string(address));
    req.set_dest_path(std::string(dest_path));
    antd::v1::DownloadResponse resp;
    check_status(impl_->file_stub->DownloadPublic(&ctx, req, &resp));
}

FileUploadResult GrpcClient::dir_upload_public(std::string_view path) {
    grpc::ClientContext ctx;
    antd::v1::UploadFileRequest req;
    req.set_path(std::string(path));
    antd::v1::UploadPublicResponse resp;
    check_status(impl_->file_stub->DirUploadPublic(&ctx, req, &resp));
    return FileUploadResult{
        .address = resp.address(),
        .storage_cost_atto = resp.storage_cost_atto(),
        .gas_cost_wei = resp.gas_cost_wei(),
        .chunks_stored = resp.chunks_stored(),
        .payment_mode_used = resp.payment_mode_used(),
    };
}

void GrpcClient::dir_download_public(std::string_view address,
                                      std::string_view dest_path) {
    grpc::ClientContext ctx;
    antd::v1::DownloadPublicRequest req;
    req.set_address(std::string(address));
    req.set_dest_path(std::string(dest_path));
    antd::v1::DownloadResponse resp;
    check_status(impl_->file_stub->DirDownloadPublic(&ctx, req, &resp));
}

std::string GrpcClient::file_cost(std::string_view path, bool is_public) {
    grpc::ClientContext ctx;
    antd::v1::FileCostRequest req;
    req.set_path(std::string(path));
    req.set_is_public(is_public);
    antd::v1::Cost resp;
    check_status(impl_->file_stub->GetFileCost(&ctx, req, &resp));
    return resp.atto_tokens();
}

}  // namespace antd
