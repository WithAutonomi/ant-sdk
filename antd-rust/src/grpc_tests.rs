use tonic::transport::Server;
use tonic::{Request, Response, Status};

use crate::errors::AntdError;
use crate::grpc_client::proto::antd::v1;
use crate::grpc_client::GrpcClient;
use crate::models::PaymentMode;

// --- Mock service implementations ---

#[derive(Default)]
struct MockHealthService;

#[tonic::async_trait]
impl v1::health_service_server::HealthService for MockHealthService {
    async fn check(
        &self,
        _request: Request<v1::HealthCheckRequest>,
    ) -> Result<Response<v1::HealthCheckResponse>, Status> {
        Ok(Response::new(v1::HealthCheckResponse {
            status: "ok".to_string(),
            network: "local".to_string(),
            version: "0.4.0".to_string(),
            evm_network: "local".to_string(),
            uptime_seconds: 42,
            build_commit: "abcdef123456".to_string(),
            payment_token_address: "0xtoken".to_string(),
            payment_vault_address: "0xvault".to_string(),
        }))
    }
}

#[derive(Default)]
struct MockDataService;

#[tonic::async_trait]
impl v1::data_service_server::DataService for MockDataService {
    async fn put_public(
        &self,
        _request: Request<v1::PutPublicDataRequest>,
    ) -> Result<Response<v1::PutPublicDataResponse>, Status> {
        Ok(Response::new(v1::PutPublicDataResponse {
            cost: Some(v1::Cost {
                atto_tokens: "100".to_string(),
                ..Default::default()
            }),
            address: "abc123".to_string(),
        }))
    }

    async fn get_public(
        &self,
        _request: Request<v1::GetPublicDataRequest>,
    ) -> Result<Response<v1::GetPublicDataResponse>, Status> {
        Ok(Response::new(v1::GetPublicDataResponse {
            data: b"hello".to_vec(),
        }))
    }

    async fn put(
        &self,
        _request: Request<v1::PutDataRequest>,
    ) -> Result<Response<v1::PutDataResponse>, Status> {
        Ok(Response::new(v1::PutDataResponse {
            cost: Some(v1::Cost {
                atto_tokens: "200".to_string(),
                ..Default::default()
            }),
            data_map: "dm123".to_string(),
        }))
    }

    async fn get(
        &self,
        _request: Request<v1::GetDataRequest>,
    ) -> Result<Response<v1::GetDataResponse>, Status> {
        Ok(Response::new(v1::GetDataResponse {
            data: b"secret".to_vec(),
        }))
    }

    async fn cost(
        &self,
        _request: Request<v1::DataCostRequest>,
    ) -> Result<Response<v1::Cost>, Status> {
        Ok(Response::new(v1::Cost {
            atto_tokens: "50".to_string(),
            file_size: 4,
            chunk_count: 3,
            estimated_gas_cost_wei: "150000000000000".to_string(),
            payment_mode: "single".to_string(),
        }))
    }

    type StreamPublicStream = tokio_stream::wrappers::ReceiverStream<Result<v1::DataChunk, Status>>;

    async fn stream_public(
        &self,
        _request: Request<v1::StreamPublicDataRequest>,
    ) -> Result<Response<Self::StreamPublicStream>, Status> {
        let (_tx, rx) = tokio::sync::mpsc::channel(1);
        Ok(Response::new(tokio_stream::wrappers::ReceiverStream::new(
            rx,
        )))
    }
}

#[derive(Default)]
struct MockChunkService;

#[tonic::async_trait]
impl v1::chunk_service_server::ChunkService for MockChunkService {
    async fn put(
        &self,
        _request: Request<v1::PutChunkRequest>,
    ) -> Result<Response<v1::PutChunkResponse>, Status> {
        Ok(Response::new(v1::PutChunkResponse {
            cost: Some(v1::Cost {
                atto_tokens: "10".to_string(),
                ..Default::default()
            }),
            address: "chunk1".to_string(),
        }))
    }

    async fn get(
        &self,
        _request: Request<v1::GetChunkRequest>,
    ) -> Result<Response<v1::GetChunkResponse>, Status> {
        Ok(Response::new(v1::GetChunkResponse {
            data: b"chunkdata".to_vec(),
        }))
    }

    async fn prepare_chunk(
        &self,
        request: Request<v1::PrepareChunkRequest>,
    ) -> Result<Response<v1::PrepareChunkResponse>, Status> {
        let data = request.into_inner().data;
        // Inputs starting with "EXISTS" are treated as already-stored.
        if data.starts_with(b"EXISTS") {
            return Ok(Response::new(v1::PrepareChunkResponse {
                address: "0xabc".to_string(),
                already_stored: true,
                ..Default::default()
            }));
        }
        Ok(Response::new(v1::PrepareChunkResponse {
            address: "0xnewchunk".to_string(),
            already_stored: false,
            upload_id: "upid_chunk_42".to_string(),
            payment_type: "wave_batch".to_string(),
            payments: vec![v1::PaymentEntry {
                quote_hash: "0xq1".to_string(),
                rewards_address: "0xr1".to_string(),
                amount: "100".to_string(),
            }],
            total_amount: "100".to_string(),
            payment_vault_address: "0xvault".to_string(),
            payment_token_address: "0xtoken".to_string(),
            rpc_url: "http://localhost:8545".to_string(),
        }))
    }

    async fn finalize_chunk(
        &self,
        request: Request<v1::FinalizeChunkRequest>,
    ) -> Result<Response<v1::FinalizeChunkResponse>, Status> {
        let req = request.into_inner();
        // Echo the upload_id into the address so the test can verify
        // request-body forwarding.
        Ok(Response::new(v1::FinalizeChunkResponse {
            address: format!("addr_for_{}", req.upload_id),
        }))
    }
}

#[derive(Default)]
struct MockUploadService;

#[tonic::async_trait]
impl v1::upload_service_server::UploadService for MockUploadService {
    async fn prepare_file_upload(
        &self,
        request: Request<v1::PrepareFileUploadRequest>,
    ) -> Result<Response<v1::PrepareUploadResponse>, Status> {
        let req = request.into_inner();
        // Encode the visibility into the upload_id so the test can verify
        // the field is forwarded over the wire.
        let upload_id = format!("upid_file_{}", req.visibility);
        Ok(Response::new(v1::PrepareUploadResponse {
            upload_id,
            payment_type: "wave_batch".to_string(),
            payments: vec![v1::PaymentEntry {
                quote_hash: "0xqa".to_string(),
                rewards_address: "0xra".to_string(),
                amount: "1".to_string(),
            }],
            total_amount: "1".to_string(),
            payment_vault_address: "0xvault".to_string(),
            payment_token_address: "0xtoken".to_string(),
            rpc_url: "http://localhost:8545".to_string(),
            ..Default::default()
        }))
    }

    async fn prepare_data_upload(
        &self,
        request: Request<v1::PrepareDataUploadRequest>,
    ) -> Result<Response<v1::PrepareUploadResponse>, Status> {
        let req = request.into_inner();
        // Merkle response when payload starts with "MERKLE"; otherwise
        // wave_batch. Also echoes visibility into upload_id like the
        // file variant.
        let upload_id = format!("upid_data_{}", req.visibility);
        if req.data.starts_with(b"MERKLE") {
            return Ok(Response::new(v1::PrepareUploadResponse {
                upload_id,
                payment_type: "merkle".to_string(),
                payments: vec![],
                depth: 7,
                pool_commitments: vec![v1::PoolCommitmentEntry {
                    pool_hash: "0xpool".to_string(),
                    candidates: vec![v1::CandidateNodeEntry {
                        rewards_address: "0xc1".to_string(),
                        amount: "5".to_string(),
                    }],
                }],
                merkle_payment_timestamp: 1_700_000_000,
                total_amount: "0".to_string(),
                payment_vault_address: "0xvault".to_string(),
                payment_token_address: "0xtoken".to_string(),
                rpc_url: "http://localhost:8545".to_string(),
            }));
        }
        Ok(Response::new(v1::PrepareUploadResponse {
            upload_id,
            payment_type: "wave_batch".to_string(),
            payments: vec![v1::PaymentEntry {
                quote_hash: "0xqb".to_string(),
                rewards_address: "0xrb".to_string(),
                amount: "2".to_string(),
            }],
            total_amount: "2".to_string(),
            payment_vault_address: "0xvault".to_string(),
            payment_token_address: "0xtoken".to_string(),
            rpc_url: "http://localhost:8545".to_string(),
            ..Default::default()
        }))
    }

    async fn finalize_upload(
        &self,
        request: Request<v1::FinalizeUploadRequest>,
    ) -> Result<Response<v1::FinalizeUploadResponse>, Status> {
        let req = request.into_inner();
        // Wave-batch: tx_hashes populated, winner_pool_hash empty.
        // Merkle:     winner_pool_hash populated, tx_hashes empty.
        if !req.winner_pool_hash.is_empty() {
            return Ok(Response::new(v1::FinalizeUploadResponse {
                data_map: "dm_merkle".to_string(),
                address: if req.store_data_map {
                    "stored_on_network".to_string()
                } else {
                    String::new()
                },
                data_map_address: String::new(),
                chunks_stored: 64,
            }));
        }
        // Wave-batch — include data_map_address when visibility was public
        // (encoded into upload_id).
        let was_public = req.upload_id.ends_with("public");
        Ok(Response::new(v1::FinalizeUploadResponse {
            data_map: "dm_wave".to_string(),
            address: String::new(),
            data_map_address: if was_public {
                "addr_public_dm".to_string()
            } else {
                String::new()
            },
            chunks_stored: 3,
        }))
    }
}

#[derive(Default)]
struct MockFileService;

#[tonic::async_trait]
impl v1::file_service_server::FileService for MockFileService {
    async fn put(
        &self,
        _request: Request<v1::PutFileRequest>,
    ) -> Result<Response<v1::PutFileResponse>, Status> {
        Ok(Response::new(v1::PutFileResponse {
            data_map: "dmfile1".to_string(),
            storage_cost_atto: "900".to_string(),
            gas_cost_wei: "41".to_string(),
            chunks_stored: 3,
            payment_mode_used: "auto".to_string(),
        }))
    }

    async fn put_public(
        &self,
        _request: Request<v1::PutFileRequest>,
    ) -> Result<Response<v1::PutFilePublicResponse>, Status> {
        Ok(Response::new(v1::PutFilePublicResponse {
            address: "file1".to_string(),
            storage_cost_atto: "1000".to_string(),
            gas_cost_wei: "42".to_string(),
            chunks_stored: 3,
            payment_mode_used: "auto".to_string(),
        }))
    }

    async fn get(
        &self,
        _request: Request<v1::GetFileRequest>,
    ) -> Result<Response<v1::GetFileResponse>, Status> {
        Ok(Response::new(v1::GetFileResponse {}))
    }

    async fn get_public(
        &self,
        _request: Request<v1::GetFilePublicRequest>,
    ) -> Result<Response<v1::GetFileResponse>, Status> {
        Ok(Response::new(v1::GetFileResponse {}))
    }

    async fn cost(
        &self,
        _request: Request<v1::FileCostRequest>,
    ) -> Result<Response<v1::Cost>, Status> {
        Ok(Response::new(v1::Cost {
            atto_tokens: "1000".to_string(),
            file_size: 4096,
            chunk_count: 3,
            estimated_gas_cost_wei: "150000000000000".to_string(),
            payment_mode: "auto".to_string(),
        }))
    }
}

// --- Error mock: HealthService that returns a configurable gRPC status ---

struct ErrorHealthService {
    code: tonic::Code,
    msg: String,
}

#[tonic::async_trait]
impl v1::health_service_server::HealthService for ErrorHealthService {
    async fn check(
        &self,
        _request: Request<v1::HealthCheckRequest>,
    ) -> Result<Response<v1::HealthCheckResponse>, Status> {
        Err(Status::new(self.code, self.msg.clone()))
    }
}

// --- Test helpers ---

/// Starts a mock gRPC server on a random port and returns a connected GrpcClient.
async fn start_mock_server() -> GrpcClient {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        let incoming = tokio_stream::wrappers::TcpListenerStream::new(listener);
        Server::builder()
            .add_service(v1::health_service_server::HealthServiceServer::new(
                MockHealthService,
            ))
            .add_service(v1::data_service_server::DataServiceServer::new(
                MockDataService,
            ))
            .add_service(v1::chunk_service_server::ChunkServiceServer::new(
                MockChunkService,
            ))
            .add_service(v1::file_service_server::FileServiceServer::new(
                MockFileService,
            ))
            .add_service(v1::upload_service_server::UploadServiceServer::new(
                MockUploadService,
            ))
            .serve_with_incoming(incoming)
            .await
            .unwrap();
    });

    // Give the server a moment to start.
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    GrpcClient::new(&format!("http://{addr}")).await.unwrap()
}

/// Starts a mock gRPC server that returns an error for the HealthService.
async fn start_error_server(code: tonic::Code, msg: &str) -> GrpcClient {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let error_svc = ErrorHealthService {
        code,
        msg: msg.to_string(),
    };

    tokio::spawn(async move {
        let incoming = tokio_stream::wrappers::TcpListenerStream::new(listener);
        Server::builder()
            .add_service(v1::health_service_server::HealthServiceServer::new(
                error_svc,
            ))
            .serve_with_incoming(incoming)
            .await
            .unwrap();
    });

    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    GrpcClient::new(&format!("http://{addr}")).await.unwrap()
}

// --- Tests for all gRPC methods ---

#[tokio::test]
async fn test_grpc_health() {
    let client = start_mock_server().await;
    let health = client.health().await.unwrap();
    assert!(health.ok);
    assert_eq!(health.network, "local");
    assert_eq!(health.version, "0.4.0");
    assert_eq!(health.evm_network, "local");
    assert_eq!(health.uptime_seconds, 42);
    assert_eq!(health.build_commit, "abcdef123456");
    assert_eq!(health.payment_token_address, "0xtoken");
    assert_eq!(health.payment_vault_address, "0xvault");
}

#[tokio::test]
async fn test_grpc_data_put_public() {
    let client = start_mock_server().await;
    let result = client
        .data_put_public(b"hello", PaymentMode::Auto)
        .await
        .unwrap();
    assert_eq!(result.address, "abc123");
}

#[tokio::test]
async fn test_grpc_data_get_public() {
    let client = start_mock_server().await;
    let data = client.data_get_public("abc123").await.unwrap();
    assert_eq!(data, b"hello");
}

#[tokio::test]
async fn test_grpc_data_put_private() {
    let client = start_mock_server().await;
    let result = client.data_put(b"secret", PaymentMode::Auto).await.unwrap();
    assert_eq!(result.data_map, "dm123");
}

#[tokio::test]
async fn test_grpc_data_get_private() {
    let client = start_mock_server().await;
    let data = client.data_get("dm123").await.unwrap();
    assert_eq!(data, b"secret");
}

#[tokio::test]
async fn test_grpc_data_cost() {
    let client = start_mock_server().await;
    let est = client.data_cost(b"test", PaymentMode::Auto).await.unwrap();
    assert_eq!(est.cost, "50");
    assert_eq!(est.file_size, 4);
    assert_eq!(est.chunk_count, 3);
    assert_eq!(est.estimated_gas_cost_wei, "150000000000000");
    assert_eq!(est.payment_mode, "single");
}

#[tokio::test]
async fn test_grpc_chunk_put() {
    let client = start_mock_server().await;
    let result = client.chunk_put(b"chunkdata").await.unwrap();
    assert_eq!(result.address, "chunk1");
    assert_eq!(result.cost, "10");
}

#[tokio::test]
async fn test_grpc_chunk_get() {
    let client = start_mock_server().await;
    let data = client.chunk_get("chunk1").await.unwrap();
    assert_eq!(data, b"chunkdata");
}

#[tokio::test]
async fn test_grpc_file_upload_public() {
    let client = start_mock_server().await;
    let result = client
        .file_put_public("/tmp/test.txt", PaymentMode::Auto)
        .await
        .unwrap();
    assert_eq!(result.address, "file1");
    assert_eq!(result.storage_cost_atto, "1000");
    assert_eq!(result.gas_cost_wei, "42");
    assert_eq!(result.chunks_stored, 3);
    assert_eq!(result.payment_mode_used, "auto");
}

#[tokio::test]
async fn test_grpc_file_download_public() {
    let client = start_mock_server().await;
    client
        .file_get_public("file1", "/tmp/out.txt")
        .await
        .unwrap();
}

#[tokio::test]
async fn test_grpc_file_cost() {
    let client = start_mock_server().await;
    let est = client
        .file_cost("/tmp/test.txt", true, PaymentMode::Auto)
        .await
        .unwrap();
    assert_eq!(est.cost, "1000");
    assert_eq!(est.file_size, 4096);
    assert_eq!(est.chunk_count, 3);
    assert_eq!(est.estimated_gas_cost_wei, "150000000000000");
    assert_eq!(est.payment_mode, "auto");
}

// --- External-signer prepare/finalize tests ---

#[tokio::test]
async fn test_grpc_prepare_upload_omits_visibility_when_none() {
    let client = start_mock_server().await;
    let result = client.prepare_upload("/tmp/x.bin", None).await.unwrap();
    // Empty visibility = proto3 default; the mock echoes it into upload_id.
    assert_eq!(result.upload_id, "upid_file_");
    assert_eq!(result.payment_type, "wave_batch");
    assert_eq!(result.payments.len(), 1);
    assert_eq!(result.payments[0].quote_hash, "0xqa");
    assert!(result.depth.is_none());
    assert!(result.pool_commitments.is_none());
}

#[tokio::test]
async fn test_grpc_prepare_upload_forwards_visibility_public() {
    let client = start_mock_server().await;
    let result = client
        .prepare_upload("/tmp/x.bin", Some("public"))
        .await
        .unwrap();
    assert_eq!(result.upload_id, "upid_file_public");
}

#[tokio::test]
async fn test_grpc_prepare_upload_public_convenience() {
    let client = start_mock_server().await;
    let result = client.prepare_upload_public("/tmp/x.bin").await.unwrap();
    assert_eq!(result.upload_id, "upid_file_public");
}

#[tokio::test]
async fn test_grpc_prepare_data_upload_wave_batch() {
    let client = start_mock_server().await;
    let result = client
        .prepare_data_upload(b"small", Some("private"))
        .await
        .unwrap();
    assert_eq!(result.upload_id, "upid_data_private");
    assert_eq!(result.payment_type, "wave_batch");
    assert!(result.depth.is_none());
}

#[tokio::test]
async fn test_grpc_prepare_data_upload_merkle() {
    let client = start_mock_server().await;
    let result = client
        .prepare_data_upload(b"MERKLE-large-payload", None)
        .await
        .unwrap();
    assert_eq!(result.payment_type, "merkle");
    assert_eq!(result.depth, Some(7));
    assert_eq!(result.merkle_payment_timestamp, Some(1_700_000_000));
    let pcs = result.pool_commitments.expect("pool_commitments present");
    assert_eq!(pcs.len(), 1);
    assert_eq!(pcs[0].pool_hash, "0xpool");
    assert_eq!(pcs[0].candidates[0].rewards_address, "0xc1");
}

#[tokio::test]
async fn test_grpc_finalize_upload_wave_batch_omits_data_map_address_when_private() {
    let client = start_mock_server().await;
    let mut tx_hashes = std::collections::HashMap::new();
    tx_hashes.insert("0xq1".to_string(), "0xtx1".to_string());
    let result = client
        .finalize_upload("upid_file_", &tx_hashes)
        .await
        .unwrap();
    assert_eq!(result.data_map, "dm_wave");
    assert_eq!(result.data_map_address, "");
    assert_eq!(result.chunks_stored, 3);
}

#[tokio::test]
async fn test_grpc_finalize_upload_wave_batch_returns_data_map_address_when_public() {
    let client = start_mock_server().await;
    let mut tx_hashes = std::collections::HashMap::new();
    tx_hashes.insert("0xq1".to_string(), "0xtx1".to_string());
    let result = client
        .finalize_upload("upid_file_public", &tx_hashes)
        .await
        .unwrap();
    assert_eq!(result.data_map_address, "addr_public_dm");
}

#[tokio::test]
async fn test_grpc_finalize_merkle_upload_store_data_map_true() {
    let client = start_mock_server().await;
    let result = client
        .finalize_merkle_upload("upid_data_", "0xwinpool", true)
        .await
        .unwrap();
    assert_eq!(result.data_map, "dm_merkle");
    assert_eq!(result.address, "stored_on_network");
    assert_eq!(result.chunks_stored, 64);
}

#[tokio::test]
async fn test_grpc_finalize_merkle_upload_store_data_map_false() {
    let client = start_mock_server().await;
    let result = client
        .finalize_merkle_upload("upid_data_", "0xwinpool", false)
        .await
        .unwrap();
    assert_eq!(result.data_map, "dm_merkle");
    assert_eq!(result.address, "");
}

#[tokio::test]
async fn test_grpc_prepare_chunk_upload_new_chunk() {
    let client = start_mock_server().await;
    let result = client.prepare_chunk_upload(b"newchunk").await.unwrap();
    assert!(!result.already_stored);
    assert_eq!(result.address, "0xnewchunk");
    assert_eq!(result.upload_id, "upid_chunk_42");
    assert_eq!(result.payment_type, "wave_batch");
    assert_eq!(result.payments.len(), 1);
    assert_eq!(result.payments[0].quote_hash, "0xq1");
    assert_eq!(result.total_amount, "100");
    assert_eq!(result.rpc_url, "http://localhost:8545");
}

#[tokio::test]
async fn test_grpc_prepare_chunk_upload_already_stored_short_circuit() {
    let client = start_mock_server().await;
    let result = client.prepare_chunk_upload(b"EXISTS-data").await.unwrap();
    assert!(result.already_stored);
    assert_eq!(result.address, "0xabc");
    assert_eq!(result.upload_id, "");
    assert!(result.payments.is_empty());
}

#[tokio::test]
async fn test_grpc_finalize_chunk_upload_returns_address_and_forwards_body() {
    let client = start_mock_server().await;
    let mut tx_hashes = std::collections::HashMap::new();
    tx_hashes.insert("0xq1".to_string(), "0xtxabc".to_string());
    let addr = client
        .finalize_chunk_upload("upid_chunk_42", &tx_hashes)
        .await
        .unwrap();
    assert_eq!(addr, "addr_for_upid_chunk_42");
}

// --- gRPC error mapping tests ---

#[tokio::test]
async fn test_grpc_error_not_found() {
    let client = start_error_server(tonic::Code::NotFound, "not found").await;
    let err = client.health().await.unwrap_err();
    match err {
        AntdError::Grpc(status) => {
            assert_eq!(status.code(), tonic::Code::NotFound);
            assert_eq!(status.message(), "not found");
        }
        other => panic!("expected AntdError::Grpc, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_grpc_error_invalid_argument() {
    let client = start_error_server(tonic::Code::InvalidArgument, "invalid data").await;
    let err = client.health().await.unwrap_err();
    match err {
        AntdError::Grpc(status) => {
            assert_eq!(status.code(), tonic::Code::InvalidArgument);
            assert_eq!(status.message(), "invalid data");
        }
        other => panic!("expected AntdError::Grpc, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_grpc_error_failed_precondition() {
    let client = start_error_server(tonic::Code::FailedPrecondition, "insufficient funds").await;
    let err = client.health().await.unwrap_err();
    match err {
        AntdError::Grpc(status) => {
            assert_eq!(status.code(), tonic::Code::FailedPrecondition);
            assert_eq!(status.message(), "insufficient funds");
        }
        other => panic!("expected AntdError::Grpc, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_grpc_error_already_exists() {
    let client = start_error_server(tonic::Code::AlreadyExists, "already exists").await;
    let err = client.health().await.unwrap_err();
    match err {
        AntdError::Grpc(status) => {
            assert_eq!(status.code(), tonic::Code::AlreadyExists);
            assert_eq!(status.message(), "already exists");
        }
        other => panic!("expected AntdError::Grpc, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_grpc_error_resource_exhausted() {
    let client = start_error_server(tonic::Code::ResourceExhausted, "payload too large").await;
    let err = client.health().await.unwrap_err();
    match err {
        AntdError::Grpc(status) => {
            assert_eq!(status.code(), tonic::Code::ResourceExhausted);
            assert_eq!(status.message(), "payload too large");
        }
        other => panic!("expected AntdError::Grpc, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_grpc_error_internal() {
    let client = start_error_server(tonic::Code::Internal, "server error").await;
    let err = client.health().await.unwrap_err();
    match err {
        AntdError::Grpc(status) => {
            assert_eq!(status.code(), tonic::Code::Internal);
            assert_eq!(status.message(), "server error");
        }
        other => panic!("expected AntdError::Grpc, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_grpc_error_unavailable() {
    let client = start_error_server(tonic::Code::Unavailable, "network unreachable").await;
    let err = client.health().await.unwrap_err();
    match err {
        AntdError::Grpc(status) => {
            assert_eq!(status.code(), tonic::Code::Unavailable);
            assert_eq!(status.message(), "network unreachable");
        }
        other => panic!("expected AntdError::Grpc, got: {other:?}"),
    }
}
