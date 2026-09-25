use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use bytes::Bytes;
use futures_core::Stream;
use tokio_stream::StreamExt;
use tonic::transport::{Channel, Endpoint};

use crate::discover::discover_grpc_target;
use crate::errors::AntdError;
use crate::models::*;

/// Generated protobuf types for the antd gRPC API.
// tonic's generated client methods return Result<_, tonic::Status> (~176
// bytes), which trips clippy::result_large_err on rustc >= 1.98; the
// signatures aren't ours to change.
#[allow(clippy::result_large_err)]
pub mod proto {
    pub mod antd {
        pub mod v1 {
            // Committed output of tonic-build over ../antd/proto (see
            // tests/proto_drift.rs); consumers need neither the protos nor protoc.
            include!("generated/antd.v1.rs");
        }
    }
}

use proto::antd::v1::{
    chunk_service_client::ChunkServiceClient, data_service_client::DataServiceClient,
    file_service_client::FileServiceClient, health_service_client::HealthServiceClient,
    upload_service_client::UploadServiceClient, verify_service_client::VerifyServiceClient,
    wallet_service_client::WalletServiceClient,
};

/// Default gRPC endpoint of the antd daemon.
pub const DEFAULT_GRPC_ENDPOINT: &str = "http://localhost:50051";

/// Default ceiling on a single gRPC response message the client will decode
/// (32 MiB). tonic's own default is 4 MiB, which a prepare response carrying
/// signed quotes can exceed: each entry is ~5-6 KB of quote plus up to 8 KB
/// of commitment sidecar, so a large wave-batch prepare (ant-core falls back
/// from merkle to wave on `InsufficientPeers` with the whole pending chunk
/// set) can be 8 MiB or more. The ceiling matches the daemon's own
/// `VerifyService` message limit, which is sized to 1024 maximal entries.
/// Override with [`GrpcClient::connect_with_max_message_size`].
pub const DEFAULT_MAX_RECV_MESSAGE_BYTES: usize = 32 * 1024 * 1024;

/// Extract the plaintext bytes of a `DataChunk`, or `None` if the frame is a
/// progress update (or empty). Used by the non-progress stream methods to drop
/// any stray progress frames and yield only data bytes.
fn data_bytes_of(chunk: proto::antd::v1::DataChunk) -> Option<Bytes> {
    match chunk.kind {
        Some(proto::antd::v1::data_chunk::Kind::Data(d)) => Some(Bytes::from(d)),
        _ => None,
    }
}

/// Map a wire `DataChunk` onto the public [`DownloadFrame`]. A frame with no
/// `kind` set (shouldn't occur) is treated as an empty data chunk.
fn frame_of(chunk: proto::antd::v1::DataChunk) -> DownloadFrame {
    match chunk.kind {
        Some(proto::antd::v1::data_chunk::Kind::Progress(p)) => {
            DownloadFrame::Progress(DownloadProgress {
                phase: p.phase,
                fetched: p.fetched,
                total: p.total,
            })
        }
        Some(proto::antd::v1::data_chunk::Kind::Data(d)) => DownloadFrame::Data(Bytes::from(d)),
        None => DownloadFrame::Data(Bytes::new()),
    }
}

/// Read the total download size from a stream response's `x-content-length`
/// metadata and wrap it as a leading [`DownloadFrame::Meta`]. Returns `None`
/// when the header is absent or unparseable (older daemons), so the caller
/// simply yields no Meta frame.
fn meta_frame_of(
    metadata: &tonic::metadata::MetadataMap,
) -> Option<Result<DownloadFrame, AntdError>> {
    metadata
        .get("x-content-length")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<u64>().ok())
        .map(|total| Ok(DownloadFrame::Meta(total)))
}

/// gRPC client for the antd daemon.
///
/// Provides the same async methods as [`crate::Client`] but communicates
/// over gRPC instead of REST/JSON.
#[derive(Debug, Clone)]
pub struct GrpcClient {
    health: HealthServiceClient<Channel>,
    data: DataServiceClient<Channel>,
    chunks: ChunkServiceClient<Channel>,
    files: FileServiceClient<Channel>,
    upload: UploadServiceClient<Channel>,
    wallet: WalletServiceClient<Channel>,
    verify: VerifyServiceClient<Channel>,
}

impl GrpcClient {
    /// Creates a new gRPC client connected to the given endpoint.
    ///
    /// This is an alias for [`GrpcClient::connect`].
    pub async fn new(endpoint: &str) -> Result<Self, AntdError> {
        Self::connect(endpoint).await
    }

    /// Creates a gRPC client by auto-discovering the daemon port file,
    /// falling back to [`DEFAULT_GRPC_ENDPOINT`] if discovery fails.
    pub async fn auto_discover() -> Result<Self, AntdError> {
        let endpoint = discover_grpc_target().unwrap_or_else(|| DEFAULT_GRPC_ENDPOINT.to_string());
        Self::connect(&endpoint).await
    }

    /// Connects to the antd gRPC server at the given endpoint with the
    /// [`DEFAULT_MAX_RECV_MESSAGE_BYTES`] response ceiling.
    pub async fn connect(endpoint: &str) -> Result<Self, AntdError> {
        Self::connect_with_max_message_size(endpoint, DEFAULT_MAX_RECV_MESSAGE_BYTES).await
    }

    /// [`connect`](Self::connect) with an explicit ceiling, in bytes, on a
    /// single response message. Responses over the ceiling fail with an
    /// `OutOfRange` status ([`AntdError::Grpc`]) rather than being
    /// truncated. Applied to every service client so the bound is uniform.
    pub async fn connect_with_max_message_size(
        endpoint: &str,
        max_recv_message_bytes: usize,
    ) -> Result<Self, AntdError> {
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| AntdError::Internal(format!("invalid endpoint: {e}")))?
            .connect()
            .await
            .map_err(|e| AntdError::Internal(format!("grpc connect: {e}")))?;

        let n = max_recv_message_bytes;
        Ok(Self {
            health: HealthServiceClient::new(channel.clone()).max_decoding_message_size(n),
            data: DataServiceClient::new(channel.clone()).max_decoding_message_size(n),
            chunks: ChunkServiceClient::new(channel.clone()).max_decoding_message_size(n),
            files: FileServiceClient::new(channel.clone()).max_decoding_message_size(n),
            upload: UploadServiceClient::new(channel.clone()).max_decoding_message_size(n),
            wallet: WalletServiceClient::new(channel.clone()).max_decoding_message_size(n),
            verify: VerifyServiceClient::new(channel).max_decoding_message_size(n),
        })
    }

    // --- Health ---

    /// Checks the antd daemon status.
    pub async fn health(&self) -> Result<HealthStatus, AntdError> {
        let resp = self
            .health
            .clone()
            .check(proto::antd::v1::HealthCheckRequest {})
            .await?
            .into_inner();

        Ok(HealthStatus {
            ok: resp.status == "ok",
            network: resp.network,
            version: resp.version,
            evm_network: resp.evm_network,
            uptime_seconds: resp.uptime_seconds,
            build_commit: resp.build_commit,
            payment_token_address: resp.payment_token_address,
            payment_vault_address: resp.payment_vault_address,
            write_ready: resp.write_ready,
            connected_peers: resp.connected_peers,
            routing_table_size: resp.routing_table_size,
            rebootstrap_threshold: resp.rebootstrap_threshold,
            last_store_ok_secs_ago: resp.last_store_ok_secs_ago,
        })
    }

    // --- Data ---

    /// Stores private encrypted data. Returns the caller-held DataMap (hex).
    pub async fn data_put(
        &self,
        data: &[u8],
        payment_mode: PaymentMode,
    ) -> Result<DataPutResult, AntdError> {
        let resp = self
            .data
            .clone()
            .put(proto::antd::v1::PutDataRequest {
                data: data.to_vec(),
                payment_mode: payment_mode.as_wire().to_string(),
            })
            .await?
            .into_inner();

        Ok(DataPutResult {
            data_map: resp.data_map,
            chunks_stored: resp.chunks_stored,
            payment_mode_used: resp.payment_mode_used,
        })
    }

    /// Retrieves private data from a caller-held DataMap (hex).
    pub async fn data_get(&self, data_map: &str) -> Result<Vec<u8>, AntdError> {
        let resp = self
            .data
            .clone()
            .get(proto::antd::v1::GetDataRequest {
                data_map: data_map.to_string(),
            })
            .await?
            .into_inner();

        Ok(resp.data)
    }

    /// Stores public data. Returns the on-network DataMap address.
    pub async fn data_put_public(
        &self,
        data: &[u8],
        payment_mode: PaymentMode,
    ) -> Result<DataPutPublicResult, AntdError> {
        let resp = self
            .data
            .clone()
            .put_public(proto::antd::v1::PutPublicDataRequest {
                data: data.to_vec(),
                payment_mode: payment_mode.as_wire().to_string(),
            })
            .await?
            .into_inner();

        Ok(DataPutPublicResult {
            address: resp.address,
            chunks_stored: resp.chunks_stored,
            payment_mode_used: resp.payment_mode_used,
        })
    }

    /// Retrieves public data by address.
    pub async fn data_get_public(&self, address: &str) -> Result<Vec<u8>, AntdError> {
        let resp = self
            .data
            .clone()
            .get_public(proto::antd::v1::GetPublicDataRequest {
                address: address.to_string(),
            })
            .await?
            .into_inner();

        Ok(resp.data)
    }

    /// Streams private data from a caller-held DataMap (hex), one decrypt
    /// batch at a time, instead of buffering the whole object in memory.
    ///
    /// The gRPC counterpart to [`data_get`](Self::data_get) and mirror of the
    /// REST client's [`data_stream`](crate::Client::data_stream): returns an
    /// async [`Stream`] of [`Bytes`] chunks the caller consumes incrementally.
    pub async fn data_stream(
        &self,
        data_map: &str,
    ) -> Result<impl Stream<Item = Result<Bytes, AntdError>>, AntdError> {
        let stream = self
            .data
            .clone()
            .stream(proto::antd::v1::StreamDataRequest {
                data_map: data_map.to_string(),
                include_progress: false,
            })
            .await?
            .into_inner();

        Ok(stream.filter_map(|item| match item {
            Ok(chunk) => data_bytes_of(chunk).map(Ok),
            Err(e) => Some(Err(AntdError::from(e))),
        }))
    }

    /// Streams public data by address — the gRPC counterpart to
    /// [`data_get_public`](Self::data_get_public). Returns an async [`Stream`]
    /// of [`Bytes`] chunks consumed incrementally (constant memory).
    pub async fn data_stream_public(
        &self,
        address: &str,
    ) -> Result<impl Stream<Item = Result<Bytes, AntdError>>, AntdError> {
        let stream = self
            .data
            .clone()
            .stream_public(proto::antd::v1::StreamPublicDataRequest {
                address: address.to_string(),
                include_progress: false,
            })
            .await?
            .into_inner();

        Ok(stream.filter_map(|item| match item {
            Ok(chunk) => data_bytes_of(chunk).map(Ok),
            Err(e) => Some(Err(AntdError::from(e))),
        }))
    }

    /// Like [`data_stream`](Self::data_stream) but requests interleaved
    /// fetch-progress frames so the caller can drive a *determinate* progress
    /// bar. Each item is a [`DownloadFrame`] — either a plaintext [`Bytes`]
    /// chunk ([`DownloadFrame::Data`]) or a [`DownloadProgress`] update
    /// ([`DownloadFrame::Progress`]). The byte denominator is surfaced as a
    /// leading [`DownloadFrame::Meta`], read from the response's
    /// `x-content-length` metadata.
    pub async fn data_stream_with_progress(
        &self,
        data_map: &str,
    ) -> Result<impl Stream<Item = Result<DownloadFrame, AntdError>>, AntdError> {
        let response = self
            .data
            .clone()
            .stream(proto::antd::v1::StreamDataRequest {
                data_map: data_map.to_string(),
                include_progress: true,
            })
            .await?;

        let meta = meta_frame_of(response.metadata());
        let stream = response
            .into_inner()
            .map(|item| item.map(frame_of).map_err(AntdError::from));

        Ok(tokio_stream::iter(meta).chain(stream))
    }

    /// Like [`data_stream_public`](Self::data_stream_public) but requests
    /// interleaved fetch-progress frames. See
    /// [`data_stream_with_progress`](Self::data_stream_with_progress).
    pub async fn data_stream_public_with_progress(
        &self,
        address: &str,
    ) -> Result<impl Stream<Item = Result<DownloadFrame, AntdError>>, AntdError> {
        let response = self
            .data
            .clone()
            .stream_public(proto::antd::v1::StreamPublicDataRequest {
                address: address.to_string(),
                include_progress: true,
            })
            .await?;

        let meta = meta_frame_of(response.metadata());
        let stream = response
            .into_inner()
            .map(|item| item.map(frame_of).map_err(AntdError::from));

        Ok(tokio_stream::iter(meta).chain(stream))
    }

    /// Pre-upload cost breakdown for the given bytes.
    pub async fn data_cost(
        &self,
        data: &[u8],
        payment_mode: PaymentMode,
    ) -> Result<UploadCostEstimate, AntdError> {
        let resp = self
            .data
            .clone()
            .cost(proto::antd::v1::DataCostRequest {
                data: data.to_vec(),
                payment_mode: payment_mode.as_wire().to_string(),
            })
            .await?
            .into_inner();

        Ok(UploadCostEstimate {
            cost: resp.atto_tokens,
            file_size: resp.file_size,
            chunk_count: resp.chunk_count,
            estimated_gas_cost_wei: resp.estimated_gas_cost_wei,
            payment_mode: resp.payment_mode,
        })
    }

    // --- Chunks ---

    /// Stores a raw chunk on the network.
    pub async fn chunk_put(&self, data: &[u8]) -> Result<PutResult, AntdError> {
        let resp = self
            .chunks
            .clone()
            .put(proto::antd::v1::PutChunkRequest {
                data: data.to_vec(),
            })
            .await?
            .into_inner();

        let cost = resp.cost.map(|c| c.atto_tokens).unwrap_or_default();

        Ok(PutResult {
            cost,
            address: resp.address,
        })
    }

    /// Retrieves a chunk by address.
    pub async fn chunk_get(&self, address: &str) -> Result<Vec<u8>, AntdError> {
        let resp = self
            .chunks
            .clone()
            .get(proto::antd::v1::GetChunkRequest {
                address: address.to_string(),
            })
            .await?
            .into_inner();

        Ok(resp.data)
    }

    /// Prepares a single chunk for external-signer publish.
    ///
    /// Mirrors [`crate::Client::prepare_chunk_upload`]. Either the chunk is
    /// already on-network ([`PrepareChunkResult::already_stored`] = `true`,
    /// other fields empty) or returns wave-batch payment details for
    /// `payForQuotes()`.
    ///
    /// Unlike [`chunk_put`](Self::chunk_put), does NOT require the daemon
    /// to have a wallet — funds flow through the external signer.
    ///
    /// Requires antd >= 0.9.0.
    pub async fn prepare_chunk_upload(&self, data: &[u8]) -> Result<PrepareChunkResult, AntdError> {
        self.prepare_chunk_upload_with_options(data, &PrepareOptions::default())
            .await
    }

    /// [`prepare_chunk_upload`](Self::prepare_chunk_upload) with explicit
    /// [`PrepareOptions`]. Mirrors
    /// [`crate::Client::prepare_chunk_upload_with_options`].
    pub async fn prepare_chunk_upload_with_options(
        &self,
        data: &[u8],
        opts: &PrepareOptions,
    ) -> Result<PrepareChunkResult, AntdError> {
        let resp = self
            .chunks
            .clone()
            .prepare_chunk(proto::antd::v1::PrepareChunkRequest {
                data: data.to_vec(),
                include_signed_quotes: opts.include_signed_quotes,
            })
            .await?
            .into_inner();

        Ok(PrepareChunkResult {
            address: resp.address,
            already_stored: resp.already_stored,
            upload_id: resp.upload_id,
            payment_type: resp.payment_type,
            payments: resp
                .payments
                .into_iter()
                .map(payment_entry_to_info)
                .collect(),
            total_amount: resp.total_amount,
            payment_vault_address: resp.payment_vault_address,
            payment_token_address: resp.payment_token_address,
            rpc_url: resp.rpc_url,
            signed_quotes: resp
                .signed_quotes
                .into_iter()
                .map(signed_quote_entry_to_model)
                .collect(),
        })
    }

    /// Submits a prepared chunk to the network after external payment.
    ///
    /// Mirrors [`crate::Client::finalize_chunk_upload`]. Returns the network
    /// address of the stored chunk (matches
    /// [`PrepareChunkResult::address`]).
    ///
    /// A partial store (gRPC `ABORTED` whose message starts with
    /// `Partial upload:`) surfaces as [`AntdError::PartialUpload`] with the
    /// counts, `retryable` and `retention_known` parsed from the status
    /// message; counts that do not parse leave retention unknown. The
    /// recovery contract is the same as over REST. Any other `ABORTED` stays
    /// [`AntdError::Grpc`].
    ///
    /// Requires antd >= 0.9.0.
    pub async fn finalize_chunk_upload(
        &self,
        upload_id: &str,
        tx_hashes: &std::collections::HashMap<String, String>,
    ) -> Result<String, AntdError> {
        let resp = self
            .chunks
            .clone()
            .finalize_chunk(proto::antd::v1::FinalizeChunkRequest {
                upload_id: upload_id.to_string(),
                tx_hashes: tx_hashes.clone(),
            })
            .await?
            .into_inner();

        Ok(resp.address)
    }

    // --- Files ---

    /// Uploads a file privately. Returns the caller-held DataMap (hex).
    pub async fn file_put(
        &self,
        path: &str,
        payment_mode: PaymentMode,
    ) -> Result<FilePutResult, AntdError> {
        let resp = self
            .files
            .clone()
            .put(proto::antd::v1::PutFileRequest {
                path: path.to_string(),
                payment_mode: payment_mode.as_wire().to_string(),
            })
            .await?
            .into_inner();

        Ok(FilePutResult {
            data_map: resp.data_map,
            storage_cost_atto: resp.storage_cost_atto,
            gas_cost_wei: resp.gas_cost_wei,
            chunks_stored: resp.chunks_stored,
            payment_mode_used: resp.payment_mode_used,
        })
    }

    /// Downloads a private file from a caller-held DataMap.
    pub async fn file_get(&self, data_map: &str, dest_path: &str) -> Result<(), AntdError> {
        self.files
            .clone()
            .get(proto::antd::v1::GetFileRequest {
                data_map: data_map.to_string(),
                dest_path: dest_path.to_string(),
            })
            .await?;
        Ok(())
    }

    /// Uploads a file publicly. Returns the on-network DataMap address.
    pub async fn file_put_public(
        &self,
        path: &str,
        payment_mode: PaymentMode,
    ) -> Result<FilePutPublicResult, AntdError> {
        let resp = self
            .files
            .clone()
            .put_public(proto::antd::v1::PutFileRequest {
                path: path.to_string(),
                payment_mode: payment_mode.as_wire().to_string(),
            })
            .await?
            .into_inner();

        Ok(FilePutPublicResult {
            address: resp.address,
            storage_cost_atto: resp.storage_cost_atto,
            gas_cost_wei: resp.gas_cost_wei,
            chunks_stored: resp.chunks_stored,
            payment_mode_used: resp.payment_mode_used,
        })
    }

    /// Downloads a public file from an on-network DataMap address.
    pub async fn file_get_public(&self, address: &str, dest_path: &str) -> Result<(), AntdError> {
        self.files
            .clone()
            .get_public(proto::antd::v1::GetFilePublicRequest {
                address: address.to_string(),
                dest_path: dest_path.to_string(),
            })
            .await?;

        Ok(())
    }

    /// Pre-upload cost breakdown for the file at `path`.
    pub async fn file_cost(
        &self,
        path: &str,
        is_public: bool,
        payment_mode: PaymentMode,
    ) -> Result<UploadCostEstimate, AntdError> {
        let resp = self
            .files
            .clone()
            .cost(proto::antd::v1::FileCostRequest {
                path: path.to_string(),
                is_public,
                payment_mode: payment_mode.as_wire().to_string(),
            })
            .await?
            .into_inner();

        Ok(UploadCostEstimate {
            cost: resp.atto_tokens,
            file_size: resp.file_size,
            chunk_count: resp.chunk_count,
            estimated_gas_cost_wei: resp.estimated_gas_cost_wei,
            payment_mode: resp.payment_mode,
        })
    }

    // --- Upload (external signer) ---

    /// Prepares a file upload for external signing.
    ///
    /// Mirrors [`crate::Client::prepare_upload`]. `visibility = Some("public")`
    /// bundles the DataMap chunk into the same external-signer payment batch;
    /// `None` / `Some("private")` keep it caller-held.
    ///
    /// Requires antd >= 0.9.0.
    pub async fn prepare_upload(
        &self,
        path: &str,
        visibility: Option<&str>,
    ) -> Result<PrepareUploadResult, AntdError> {
        self.prepare_upload_with_options(
            path,
            &PrepareOptions {
                visibility: visibility.map(str::to_string),
                include_signed_quotes: false,
            },
        )
        .await
    }

    /// [`prepare_upload`](Self::prepare_upload) with explicit
    /// [`PrepareOptions`]. Mirrors
    /// [`crate::Client::prepare_upload_with_options`]:
    /// `include_signed_quotes` populates
    /// [`PrepareUploadResult::signed_quotes`] for offline verification via
    /// [`verify_quotes`](Self::verify_quotes) (antd >= 0.13.0).
    pub async fn prepare_upload_with_options(
        &self,
        path: &str,
        opts: &PrepareOptions,
    ) -> Result<PrepareUploadResult, AntdError> {
        let resp = self
            .upload
            .clone()
            .prepare_file_upload(proto::antd::v1::PrepareFileUploadRequest {
                path: path.to_string(),
                visibility: opts.visibility.clone().unwrap_or_default(),
                include_signed_quotes: opts.include_signed_quotes,
            })
            .await?
            .into_inner();

        Ok(prepare_response_to_result(resp))
    }

    /// Convenience wrapper: prepares a *public* file upload for external
    /// signing. Equivalent to [`prepare_upload`](Self::prepare_upload) with
    /// `visibility = Some("public")`.
    ///
    /// Requires antd >= 0.9.0.
    pub async fn prepare_upload_public(
        &self,
        path: &str,
    ) -> Result<PrepareUploadResult, AntdError> {
        self.prepare_upload(path, Some("public")).await
    }

    /// Prepares an in-memory data upload for external signing.
    ///
    /// Mirrors [`crate::Client::prepare_data_upload`]. `visibility = Some("public")`
    /// bundles the DataMap chunk into the same external-signer payment batch.
    ///
    /// Requires antd >= 0.9.0.
    pub async fn prepare_data_upload(
        &self,
        data: &[u8],
        visibility: Option<&str>,
    ) -> Result<PrepareUploadResult, AntdError> {
        self.prepare_data_upload_with_options(
            data,
            &PrepareOptions {
                visibility: visibility.map(str::to_string),
                include_signed_quotes: false,
            },
        )
        .await
    }

    /// [`prepare_data_upload`](Self::prepare_data_upload) with explicit
    /// [`PrepareOptions`]. Mirrors
    /// [`crate::Client::prepare_data_upload_with_options`].
    pub async fn prepare_data_upload_with_options(
        &self,
        data: &[u8],
        opts: &PrepareOptions,
    ) -> Result<PrepareUploadResult, AntdError> {
        let resp = self
            .upload
            .clone()
            .prepare_data_upload(proto::antd::v1::PrepareDataUploadRequest {
                data: data.to_vec(),
                visibility: opts.visibility.clone().unwrap_or_default(),
                include_signed_quotes: opts.include_signed_quotes,
            })
            .await?
            .into_inner();

        Ok(prepare_response_to_result(resp))
    }

    /// Verifies a batch of signed quotes offline via `VerifyService`.
    ///
    /// Mirrors [`crate::Client::verify_quotes`]. Entries carry the base64
    /// strings from [`SignedQuoteEntry`] (either transport); they are
    /// decoded to the raw bytes the proto expects here, and an entry whose
    /// `signed_quote` or `commitment_sidecar` is not valid base64 fails the
    /// call with [`AntdError::BadRequest`] before anything is sent (on REST
    /// the daemon would return a per-entry invalid verdict for the same
    /// input).
    ///
    /// The daemon accepts at most 1024 entries per call. antd >= 0.13.1 sets
    /// the gRPC decode ceiling to admit a full batch; on 0.13.0 the gRPC
    /// side tops out around 600 real entries.
    ///
    /// Requires antd >= 0.13.0.
    pub async fn verify_quotes(
        &self,
        entries: &[VerifyQuoteEntry],
    ) -> Result<VerifyQuotesResult, AntdError> {
        let mut wire = Vec::with_capacity(entries.len());
        for (i, e) in entries.iter().enumerate() {
            let signed_quote = BASE64.decode(&e.signed_quote).map_err(|err| {
                AntdError::BadRequest(format!(
                    "verify_quotes entry {i} ({}): signed_quote is not valid base64: {err}",
                    e.quote_hash
                ))
            })?;
            let commitment_sidecar = match &e.commitment_sidecar {
                Some(b64) if !b64.is_empty() => BASE64.decode(b64).map_err(|err| {
                    AntdError::BadRequest(format!(
                        "verify_quotes entry {i} ({}): commitment_sidecar is not valid base64: {err}",
                        e.quote_hash
                    ))
                })?,
                _ => Vec::new(),
            };
            wire.push(proto::antd::v1::VerifyQuoteEntry {
                quote_hash: e.quote_hash.clone(),
                rewards_address: e.rewards_address.clone(),
                amount: e.amount.clone(),
                signed_quote,
                commitment_sidecar,
            });
        }

        let resp = self
            .verify
            .clone()
            .verify_quotes(proto::antd::v1::VerifyQuotesRequest { entries: wire })
            .await?
            .into_inner();

        Ok(VerifyQuotesResult {
            valid: resp.valid,
            entries: resp.entries.into_iter().map(verdict_to_model).collect(),
        })
    }

    /// Finalizes a wave-batch upload after the external signer has submitted
    /// `payForQuotes()` transactions.
    ///
    /// Mirrors [`crate::Client::finalize_upload`].
    ///
    /// A partial store (gRPC `ABORTED` whose message starts with
    /// `Partial upload:`) surfaces as [`AntdError::PartialUpload`] with the
    /// counts, `retryable` and `retention_known` parsed from the status
    /// message; counts that do not parse leave retention unknown. The
    /// recovery contract is the same as over REST. Any other `ABORTED` stays
    /// [`AntdError::Grpc`].
    ///
    /// Requires antd >= 0.9.0.
    pub async fn finalize_upload(
        &self,
        upload_id: &str,
        tx_hashes: &std::collections::HashMap<String, String>,
    ) -> Result<FinalizeUploadResult, AntdError> {
        let resp = self
            .upload
            .clone()
            .finalize_upload(proto::antd::v1::FinalizeUploadRequest {
                upload_id: upload_id.to_string(),
                tx_hashes: tx_hashes.clone(),
                winner_pool_hash: String::new(),
                winner_pool_hashes: Vec::new(),
                store_data_map: false,
            })
            .await?
            .into_inner();

        Ok(finalize_response_to_result(resp))
    }

    /// Finalizes a merkle-batch upload after the winning pool has been
    /// determined.
    ///
    /// Mirrors [`crate::Client::finalize_merkle_upload`].
    ///
    /// A partial store (gRPC `ABORTED` whose message starts with
    /// `Partial upload:`) surfaces as [`AntdError::PartialUpload`] with the
    /// counts, `retryable` and `retention_known` parsed from the status
    /// message; counts that do not parse leave retention unknown. The
    /// recovery contract is the same as over REST. Any other `ABORTED` stays
    /// [`AntdError::Grpc`].
    ///
    /// Requires antd >= 0.9.0.
    pub async fn finalize_merkle_upload(
        &self,
        upload_id: &str,
        winner_pool_hash: &str,
        store_data_map: bool,
    ) -> Result<FinalizeUploadResult, AntdError> {
        let resp = self
            .upload
            .clone()
            .finalize_upload(proto::antd::v1::FinalizeUploadRequest {
                upload_id: upload_id.to_string(),
                tx_hashes: std::collections::HashMap::new(),
                winner_pool_hash: winner_pool_hash.to_string(),
                // Legacy single-batch call shape; the multi-batch surface
                // (winner-hash list, merkle_batches consumption) is the
                // client-sweep follow-up.
                winner_pool_hashes: Vec::new(),
                store_data_map,
            })
            .await?
            .into_inner();

        Ok(finalize_response_to_result(resp))
    }
    // --- Wallet ---

    /// Returns the wallet address configured in the daemon.
    /// Returns `AntdError::ServiceUnavailable` if the daemon has no wallet
    /// configured (the daemon emits gRPC `FailedPrecondition` which maps to
    /// `ServiceUnavailable` in our error hierarchy).
    pub async fn wallet_address(&self) -> Result<WalletAddress, AntdError> {
        let resp = self
            .wallet
            .clone()
            .get_address(proto::antd::v1::GetWalletAddressRequest {})
            .await?
            .into_inner();
        Ok(WalletAddress {
            address: resp.address,
        })
    }

    /// Returns the wallet token + gas balances from the daemon.
    pub async fn wallet_balance(&self) -> Result<WalletBalance, AntdError> {
        let resp = self
            .wallet
            .clone()
            .get_balance(proto::antd::v1::GetWalletBalanceRequest {})
            .await?
            .into_inner();
        Ok(WalletBalance {
            balance: resp.balance,
            gas_balance: resp.gas_balance,
        })
    }

    /// Approves the wallet to spend tokens on payment contracts.
    /// One-time operation; idempotent at the contract level.
    pub async fn wallet_approve(&self) -> Result<bool, AntdError> {
        let resp = self
            .wallet
            .clone()
            .approve(proto::antd::v1::WalletApproveRequest {})
            .await?
            .into_inner();
        Ok(resp.approved)
    }
}

// --- proto → model conversions ---

fn payment_entry_to_info(p: proto::antd::v1::PaymentEntry) -> PaymentInfo {
    PaymentInfo {
        quote_hash: p.quote_hash,
        rewards_address: p.rewards_address,
        amount: p.amount,
    }
}

/// The proto carries the opaque msgpack blobs as raw bytes; the shared model
/// (also fed by REST, where they travel as JSON strings) carries them base64
/// so an entry obtained here feeds `verify_quotes` on either transport.
fn signed_quote_entry_to_model(e: proto::antd::v1::SignedQuoteEntry) -> SignedQuoteEntry {
    SignedQuoteEntry {
        quote_hash: e.quote_hash,
        quote: BASE64.encode(&e.quote),
        commitment_sidecar: (!e.commitment_sidecar.is_empty())
            .then(|| BASE64.encode(&e.commitment_sidecar)),
    }
}

/// proto3 scalars → the REST-shaped `Option` fields: the extracted fields are
/// meaningful only once the quote decoded, exactly as REST omits them.
fn verdict_to_model(v: proto::antd::v1::VerifyQuoteVerdict) -> VerifyQuoteVerdict {
    let decoded = v.quote_decoded;
    VerifyQuoteVerdict {
        quote_hash: v.quote_hash,
        valid: v.valid,
        error: (!v.error.is_empty()).then_some(v.error),
        timestamp_unix_secs: decoded.then_some(v.timestamp_unix_secs),
        content: decoded.then_some(v.content),
        price: decoded.then_some(v.price),
        rewards_address: decoded.then_some(v.rewards_address),
        committed_key_count: decoded.then_some(v.committed_key_count),
        pinned: decoded.then_some(v.pinned),
    }
}

fn prepare_response_to_result(resp: proto::antd::v1::PrepareUploadResponse) -> PrepareUploadResult {
    // gRPC proto3 uses scalar defaults rather than optional fields, so map
    // the merkle-only fields onto Option via "zero means absent" heuristic
    // that matches REST's omit-when-missing JSON shape.
    let payment_type = resp.payment_type;
    let is_merkle = payment_type == "merkle";

    PrepareUploadResult {
        upload_id: resp.upload_id,
        payments: resp
            .payments
            .into_iter()
            .map(payment_entry_to_info)
            .collect(),
        total_amount: resp.total_amount,
        payment_vault_address: resp.payment_vault_address,
        payment_token_address: resp.payment_token_address,
        rpc_url: resp.rpc_url,
        payment_type,
        depth: is_merkle.then_some(resp.depth as u8),
        pool_commitments: is_merkle.then(|| {
            resp.pool_commitments
                .into_iter()
                .map(|pc| PoolCommitmentEntry {
                    pool_hash: pc.pool_hash,
                    candidates: pc
                        .candidates
                        .into_iter()
                        .map(|c| CandidateNodeEntry {
                            rewards_address: c.rewards_address,
                            amount: c.amount,
                        })
                        .collect(),
                })
                .collect()
        }),
        merkle_payment_timestamp: is_merkle.then_some(resp.merkle_payment_timestamp),
        // Already-stored preflight (parity with REST): the external signer
        // pays for `total_chunks - already_stored_count` chunks.
        total_chunks: resp.total_chunks,
        already_stored_count: resp.already_stored_count,
        signed_quotes: resp
            .signed_quotes
            .into_iter()
            .map(signed_quote_entry_to_model)
            .collect(),
    }
}

fn finalize_response_to_result(
    resp: proto::antd::v1::FinalizeUploadResponse,
) -> FinalizeUploadResult {
    FinalizeUploadResult {
        data_map: resp.data_map,
        address: resp.address,
        data_map_address: resp.data_map_address,
        chunks_stored: resp.chunks_stored as i64,
    }
}
