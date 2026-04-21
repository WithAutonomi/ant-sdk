use tonic::transport::Server;
use tonic::{Request, Response, Status};

use crate::errors::AntdError;
use crate::grpc_client::proto::antd::v1;
use crate::grpc_client::GrpcClient;
use crate::models::*;

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

    async fn put_private(
        &self,
        _request: Request<v1::PutPrivateDataRequest>,
    ) -> Result<Response<v1::PutPrivateDataResponse>, Status> {
        Ok(Response::new(v1::PutPrivateDataResponse {
            cost: Some(v1::Cost {
                atto_tokens: "200".to_string(),
                ..Default::default()
            }),
            data_map: "dm123".to_string(),
        }))
    }

    async fn get_private(
        &self,
        _request: Request<v1::GetPrivateDataRequest>,
    ) -> Result<Response<v1::GetPrivateDataResponse>, Status> {
        Ok(Response::new(v1::GetPrivateDataResponse {
            data: b"secret".to_vec(),
        }))
    }

    async fn get_cost(
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
}

#[derive(Default)]
struct MockFileService;

#[tonic::async_trait]
impl v1::file_service_server::FileService for MockFileService {
    async fn upload_public(
        &self,
        _request: Request<v1::UploadFileRequest>,
    ) -> Result<Response<v1::UploadPublicResponse>, Status> {
        Ok(Response::new(v1::UploadPublicResponse {
            address: "file1".to_string(),
            storage_cost_atto: "1000".to_string(),
            gas_cost_wei: "42".to_string(),
            chunks_stored: 3,
            payment_mode_used: "auto".to_string(),
        }))
    }

    async fn download_public(
        &self,
        _request: Request<v1::DownloadPublicRequest>,
    ) -> Result<Response<v1::DownloadResponse>, Status> {
        Ok(Response::new(v1::DownloadResponse {}))
    }

    async fn dir_upload_public(
        &self,
        _request: Request<v1::UploadFileRequest>,
    ) -> Result<Response<v1::UploadPublicResponse>, Status> {
        Ok(Response::new(v1::UploadPublicResponse {
            address: "dir1".to_string(),
            storage_cost_atto: "2000".to_string(),
            gas_cost_wei: "100".to_string(),
            chunks_stored: 5,
            payment_mode_used: "merkle".to_string(),
        }))
    }

    async fn dir_download_public(
        &self,
        _request: Request<v1::DownloadPublicRequest>,
    ) -> Result<Response<v1::DownloadResponse>, Status> {
        Ok(Response::new(v1::DownloadResponse {}))
    }

    async fn get_file_cost(
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
}

#[tokio::test]
async fn test_grpc_data_put_public() {
    let client = start_mock_server().await;
    let result = client.data_put_public(b"hello").await.unwrap();
    assert_eq!(result.address, "abc123");
    assert_eq!(result.cost, "100");
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
    let result = client.data_put_private(b"secret").await.unwrap();
    assert_eq!(result.address, "dm123");
    assert_eq!(result.cost, "200");
}

#[tokio::test]
async fn test_grpc_data_get_private() {
    let client = start_mock_server().await;
    let data = client.data_get_private("dm123").await.unwrap();
    assert_eq!(data, b"secret");
}

#[tokio::test]
async fn test_grpc_data_cost() {
    let client = start_mock_server().await;
    let cost = client.data_cost(b"test").await.unwrap();
    assert_eq!(cost, "50");
}

#[tokio::test]
async fn test_grpc_estimate_data_cost() {
    let client = start_mock_server().await;
    let est = client.estimate_data_cost(b"test").await.unwrap();
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
    let result = client.file_upload_public("/tmp/test.txt").await.unwrap();
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
        .file_download_public("file1", "/tmp/out.txt")
        .await
        .unwrap();
}

#[tokio::test]
async fn test_grpc_dir_upload_public() {
    let client = start_mock_server().await;
    let result = client.dir_upload_public("/tmp/mydir").await.unwrap();
    assert_eq!(result.address, "dir1");
    assert_eq!(result.storage_cost_atto, "2000");
    assert_eq!(result.gas_cost_wei, "100");
    assert_eq!(result.chunks_stored, 5);
    assert_eq!(result.payment_mode_used, "merkle");
}

#[tokio::test]
async fn test_grpc_dir_download_public() {
    let client = start_mock_server().await;
    client
        .dir_download_public("dir1", "/tmp/outdir")
        .await
        .unwrap();
}

#[tokio::test]
async fn test_grpc_file_cost() {
    let client = start_mock_server().await;
    let cost = client
        .file_cost("/tmp/test.txt", true)
        .await
        .unwrap();
    assert_eq!(cost, "1000");
}

#[tokio::test]
async fn test_grpc_estimate_file_cost() {
    let client = start_mock_server().await;
    let est = client
        .estimate_file_cost("/tmp/test.txt", true)
        .await
        .unwrap();
    assert_eq!(est.cost, "1000");
    assert_eq!(est.file_size, 4096);
    assert_eq!(est.chunk_count, 3);
    assert_eq!(est.estimated_gas_cost_wei, "150000000000000");
    assert_eq!(est.payment_mode, "auto");
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
    let client =
        start_error_server(tonic::Code::FailedPrecondition, "insufficient funds").await;
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
    let client =
        start_error_server(tonic::Code::ResourceExhausted, "payload too large").await;
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
