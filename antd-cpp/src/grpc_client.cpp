#include "antd/grpc_client.hpp"

#include <grpcpp/grpcpp.h>

// Proto-generated headers — produced by protoc + grpc_cpp_plugin.
// Run `protoc` against antd/proto/antd/v1/*.proto or let the CMake
// antd_grpc target handle compilation automatically.
#include "antd/v1/health.grpc.pb.h"
#include "antd/v1/data.grpc.pb.h"
#include "antd/v1/chunks.grpc.pb.h"
#include "antd/v1/files.grpc.pb.h"
#include "antd/v1/upload.grpc.pb.h"

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
    std::unique_ptr<antd::v1::FileService::Stub> file_stub;
    std::unique_ptr<antd::v1::UploadService::Stub> upload_stub;

    explicit Impl(const std::string& target)
        : channel(grpc::CreateChannel(target, grpc::InsecureChannelCredentials())),
          health_stub(antd::v1::HealthService::NewStub(channel)),
          data_stub(antd::v1::DataService::NewStub(channel)),
          chunk_stub(antd::v1::ChunkService::NewStub(channel)),
          file_stub(antd::v1::FileService::NewStub(channel)),
          upload_stub(antd::v1::UploadService::NewStub(channel)) {}
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

DataPutPublicResult GrpcClient::data_put_public(const std::vector<uint8_t>& data,
                                                PaymentMode payment_mode) {
    grpc::ClientContext ctx;
    antd::v1::PutPublicDataRequest req;
    req.set_data(data.data(), data.size());
    req.set_payment_mode(payment_mode_wire(payment_mode));
    antd::v1::PutPublicDataResponse resp;
    check_status(impl_->data_stub->PutPublic(&ctx, req, &resp));
    return DataPutPublicResult{
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

DataPutResult GrpcClient::data_put(const std::vector<uint8_t>& data,
                                   PaymentMode payment_mode) {
    grpc::ClientContext ctx;
    antd::v1::PutDataRequest req;
    req.set_data(data.data(), data.size());
    req.set_payment_mode(payment_mode_wire(payment_mode));
    antd::v1::PutDataResponse resp;
    check_status(impl_->data_stub->Put(&ctx, req, &resp));
    return DataPutResult{
        .data_map = resp.data_map(),
    };
}

std::vector<uint8_t> GrpcClient::data_get(std::string_view data_map) {
    grpc::ClientContext ctx;
    antd::v1::GetDataRequest req;
    req.set_data_map(std::string(data_map));
    antd::v1::GetDataResponse resp;
    check_status(impl_->data_stub->Get(&ctx, req, &resp));
    const auto& d = resp.data();
    return std::vector<uint8_t>(d.begin(), d.end());
}

UploadCostEstimate GrpcClient::data_cost(const std::vector<uint8_t>& data,
                                         PaymentMode payment_mode) {
    grpc::ClientContext ctx;
    antd::v1::DataCostRequest req;
    req.set_data(data.data(), data.size());
    req.set_payment_mode(payment_mode_wire(payment_mode));
    antd::v1::Cost resp;
    check_status(impl_->data_stub->Cost(&ctx, req, &resp));
    return UploadCostEstimate{
        resp.atto_tokens(),
        resp.file_size(),
        resp.chunk_count(),
        resp.estimated_gas_cost_wei(),
        resp.payment_mode(),
    };
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

FilePutResult GrpcClient::file_put(std::string_view path, PaymentMode payment_mode) {
    grpc::ClientContext ctx;
    antd::v1::PutFileRequest req;
    req.set_path(std::string(path));
    req.set_payment_mode(payment_mode_wire(payment_mode));
    antd::v1::PutFileResponse resp;
    check_status(impl_->file_stub->Put(&ctx, req, &resp));
    return FilePutResult{
        .data_map = resp.data_map(),
        .storage_cost_atto = resp.storage_cost_atto(),
        .gas_cost_wei = resp.gas_cost_wei(),
        .chunks_stored = resp.chunks_stored(),
        .payment_mode_used = resp.payment_mode_used(),
    };
}

void GrpcClient::file_get(std::string_view data_map, std::string_view dest_path) {
    grpc::ClientContext ctx;
    antd::v1::GetFileRequest req;
    req.set_data_map(std::string(data_map));
    req.set_dest_path(std::string(dest_path));
    antd::v1::GetFileResponse resp;
    check_status(impl_->file_stub->Get(&ctx, req, &resp));
}

FilePutPublicResult GrpcClient::file_put_public(std::string_view path,
                                                PaymentMode payment_mode) {
    grpc::ClientContext ctx;
    antd::v1::PutFileRequest req;
    req.set_path(std::string(path));
    req.set_payment_mode(payment_mode_wire(payment_mode));
    antd::v1::PutFilePublicResponse resp;
    check_status(impl_->file_stub->PutPublic(&ctx, req, &resp));
    return FilePutPublicResult{
        .address = resp.address(),
        .storage_cost_atto = resp.storage_cost_atto(),
        .gas_cost_wei = resp.gas_cost_wei(),
        .chunks_stored = resp.chunks_stored(),
        .payment_mode_used = resp.payment_mode_used(),
    };
}

void GrpcClient::file_get_public(std::string_view address,
                                  std::string_view dest_path) {
    grpc::ClientContext ctx;
    antd::v1::GetFilePublicRequest req;
    req.set_address(std::string(address));
    req.set_dest_path(std::string(dest_path));
    antd::v1::GetFileResponse resp;
    check_status(impl_->file_stub->GetPublic(&ctx, req, &resp));
}

UploadCostEstimate GrpcClient::file_cost(std::string_view path,
                                          bool is_public,
                                          PaymentMode payment_mode) {
    grpc::ClientContext ctx;
    antd::v1::FileCostRequest req;
    req.set_path(std::string(path));
    req.set_is_public(is_public);
    req.set_payment_mode(payment_mode_wire(payment_mode));
    antd::v1::Cost resp;
    check_status(impl_->file_stub->Cost(&ctx, req, &resp));
    return UploadCostEstimate{
        resp.atto_tokens(),
        resp.file_size(),
        resp.chunk_count(),
        resp.estimated_gas_cost_wei(),
        resp.payment_mode(),
    };
}

// ---------------------------------------------------------------------------
// External signer (two-phase upload)
// ---------------------------------------------------------------------------

namespace {

// Merkle-only fields (`depth`, `pool_commitments`, `merkle_payment_timestamp`)
// are gated on `payment_type == "merkle"`. proto3 scalar defaults are not
// enough — REST omits these fields entirely on wave-batch, and the model
// layer expects them to be empty / zero there.
PrepareUploadResult map_prepare_upload_response(const antd::v1::PrepareUploadResponse& resp) {
    PrepareUploadResult r;
    r.upload_id = resp.upload_id();
    r.payment_type = resp.payment_type().empty() ? "wave_batch" : resp.payment_type();
    r.total_amount = resp.total_amount();
    r.payment_vault_address = resp.payment_vault_address();
    r.payment_token_address = resp.payment_token_address();
    r.rpc_url = resp.rpc_url();

    for (const auto& p : resp.payments()) {
        r.payments.push_back(PaymentInfo{
            .quote_hash = p.quote_hash(),
            .rewards_address = p.rewards_address(),
            .amount = p.amount(),
        });
    }

    if (resp.payment_type() == "merkle") {
        r.depth = static_cast<int>(resp.depth());
        r.merkle_payment_timestamp = resp.merkle_payment_timestamp();
        for (const auto& pc : resp.pool_commitments()) {
            PoolCommitmentEntry entry;
            entry.pool_hash = pc.pool_hash();
            for (const auto& c : pc.candidates()) {
                entry.candidates.push_back(CandidateNodeEntry{
                    .rewards_address = c.rewards_address(),
                    .amount = c.amount(),
                });
            }
            r.pool_commitments.push_back(std::move(entry));
        }
    }
    return r;
}

FinalizeUploadResult map_finalize_upload_response(const antd::v1::FinalizeUploadResponse& resp) {
    return FinalizeUploadResult{
        .data_map = resp.data_map(),
        .address = resp.address(),
        .data_map_address = resp.data_map_address(),
        .chunks_stored = static_cast<int64_t>(resp.chunks_stored()),
    };
}

}  // namespace

PrepareUploadResult GrpcClient::prepare_upload(std::string_view path,
                                               std::optional<std::string> visibility) {
    grpc::ClientContext ctx;
    antd::v1::PrepareFileUploadRequest req;
    req.set_path(std::string(path));
    if (visibility) {
        req.set_visibility(*visibility);
    }
    antd::v1::PrepareUploadResponse resp;
    check_status(impl_->upload_stub->PrepareFileUpload(&ctx, req, &resp));
    return map_prepare_upload_response(resp);
}

PrepareUploadResult GrpcClient::prepare_upload_public(std::string_view path) {
    return prepare_upload(path, std::string("public"));
}

PrepareUploadResult GrpcClient::prepare_data_upload(const std::vector<uint8_t>& data,
                                                    std::optional<std::string> visibility) {
    grpc::ClientContext ctx;
    antd::v1::PrepareDataUploadRequest req;
    req.set_data(data.data(), data.size());
    if (visibility) {
        req.set_visibility(*visibility);
    }
    antd::v1::PrepareUploadResponse resp;
    check_status(impl_->upload_stub->PrepareDataUpload(&ctx, req, &resp));
    return map_prepare_upload_response(resp);
}

FinalizeUploadResult GrpcClient::finalize_upload(std::string_view upload_id,
                                                  const std::map<std::string, std::string>& tx_hashes,
                                                  bool store_data_map) {
    grpc::ClientContext ctx;
    antd::v1::FinalizeUploadRequest req;
    req.set_upload_id(std::string(upload_id));
    req.set_store_data_map(store_data_map);
    auto* tx_map = req.mutable_tx_hashes();
    for (const auto& [k, v] : tx_hashes) {
        (*tx_map)[k] = v;
    }
    antd::v1::FinalizeUploadResponse resp;
    check_status(impl_->upload_stub->FinalizeUpload(&ctx, req, &resp));
    return map_finalize_upload_response(resp);
}

FinalizeUploadResult GrpcClient::finalize_merkle_upload(std::string_view upload_id,
                                                         std::string_view winner_pool_hash,
                                                         bool store_data_map) {
    grpc::ClientContext ctx;
    antd::v1::FinalizeUploadRequest req;
    req.set_upload_id(std::string(upload_id));
    req.set_winner_pool_hash(std::string(winner_pool_hash));
    req.set_store_data_map(store_data_map);
    antd::v1::FinalizeUploadResponse resp;
    check_status(impl_->upload_stub->FinalizeUpload(&ctx, req, &resp));
    return map_finalize_upload_response(resp);
}

PrepareChunkResult GrpcClient::prepare_chunk_upload(const std::vector<uint8_t>& data) {
    grpc::ClientContext ctx;
    antd::v1::PrepareChunkRequest req;
    req.set_data(data.data(), data.size());
    antd::v1::PrepareChunkResponse resp;
    check_status(impl_->chunk_stub->PrepareChunk(&ctx, req, &resp));

    PrepareChunkResult r;
    r.address = resp.address();
    r.already_stored = resp.already_stored();
    if (resp.already_stored()) {
        // Wave-batch fields are zero/empty by proto3 default — leave them.
        return r;
    }
    r.upload_id = resp.upload_id();
    r.payment_type = resp.payment_type();
    r.total_amount = resp.total_amount();
    r.payment_vault_address = resp.payment_vault_address();
    r.payment_token_address = resp.payment_token_address();
    r.rpc_url = resp.rpc_url();
    for (const auto& p : resp.payments()) {
        r.payments.push_back(PaymentInfo{
            .quote_hash = p.quote_hash(),
            .rewards_address = p.rewards_address(),
            .amount = p.amount(),
        });
    }
    return r;
}

std::string GrpcClient::finalize_chunk_upload(std::string_view upload_id,
                                              const std::map<std::string, std::string>& tx_hashes) {
    grpc::ClientContext ctx;
    antd::v1::FinalizeChunkRequest req;
    req.set_upload_id(std::string(upload_id));
    auto* tx_map = req.mutable_tx_hashes();
    for (const auto& [k, v] : tx_hashes) {
        (*tx_map)[k] = v;
    }
    antd::v1::FinalizeChunkResponse resp;
    check_status(impl_->chunk_stub->FinalizeChunk(&ctx, req, &resp));
    return resp.address();
}

}  // namespace antd
