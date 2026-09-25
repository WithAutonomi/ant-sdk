use tonic::transport::Server;
use tonic::{Request, Response, Status};

use crate::errors::AntdError;
use crate::grpc_client::proto::antd::v1;
use crate::grpc_client::GrpcClient;
use crate::models::{PaymentMode, PrepareOptions, VerifyQuoteEntry};

// --- Mock service implementations ---

/// The daemon's shape for one signed wave-batch quote when the request set
/// `include_signed_quotes`: raw msgpack bytes on the wire ("opaque" / "side"
/// stand in), which the client must base64-encode into the shared model.
fn mock_signed_quotes(include: bool, quote_hash: &str) -> Vec<v1::SignedQuoteEntry> {
    if !include {
        return Vec::new();
    }
    vec![v1::SignedQuoteEntry {
        quote_hash: quote_hash.to_string(),
        quote: b"opaque".to_vec(),
        commitment_sidecar: b"side".to_vec(),
    }]
}

/// Requesting this path with `include_signed_quotes` makes the mock return
/// [`big_signed_quotes`]: a full-size wave-batch prepare whose signed quotes
/// push the response well past tonic's 4 MiB default receive limit.
const BIG_PREPARE_PATH: &str = "/big";

/// 1024 entries (the daemon's `MAX_VERIFY_ENTRIES`) with 8,000-byte quote
/// blobs, about 8.3 MB on the wire. Synthetic transport fixture only; the
/// bytes are not real quotes.
fn big_signed_quotes() -> Vec<v1::SignedQuoteEntry> {
    (0..1024)
        .map(|i| v1::SignedQuoteEntry {
            quote_hash: format!("0xq{i:04}"),
            quote: vec![b'q'; 8000],
            commitment_sidecar: b"side".to_vec(),
        })
        .collect()
}

/// Verifies "opaque" quotes only, treats a present sidecar as a pinned
/// commitment of 42 keys, and reports the batch valid when every entry is.
#[derive(Default)]
struct MockVerifyService;

#[tonic::async_trait]
impl v1::verify_service_server::VerifyService for MockVerifyService {
    async fn verify_quotes(
        &self,
        request: Request<v1::VerifyQuotesRequest>,
    ) -> Result<Response<v1::VerifyQuotesResponse>, Status> {
        let req = request.into_inner();
        let mut valid = !req.entries.is_empty();
        let entries = req
            .entries
            .into_iter()
            .map(|e| {
                let ok = e.signed_quote == b"opaque";
                valid &= ok;
                let pinned = !e.commitment_sidecar.is_empty();
                v1::VerifyQuoteVerdict {
                    quote_hash: e.quote_hash,
                    valid: ok,
                    error: if ok {
                        String::new()
                    } else {
                        "signed_quote did not deserialize as a PaymentQuote".to_string()
                    },
                    quote_decoded: ok,
                    timestamp_unix_secs: 1_756_000_000,
                    content: "aa".to_string(),
                    price: "5".to_string(),
                    rewards_address: e.rewards_address,
                    committed_key_count: if pinned { 42 } else { 0 },
                    pinned,
                }
            })
            .collect();
        Ok(Response::new(v1::VerifyQuotesResponse { valid, entries }))
    }
}

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
            write_ready: true,
            connected_peers: 5,
            routing_table_size: 12,
            rebootstrap_threshold: 3,
            last_store_ok_secs_ago: Some(42),
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
            chunks_stored: 2,
            payment_mode_used: "auto".to_string(),
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
            chunks_stored: 3,
            payment_mode_used: "single".to_string(),
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
        // Emit the payload as two chunks so the client's chunk-by-chunk
        // consumption is exercised, not just a single message.
        let (tx, rx) = tokio::sync::mpsc::channel(2);
        tokio::spawn(async move {
            for part in [b"hel".to_vec(), b"lo".to_vec()] {
                let _ = tx
                    .send(Ok(v1::DataChunk {
                        kind: Some(v1::data_chunk::Kind::Data(part)),
                    }))
                    .await;
            }
        });
        Ok(Response::new(tokio_stream::wrappers::ReceiverStream::new(
            rx,
        )))
    }

    type StreamStream = tokio_stream::wrappers::ReceiverStream<Result<v1::DataChunk, Status>>;

    async fn stream(
        &self,
        request: Request<v1::StreamDataRequest>,
    ) -> Result<Response<Self::StreamStream>, Status> {
        let include_progress = request.into_inner().include_progress;
        let (tx, rx) = tokio::sync::mpsc::channel(4);
        tokio::spawn(async move {
            // When progress is requested, interleave a fetch-progress frame so
            // the with-progress consumer path is exercised.
            if include_progress {
                let _ = tx
                    .send(Ok(v1::DataChunk {
                        kind: Some(v1::data_chunk::Kind::Progress(v1::DownloadProgress {
                            phase: "fetching".to_string(),
                            fetched: 1,
                            total: 2,
                        })),
                    }))
                    .await;
            }
            for part in [b"sec".to_vec(), b"ret".to_vec()] {
                let _ = tx
                    .send(Ok(v1::DataChunk {
                        kind: Some(v1::data_chunk::Kind::Data(part)),
                    }))
                    .await;
            }
        });
        // The daemon attaches the total plaintext size as response metadata so
        // the consumer can surface a byte denominator (V2-510).
        let mut response = Response::new(tokio_stream::wrappers::ReceiverStream::new(rx));
        response
            .metadata_mut()
            .insert("x-content-length", "6".parse().unwrap());
        Ok(response)
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
        let req = request.into_inner();
        // Inputs starting with "EXISTS" are treated as already-stored.
        if req.data.starts_with(b"EXISTS") {
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
            signed_quotes: mock_signed_quotes(req.include_signed_quotes, "0xq1"),
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
        let signed_quotes = if req.include_signed_quotes && req.path == BIG_PREPARE_PATH {
            big_signed_quotes()
        } else {
            mock_signed_quotes(req.include_signed_quotes, "0xqa")
        };
        Ok(Response::new(v1::PrepareUploadResponse {
            upload_id,
            signed_quotes,
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
            total_chunks: 3,
            already_stored_count: 1,
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
                merkle_batches: Vec::new(),
                total_amount: "0".to_string(),
                payment_vault_address: "0xvault".to_string(),
                payment_token_address: "0xtoken".to_string(),
                rpc_url: "http://localhost:8545".to_string(),
                total_chunks: 3,
                already_stored_count: 1,
                signed_quotes: Vec::new(),
            }));
        }
        Ok(Response::new(v1::PrepareUploadResponse {
            upload_id,
            signed_quotes: mock_signed_quotes(req.include_signed_quotes, "0xqb"),
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
            total_chunks: 3,
            already_stored_count: 1,
            ..Default::default()
        }))
    }

    async fn finalize_upload(
        &self,
        request: Request<v1::FinalizeUploadRequest>,
    ) -> Result<Response<v1::FinalizeUploadResponse>, Status> {
        let req = request.into_inner();
        // Magic id: a quorum-shortfall finalize (PARTIAL_UPLOAD) whose paid
        // attempt the daemon retained for a same-upload_id retry.
        if req.upload_id == "partial" {
            return Err(Status::aborted(
                "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum \
                 (paid attempt retained: call finalize again with the same upload_id to \
                 store the remainder against the same payment)",
            ));
        }
        // Magic id: a partial upload the daemon did NOT retain (unpaid merkle
        // batches, or an older daemon's message).
        if req.upload_id == "partial-final" {
            return Err(Status::aborted(
                "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum \
                 (stored chunks persist; re-prepare the same content to retry only the \
                 remainder)",
            ));
        }
        // Magic ids: a partial upload whose counts read but whose retention
        // hint is missing or cut short; retention must read as unknown.
        if req.upload_id == "partial-no-hint" {
            return Err(Status::aborted(
                "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum",
            ));
        }
        if req.upload_id == "partial-truncated-hint" {
            return Err(Status::aborted(
                "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum \
                 (paid attempt retai",
            ));
        }
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
    let addr = spawn_mock_server().await;
    GrpcClient::new(&format!("http://{addr}")).await.unwrap()
}

/// Starts the full mock server and returns its address, so a test can connect
/// with a non-default client configuration.
async fn spawn_mock_server() -> std::net::SocketAddr {
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
            .add_service(v1::verify_service_server::VerifyServiceServer::new(
                MockVerifyService,
            ))
            .serve_with_incoming(incoming)
            .await
            .unwrap();
    });

    // Give the server a moment to start.
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    addr
}

/// A full-size signed-quote prepare response (>4 MiB, tonic's default
/// receive limit) must decode on a default client: the SDK sets its own
/// receive ceiling, sized like the daemon's, on every service client.
#[tokio::test]
async fn grpc_prepare_upload_large_signed_quote_response_fits_default_recv_limit() {
    use prost::Message;
    let fixture = v1::PrepareUploadResponse {
        signed_quotes: big_signed_quotes(),
        ..Default::default()
    };
    assert!(
        fixture.encoded_len() > 4 * 1024 * 1024,
        "fixture must exceed tonic's 4 MiB default to be a regression test, got {} bytes",
        fixture.encoded_len()
    );

    let client = start_mock_server().await;
    let r = client
        .prepare_upload_with_options(
            BIG_PREPARE_PATH,
            &PrepareOptions {
                include_signed_quotes: true,
                ..Default::default()
            },
        )
        .await
        .expect("large signed-quote response rejected on a default client");
    assert_eq!(r.signed_quotes.len(), 1024);
    assert_eq!(r.signed_quotes[1023].quote_hash, "0xq1023");
    // 8000 raw bytes -> 10668 base64 chars.
    assert_eq!(r.signed_quotes[1023].quote.len(), 10668);
}

/// The ceiling is a real bound, not a no-op: a caller-set limit below the
/// response size is enforced and surfaces as a gRPC status, not a hang or a
/// truncated result.
#[tokio::test]
async fn grpc_prepare_upload_recv_limit_is_enforced_and_configurable() {
    let addr = spawn_mock_server().await;
    let client = GrpcClient::connect_with_max_message_size(&format!("http://{addr}"), 1024 * 1024)
        .await
        .unwrap();
    let opts = PrepareOptions {
        include_signed_quotes: true,
        ..Default::default()
    };
    let err = client
        .prepare_upload_with_options(BIG_PREPARE_PATH, &opts)
        .await
        .expect_err("expected the 1 MiB receive limit to reject an 8 MB response");
    match &err {
        AntdError::Grpc(status) => {
            assert_eq!(
                status.code(),
                tonic::Code::OutOfRange,
                "unexpected status: {status:?}"
            );
            assert!(
                status.message().contains("message length too large"),
                "unexpected message: {}",
                status.message()
            );
        }
        other => panic!("expected AntdError::Grpc, got {other:?}"),
    }
    // A small response on the same client is unaffected.
    client
        .prepare_upload("/tmp/x.bin", None)
        .await
        .expect("small response failed under the lowered limit");
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
    assert!(health.write_ready);
    assert_eq!(health.connected_peers, 5);
    assert_eq!(health.routing_table_size, 12);
    assert_eq!(health.rebootstrap_threshold, 3);
    assert_eq!(health.last_store_ok_secs_ago, Some(42));
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
async fn test_grpc_data_stream_private() {
    use tokio_stream::StreamExt;
    let client = start_mock_server().await;
    let mut stream = Box::pin(client.data_stream("dm123").await.unwrap());
    let mut buf = Vec::new();
    while let Some(item) = stream.next().await {
        buf.extend_from_slice(&item.unwrap());
    }
    assert_eq!(buf, b"secret");
}

#[tokio::test]
async fn test_grpc_data_stream_public() {
    use tokio_stream::StreamExt;
    let client = start_mock_server().await;
    let mut stream = Box::pin(client.data_stream_public("abc123").await.unwrap());
    let mut buf = Vec::new();
    while let Some(item) = stream.next().await {
        buf.extend_from_slice(&item.unwrap());
    }
    assert_eq!(buf, b"hello");
}

#[tokio::test]
async fn test_grpc_data_stream_with_progress() {
    use crate::DownloadFrame;
    use tokio_stream::StreamExt;
    let client = start_mock_server().await;
    let mut stream = Box::pin(client.data_stream_with_progress("dm123").await.unwrap());

    let mut buf = Vec::new();
    let mut progress = Vec::new();
    let mut total = None;
    while let Some(item) = stream.next().await {
        match item.unwrap() {
            DownloadFrame::Meta(t) => total = Some(t),
            DownloadFrame::Data(b) => buf.extend_from_slice(&b),
            DownloadFrame::Progress(p) => progress.push(p),
        }
    }
    // Data reassembles to the full payload, the byte denominator arrives as a
    // leading Meta frame (from x-content-length), and the interleaved progress
    // frame is surfaced separately (not spliced into the bytes).
    assert_eq!(buf, b"secret");
    assert_eq!(total, Some(6));
    assert_eq!(progress.len(), 1);
    assert_eq!(progress[0].phase, "fetching");
    assert_eq!(progress[0].fetched, 1);
    assert_eq!(progress[0].total, 2);
}

#[tokio::test]
async fn test_grpc_data_stream_no_progress_when_not_requested() {
    // The plain data_stream sets include_progress=false, so the mock emits no
    // progress frame and the consumer sees only data bytes.
    use tokio_stream::StreamExt;
    let client = start_mock_server().await;
    let mut stream = Box::pin(client.data_stream("dm123").await.unwrap());
    let mut buf = Vec::new();
    while let Some(item) = stream.next().await {
        buf.extend_from_slice(&item.unwrap());
    }
    assert_eq!(buf, b"secret");
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
    assert_eq!(result.total_chunks, 3);
    assert_eq!(result.already_stored_count, 1);
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
async fn test_grpc_prepare_upload_with_options_sends_flag_and_maps_signed_quotes() {
    let client = start_mock_server().await;
    let opts = PrepareOptions {
        visibility: None,
        include_signed_quotes: true,
    };
    let r = client
        .prepare_upload_with_options("/tmp/x.bin", &opts)
        .await
        .unwrap();
    // Raw proto bytes must land base64-encoded, exactly as REST delivers them.
    assert_eq!(r.signed_quotes.len(), 1);
    assert_eq!(r.signed_quotes[0].quote_hash, "0xqa");
    assert_eq!(r.signed_quotes[0].quote, "b3BhcXVl");
    assert_eq!(
        r.signed_quotes[0].commitment_sidecar.as_deref(),
        Some("c2lkZQ==")
    );
    // Options must not disturb the rest of the mapping.
    assert_eq!(r.upload_id, "upid_file_");
    assert_eq!(r.total_chunks, 3);
    assert_eq!(r.already_stored_count, 1);
}

#[tokio::test]
async fn test_grpc_prepare_without_flag_carries_no_signed_quotes() {
    let client = start_mock_server().await;
    let file = client.prepare_upload("/tmp/x.bin", None).await.unwrap();
    assert!(file.signed_quotes.is_empty());
    let data = client.prepare_data_upload(b"small", None).await.unwrap();
    assert!(data.signed_quotes.is_empty());
    let chunk = client.prepare_chunk_upload(b"newchunk").await.unwrap();
    assert!(chunk.signed_quotes.is_empty());
}

#[tokio::test]
async fn test_grpc_prepare_data_upload_with_options_sends_flag_and_visibility() {
    let client = start_mock_server().await;
    let opts = PrepareOptions {
        visibility: Some("public".to_string()),
        include_signed_quotes: true,
    };
    let r = client
        .prepare_data_upload_with_options(b"small", &opts)
        .await
        .unwrap();
    assert_eq!(r.upload_id, "upid_data_public");
    assert_eq!(r.signed_quotes.len(), 1);
    assert_eq!(r.signed_quotes[0].quote_hash, "0xqb");
    assert_eq!(r.signed_quotes[0].quote, "b3BhcXVl");
}

#[tokio::test]
async fn test_grpc_prepare_chunk_upload_with_options_maps_signed_quotes() {
    let client = start_mock_server().await;
    let opts = PrepareOptions {
        visibility: None,
        include_signed_quotes: true,
    };
    let r = client
        .prepare_chunk_upload_with_options(b"newchunk", &opts)
        .await
        .unwrap();
    assert_eq!(r.upload_id, "upid_chunk_42");
    assert_eq!(r.signed_quotes.len(), 1);
    assert_eq!(r.signed_quotes[0].quote_hash, "0xq1");
    assert_eq!(r.signed_quotes[0].quote, "b3BhcXVl");
}

#[tokio::test]
async fn test_grpc_verify_quotes_maps_verdicts() {
    let client = start_mock_server().await;
    // Base64 strings in, decoded to raw bytes on the wire ("opaque"
    // verifies, "opaque2" does not).
    let res = client
        .verify_quotes(&[
            VerifyQuoteEntry {
                quote_hash: "qh1".into(),
                rewards_address: "ra1".into(),
                amount: "5".into(),
                signed_quote: "b3BhcXVl".into(),
                commitment_sidecar: Some("c2lkZQ==".into()),
            },
            VerifyQuoteEntry {
                quote_hash: "qh2".into(),
                rewards_address: "ra2".into(),
                amount: "6".into(),
                signed_quote: "b3BhcXVlMg==".into(),
                commitment_sidecar: None,
            },
        ])
        .await
        .unwrap();
    assert!(!res.valid);
    assert_eq!(res.entries.len(), 2);
    let first = &res.entries[0];
    assert!(first.valid);
    assert!(first.quote_decoded());
    assert_eq!(first.error, None);
    assert_eq!(first.committed_key_count, Some(42));
    assert_eq!(first.pinned, Some(true));
    assert_eq!(first.timestamp_unix_secs, Some(1_756_000_000));
    assert_eq!(first.rewards_address.as_deref(), Some("ra1"));
    let second = &res.entries[1];
    assert!(!second.valid);
    assert!(!second.quote_decoded());
    assert!(second
        .error
        .as_deref()
        .unwrap()
        .contains("did not deserialize"));
    // Nothing decoded: the extracted fields are absent, as on REST.
    assert_eq!(second.content, None);
    assert_eq!(second.pinned, None);
}

#[tokio::test]
async fn test_grpc_verify_quotes_round_trips_prepared_entries() {
    // A signed quote obtained over gRPC (base64-encoded into the model) must
    // feed verify_quotes unchanged and verify.
    let client = start_mock_server().await;
    let opts = PrepareOptions {
        visibility: None,
        include_signed_quotes: true,
    };
    let prep = client
        .prepare_upload_with_options("/tmp/x.bin", &opts)
        .await
        .unwrap();
    let sq = &prep.signed_quotes[0];
    let res = client
        .verify_quotes(&[VerifyQuoteEntry {
            quote_hash: sq.quote_hash.clone(),
            rewards_address: prep.payments[0].rewards_address.clone(),
            amount: prep.payments[0].amount.clone(),
            signed_quote: sq.quote.clone(),
            commitment_sidecar: sq.commitment_sidecar.clone(),
        }])
        .await
        .unwrap();
    assert!(res.valid);
    assert_eq!(res.entries.len(), 1);
    assert_eq!(res.entries[0].pinned, Some(true));
}

#[tokio::test]
async fn test_grpc_verify_quotes_rejects_malformed_base64_before_sending() {
    let client = start_mock_server().await;
    let err = client
        .verify_quotes(&[VerifyQuoteEntry {
            quote_hash: "qh1".into(),
            signed_quote: "not base64!".into(),
            ..Default::default()
        }])
        .await
        .unwrap_err();
    assert!(
        matches!(&err, AntdError::BadRequest(m) if m.contains("signed_quote is not valid base64")),
        "got {err:?}"
    );
    let err = client
        .verify_quotes(&[VerifyQuoteEntry {
            quote_hash: "qh1".into(),
            signed_quote: "b3BhcXVl".into(),
            commitment_sidecar: Some("%%%".into()),
            ..Default::default()
        }])
        .await
        .unwrap_err();
    assert!(
        matches!(&err, AntdError::BadRequest(m) if m.contains("commitment_sidecar is not valid base64")),
        "got {err:?}"
    );
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
async fn test_grpc_partial_upload_maps_to_partial_upload() {
    let client = start_mock_server().await;
    let err = client
        .finalize_merkle_upload("partial", "0xw1", false)
        .await
        .unwrap_err();
    // Counts and the retained hint are parsed from the status message, so
    // the gRPC client matches the REST client's typed error.
    match err {
        AntdError::PartialUpload {
            chunks_stored,
            chunks_failed,
            total_chunks,
            retryable,
            retention_known,
            message,
        } => {
            assert_eq!((chunks_stored, chunks_failed, total_chunks), (300, 12, 312));
            assert!(retryable, "expected retryable from the retained hint");
            assert!(retention_known, "the retained hint establishes retention");
            assert!(message.starts_with("Partial upload: 300/312"), "{message}");
        }
        other => panic!("expected AntdError::PartialUpload, got: {other:?}"),
    }

    let err = client
        .finalize_merkle_upload("partial-final", "0xw1", false)
        .await
        .unwrap_err();
    match err {
        AntdError::PartialUpload {
            chunks_stored,
            chunks_failed,
            total_chunks,
            retryable,
            retention_known,
            ..
        } => {
            assert_eq!((chunks_stored, chunks_failed, total_chunks), (300, 12, 312));
            assert!(
                !retryable,
                "the not-retained hint must read as not retryable"
            );
            assert!(
                retention_known,
                "the not-retained hint confirms nothing was retained"
            );
        }
        other => panic!("expected AntdError::PartialUpload, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_grpc_partial_upload_unreadable_hint_is_unknown_retention() {
    // Readable counts without a readable retention hint (none at all, or the
    // review's truncated `(paid attempt retai`): the daemon's answer was not
    // read, so retention is unknown (stop and reconcile), never "nothing
    // retained" (re-prepare). The counts still read.
    let client = start_mock_server().await;
    let tx_hashes = std::collections::HashMap::from([("0xq".to_string(), "0xtx".to_string())]);
    for id in ["partial-no-hint", "partial-truncated-hint"] {
        match client.finalize_upload(id, &tx_hashes).await.unwrap_err() {
            AntdError::PartialUpload {
                chunks_stored,
                chunks_failed,
                total_chunks,
                retryable,
                retention_known,
                message,
            } => {
                assert_eq!(
                    (chunks_stored, chunks_failed, total_chunks),
                    (1, 2, 3),
                    "{id}: the counts should still read"
                );
                assert!(!retryable, "{id}: an unreadable hint must not enable retry");
                assert!(
                    !retention_known,
                    "{id}: retention must be unknown, not confirmed non-retention"
                );
                assert!(
                    message.starts_with("Partial upload: 1/3"),
                    "{id}: {message}"
                );
            }
            other => panic!("{id}: expected AntdError::PartialUpload, got: {other:?}"),
        }
    }
}

#[tokio::test]
async fn test_grpc_error_aborted_unrecognised_message() {
    // ABORTED is a partial store only when the message carries the daemon's
    // fixed `Partial upload:` prefix; any other ABORTED keeps the generic
    // gRPC mapping instead of being misreported as a partial upload.
    let client = start_error_server(tonic::Code::Aborted, "aborted").await;
    let err = client.health().await.unwrap_err();
    match err {
        AntdError::Grpc(status) => {
            assert_eq!(status.code(), tonic::Code::Aborted);
            assert_eq!(status.message(), "aborted");
        }
        other => panic!("expected AntdError::Grpc, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_grpc_error_aborted_embedded_marker_stays_grpc() {
    // The gate is anchored at the start of the message: a `Partial upload:`
    // marker quoted inside some other ABORTED text — even one carrying the
    // retained hint — must not select paid-attempt recovery with zero counts.
    let embedded = "operation aborted; previous error: Partial upload: 3/5 chunks stored, \
                    2 failed (paid attempt retained)";
    let client = start_error_server(tonic::Code::Aborted, embedded).await;
    let err = client.health().await.unwrap_err();
    match err {
        AntdError::Grpc(status) => {
            assert_eq!(status.code(), tonic::Code::Aborted);
            assert_eq!(status.message(), embedded);
        }
        other => panic!("expected AntdError::Grpc, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_grpc_error_aborted_partial_prefix_garbled_counts() {
    // The prefix alone is enough to classify the status as a partial store;
    // counts that fail to parse read as zero, `retryable` as false, and
    // retention as unknown.
    let client = start_error_server(tonic::Code::Aborted, "Partial upload: n/a chunks").await;
    let err = client.health().await.unwrap_err();
    match err {
        AntdError::PartialUpload {
            chunks_stored,
            chunks_failed,
            total_chunks,
            retryable,
            retention_known,
            message,
        } => {
            assert_eq!((chunks_stored, chunks_failed, total_chunks), (0, 0, 0));
            assert!(!retryable);
            assert!(!retention_known);
            assert_eq!(message, "Partial upload: n/a chunks");
        }
        other => panic!("expected AntdError::PartialUpload, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_grpc_error_aborted_partial_invalid_counts_with_hint_unknown_retention() {
    // The counts gate retention: a `Partial upload:` status whose counts do
    // not parse, or overflow u64 in any position, is still a partial store,
    // but reads as zero counts, not retryable and retention unknown, even
    // with the retained hint.
    let over = "18446744073709551616"; // u64::MAX + 1
    let msgs = [
        "Partial upload: 300/312 chunks (paid attempt retained)".to_string(),
        format!("Partial upload: {over}/312 chunks stored, 12 failed (paid attempt retained)"),
        format!("Partial upload: 300/{over} chunks stored, 12 failed (paid attempt retained)"),
        format!("Partial upload: 300/312 chunks stored, {over} failed (paid attempt retained)"),
    ];
    for msg in msgs {
        let client = start_error_server(tonic::Code::Aborted, &msg).await;
        match client.health().await.unwrap_err() {
            AntdError::PartialUpload {
                chunks_stored,
                chunks_failed,
                total_chunks,
                retryable,
                retention_known,
                message,
            } => {
                assert_eq!(
                    (chunks_stored, chunks_failed, total_chunks),
                    (0, 0, 0),
                    "{msg}"
                );
                assert!(!retryable, "invalid counts must not enable retry: {msg}");
                assert!(
                    !retention_known,
                    "invalid counts must leave retention unknown: {msg}"
                );
                assert_eq!(message, msg);
            }
            other => panic!("expected AntdError::PartialUpload for {msg}, got: {other:?}"),
        }
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

// --- V2-286: WalletService ---

#[derive(Default)]
struct MockWalletService;

#[tonic::async_trait]
impl v1::wallet_service_server::WalletService for MockWalletService {
    async fn get_address(
        &self,
        _request: Request<v1::GetWalletAddressRequest>,
    ) -> Result<Response<v1::GetWalletAddressResponse>, Status> {
        Ok(Response::new(v1::GetWalletAddressResponse {
            address: "0xabc1234567890abcdef1234567890abcdef123456".to_string(),
        }))
    }

    async fn get_balance(
        &self,
        _request: Request<v1::GetWalletBalanceRequest>,
    ) -> Result<Response<v1::GetWalletBalanceResponse>, Status> {
        Ok(Response::new(v1::GetWalletBalanceResponse {
            balance: "1000000000000000000".to_string(),
            gas_balance: "500000000000000000".to_string(),
        }))
    }

    async fn approve(
        &self,
        _request: Request<v1::WalletApproveRequest>,
    ) -> Result<Response<v1::WalletApproveResponse>, Status> {
        Ok(Response::new(v1::WalletApproveResponse { approved: true }))
    }
}

/// Spins a mock server with MockWalletService alongside the existing mocks
/// and dials with a real GrpcClient. Mirrors `start_mock_server` but adds
/// the wallet service so the V2-286 tests can target it.
async fn start_wallet_mock_server() -> GrpcClient {
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
            .add_service(v1::wallet_service_server::WalletServiceServer::new(
                MockWalletService,
            ))
            .serve_with_incoming(incoming)
            .await
            .unwrap();
    });

    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    GrpcClient::new(&format!("http://{addr}")).await.unwrap()
}

#[tokio::test]
async fn test_wallet_address_returns_address() {
    let client = start_wallet_mock_server().await;
    let r = client.wallet_address().await.unwrap();
    assert_eq!(r.address, "0xabc1234567890abcdef1234567890abcdef123456");
}

#[tokio::test]
async fn test_wallet_balance_returns_balances() {
    let client = start_wallet_mock_server().await;
    let r = client.wallet_balance().await.unwrap();
    assert_eq!(r.balance, "1000000000000000000");
    assert_eq!(r.gas_balance, "500000000000000000");
}

#[tokio::test]
async fn test_wallet_approve_returns_true() {
    let client = start_wallet_mock_server().await;
    let approved = client.wallet_approve().await.unwrap();
    assert!(approved);
}

/// Failed-precondition path: daemon without a configured wallet returns
/// gRPC FailedPrecondition. The client surfaces it as AntdError::Grpc with
/// that code.
struct UnconfiguredWalletService;

#[tonic::async_trait]
impl v1::wallet_service_server::WalletService for UnconfiguredWalletService {
    async fn get_address(
        &self,
        _request: Request<v1::GetWalletAddressRequest>,
    ) -> Result<Response<v1::GetWalletAddressResponse>, Status> {
        Err(Status::failed_precondition(
            "wallet not configured — set AUTONOMI_WALLET_KEY",
        ))
    }

    async fn get_balance(
        &self,
        _request: Request<v1::GetWalletBalanceRequest>,
    ) -> Result<Response<v1::GetWalletBalanceResponse>, Status> {
        Err(Status::failed_precondition(
            "wallet not configured — set AUTONOMI_WALLET_KEY",
        ))
    }

    async fn approve(
        &self,
        _request: Request<v1::WalletApproveRequest>,
    ) -> Result<Response<v1::WalletApproveResponse>, Status> {
        Err(Status::failed_precondition(
            "wallet not configured — set AUTONOMI_WALLET_KEY",
        ))
    }
}

async fn start_unconfigured_wallet_server() -> GrpcClient {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        let incoming = tokio_stream::wrappers::TcpListenerStream::new(listener);
        Server::builder()
            .add_service(v1::wallet_service_server::WalletServiceServer::new(
                UnconfiguredWalletService,
            ))
            .serve_with_incoming(incoming)
            .await
            .unwrap();
    });

    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    GrpcClient::new(&format!("http://{addr}")).await.unwrap()
}

#[tokio::test]
async fn test_wallet_address_unconfigured_returns_failed_precondition() {
    let client = start_unconfigured_wallet_server().await;
    let err = client.wallet_address().await.unwrap_err();
    match err {
        AntdError::Grpc(status) => {
            assert_eq!(status.code(), tonic::Code::FailedPrecondition);
            assert!(status.message().contains("wallet not configured"));
        }
        other => panic!("expected AntdError::Grpc, got: {other:?}"),
    }
}
