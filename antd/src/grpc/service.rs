use std::path::PathBuf;
use std::sync::Arc;

use bytes::Bytes;
use tonic::{Request, Response, Status};

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::{
    adjust_for_public_upload, format_payment_mode, parse_payment_mode, parse_visibility,
};

// Generated protobuf modules
#[allow(dead_code)]
pub mod pb {
    tonic::include_proto!("antd.v1");
}

/// Parse a gRPC `string payment_mode` field, treating proto3's empty-string
/// default as "no preference" (Auto). Keeps REST's strict parse_payment_mode
/// unchanged — only the gRPC boundary needs to absorb the empty default that
/// old clients omitting the field will send. Returns `String` error so callers
/// convert to the (large) `Status` at the boundary.
fn parse_grpc_payment_mode(s: &str) -> Result<ant_core::data::PaymentMode, String> {
    let opt = if s.is_empty() { None } else { Some(s) };
    parse_payment_mode(opt)
}

/// Same shape as `parse_grpc_payment_mode` but for `string visibility`.
/// Empty default → `Visibility::Private` (matches REST's "field omitted ==
/// private" contract); non-empty values flow through the strict
/// `parse_visibility` parser which only accepts "private" / "public".
fn parse_grpc_visibility(s: &str) -> Result<ant_core::data::Visibility, String> {
    let opt = if s.is_empty() { None } else { Some(s) };
    parse_visibility(opt)
}

/// Mirror of REST's `build_prepare_response` (antd/src/rest/upload.rs) for the
/// gRPC wire shape. Same EVM-defaults resolution path; same wave-batch vs
/// merkle field split. Kept in sync with the REST helper — any changes to
/// `PreparedUpload` / `ExternalPaymentInfo` need to be reflected in both.
fn build_grpc_prepare_response(
    upload_id: String,
    prepared: &ant_core::data::PreparedUpload,
    network: &str,
) -> pb::PrepareUploadResponse {
    let evm_cfg = crate::evm_defaults::resolve(network);
    let rpc_url = evm_cfg.rpc_url;
    let payment_token_address = evm_cfg.token_addr;
    let payment_vault_address = evm_cfg.vault_addr;

    match &prepared.payment_info {
        ant_core::data::ExternalPaymentInfo::WaveBatch { payment_intent, .. } => {
            let payments: Vec<pb::PaymentEntry> = payment_intent
                .payments
                .iter()
                .map(|(quote_hash, rewards_addr, amount)| pb::PaymentEntry {
                    quote_hash: format!("{:#x}", quote_hash),
                    rewards_address: format!("{:#x}", rewards_addr),
                    amount: amount.to_string(),
                })
                .collect();

            pb::PrepareUploadResponse {
                upload_id,
                payment_type: "wave_batch".into(),
                payments,
                depth: 0,
                pool_commitments: Vec::new(),
                merkle_payment_timestamp: 0,
                total_amount: payment_intent.total_amount.to_string(),
                payment_vault_address,
                payment_token_address,
                rpc_url,
            }
        }
        ant_core::data::ExternalPaymentInfo::Merkle { prepared_batch, .. } => {
            let pool_commitments: Vec<pb::PoolCommitmentEntry> = prepared_batch
                .pool_commitments
                .iter()
                .map(|pc| pb::PoolCommitmentEntry {
                    pool_hash: format!("0x{}", hex::encode(pc.pool_hash)),
                    candidates: pc
                        .candidates
                        .iter()
                        .map(|c| pb::CandidateNodeEntry {
                            rewards_address: format!("0x{}", hex::encode(c.rewards_address)),
                            amount: c.price.to_string(),
                        })
                        .collect(),
                })
                .collect();

            pb::PrepareUploadResponse {
                upload_id,
                payment_type: "merkle".into(),
                payments: Vec::new(),
                depth: prepared_batch.depth as u32,
                pool_commitments,
                merkle_payment_timestamp: prepared_batch.merkle_payment_timestamp,
                total_amount: "0".into(),
                payment_vault_address,
                payment_token_address,
                rpc_url,
            }
        }
    }
}

// ── HealthService ──

pub struct HealthServiceImpl {
    pub state: Arc<AppState>,
}

#[tonic::async_trait]
impl pb::health_service_server::HealthService for HealthServiceImpl {
    async fn check(
        &self,
        _request: Request<pb::HealthCheckRequest>,
    ) -> Result<Response<pb::HealthCheckResponse>, Status> {
        Ok(Response::new(pb::HealthCheckResponse {
            status: "ok".into(),
            network: self.state.network.clone(),
            version: self.state.version.clone(),
            evm_network: self.state.evm_preset.clone(),
            uptime_seconds: self.state.started_at.elapsed().as_secs(),
            build_commit: self.state.build_commit.clone(),
            payment_token_address: self.state.evm_token_addr.clone(),
            payment_vault_address: self.state.evm_vault_addr.clone(),
        }))
    }
}

// ── DataService ──

pub struct DataServiceImpl {
    pub state: Arc<AppState>,
}

/// Spawn a constant-memory streaming download from `data_map` and return the
/// gRPC response stream. `file_download_to_sender` runs on a background task and
/// emits each decrypted batch as a `DataChunk`; a terminal ant-core error is
/// forwarded as the stream's final `Err(Status)` (after any chunks already
/// sent), closing the server-stream with that status. Shared by the private
/// `stream` and public `stream_public` handlers — `stream` is the primitive,
/// `stream_public` resolves the address to a DataMap then calls this.
fn spawn_data_chunk_stream(
    client: Arc<ant_core::data::Client>,
    data_map: ant_core::data::DataMap,
) -> tokio_stream::wrappers::ReceiverStream<Result<pb::DataChunk, Status>> {
    let (byte_tx, mut byte_rx) =
        tokio::sync::mpsc::channel::<std::result::Result<Bytes, ant_core::data::Error>>(16);
    let (out_tx, out_rx) = tokio::sync::mpsc::channel::<Result<pb::DataChunk, Status>>(16);

    // Producer: drive the download. file_download_to_sender returns a terminal
    // error rather than sending it into the sink, so push it via a cloned
    // handle after the chunks it already sent (preserves order on the channel).
    let err_tx = byte_tx.clone();
    tokio::spawn(async move {
        if let Err(e) = client
            .file_download_to_sender(&data_map, byte_tx, None)
            .await
        {
            let _ = err_tx.send(Err(e)).await;
        }
    });

    // Forwarder: bytes -> DataChunk, ant-core error -> Status (reusing the
    // daemon's existing mapping). Stops early if the client drops the stream.
    tokio::spawn(async move {
        while let Some(item) = byte_rx.recv().await {
            let mapped = match item {
                Ok(bytes) => Ok(pb::DataChunk {
                    data: bytes.to_vec(),
                }),
                Err(e) => Err(Status::from(AntdError::from_core(e))),
            };
            if out_tx.send(mapped).await.is_err() {
                break;
            }
        }
    });

    tokio_stream::wrappers::ReceiverStream::new(out_rx)
}

#[tonic::async_trait]
impl pb::data_service_server::DataService for DataServiceImpl {
    async fn get_public(
        &self,
        request: Request<pb::GetPublicDataRequest>,
    ) -> Result<Response<pb::GetPublicDataResponse>, Status> {
        let addr = request.into_inner().address;
        if addr.len() != 64 {
            return Err(Status::invalid_argument(
                "address must be exactly 64 hex characters",
            ));
        }
        let address_bytes = hex::decode(&addr)
            .map_err(|e| Status::invalid_argument(format!("invalid hex address: {e}")))?;
        let address: [u8; 32] = address_bytes
            .try_into()
            .map_err(|_| Status::invalid_argument("address must be 32 bytes"))?;

        let client = self.state.client.clone();
        let content = tokio::spawn(async move {
            let data_map = client
                .data_map_fetch(&address)
                .await
                .map_err(AntdError::from_core)?;
            client
                .data_download(&data_map)
                .await
                .map_err(AntdError::from_core)
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::GetPublicDataResponse {
            data: content.to_vec(),
        }))
    }

    async fn put_public(
        &self,
        request: Request<pb::PutPublicDataRequest>,
    ) -> Result<Response<pb::PutPublicDataResponse>, Status> {
        if self.state.client.wallet().is_none() {
            return Err(Status::unavailable(
                "wallet not configured — set AUTONOMI_WALLET_KEY",
            ));
        }

        let req = request.into_inner();
        let mode = parse_grpc_payment_mode(&req.payment_mode).map_err(Status::invalid_argument)?;
        let data = req.data;

        let client = self.state.client.clone();
        let address = tokio::spawn(async move {
            let result = client
                .data_upload_with_mode(Bytes::from(data), mode)
                .await
                .map_err(AntdError::from_core)?;
            let address = client
                .data_map_store(&result.data_map)
                .await
                .map_err(AntdError::from_core)?;
            Ok::<_, AntdError>(address)
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::PutPublicDataResponse {
            // ant-core's DataUploadResult does not expose per-upload storage
            // cost — REST mirrors this by omitting the field from its response
            // shape. Left empty for symmetry.
            cost: Some(pb::Cost {
                atto_tokens: String::new(),
                ..Default::default()
            }),
            address: hex::encode(address),
        }))
    }

    type StreamStream = tokio_stream::wrappers::ReceiverStream<Result<pb::DataChunk, Status>>;
    async fn stream(
        &self,
        request: Request<pb::StreamDataRequest>,
    ) -> Result<Response<Self::StreamStream>, Status> {
        let data_map_hex = request.into_inner().data_map;
        let data_map_bytes = hex::decode(&data_map_hex)
            .map_err(|e| Status::invalid_argument(format!("invalid hex data_map: {e}")))?;

        // Reject oversized data maps before deserialization (10 MB limit) —
        // mirrors `get`.
        const MAX_DATA_MAP_SIZE: usize = 10 * 1024 * 1024;
        if data_map_bytes.len() > MAX_DATA_MAP_SIZE {
            return Err(Status::invalid_argument(format!(
                "data map too large: {} bytes exceeds {} byte limit",
                data_map_bytes.len(),
                MAX_DATA_MAP_SIZE,
            )));
        }

        let data_map: ant_core::data::DataMap = rmp_serde::from_slice(&data_map_bytes)
            .map_err(|e| Status::invalid_argument(format!("invalid data map: {e}")))?;

        let client = self.state.client.clone();
        Ok(Response::new(spawn_data_chunk_stream(client, data_map)))
    }

    type StreamPublicStream = tokio_stream::wrappers::ReceiverStream<Result<pb::DataChunk, Status>>;
    async fn stream_public(
        &self,
        request: Request<pb::StreamPublicDataRequest>,
    ) -> Result<Response<Self::StreamPublicStream>, Status> {
        let addr = request.into_inner().address;
        if addr.len() != 64 {
            return Err(Status::invalid_argument(
                "address must be exactly 64 hex characters",
            ));
        }
        let address_bytes = hex::decode(&addr)
            .map_err(|e| Status::invalid_argument(format!("invalid hex address: {e}")))?;
        let address: [u8; 32] = address_bytes
            .try_into()
            .map_err(|_| Status::invalid_argument("address must be 32 bytes"))?;

        // Resolve address -> DataMap up front so a fetch failure surfaces as a
        // normal unary error before the stream opens; then stream from the
        // DataMap (public wraps the private primitive).
        let client = self.state.client.clone();
        let data_map = client
            .data_map_fetch(&address)
            .await
            .map_err(AntdError::from_core)
            .map_err(tonic::Status::from)?;

        Ok(Response::new(spawn_data_chunk_stream(client, data_map)))
    }

    async fn get(
        &self,
        request: Request<pb::GetDataRequest>,
    ) -> Result<Response<pb::GetDataResponse>, Status> {
        let data_map_hex = request.into_inner().data_map;
        let data_map_bytes = hex::decode(&data_map_hex)
            .map_err(|e| Status::invalid_argument(format!("invalid hex data_map: {e}")))?;

        // Reject oversized data maps before deserialization (10 MB limit)
        const MAX_DATA_MAP_SIZE: usize = 10 * 1024 * 1024;
        if data_map_bytes.len() > MAX_DATA_MAP_SIZE {
            return Err(Status::invalid_argument(format!(
                "data map too large: {} bytes exceeds {} byte limit",
                data_map_bytes.len(),
                MAX_DATA_MAP_SIZE,
            )));
        }

        let data_map: ant_core::data::DataMap = rmp_serde::from_slice(&data_map_bytes)
            .map_err(|e| Status::invalid_argument(format!("invalid data map: {e}")))?;

        let client = self.state.client.clone();
        let content = tokio::spawn(async move {
            client
                .data_download(&data_map)
                .await
                .map_err(AntdError::from_core)
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::GetDataResponse {
            data: content.to_vec(),
        }))
    }

    async fn put(
        &self,
        request: Request<pb::PutDataRequest>,
    ) -> Result<Response<pb::PutDataResponse>, Status> {
        if self.state.client.wallet().is_none() {
            return Err(Status::unavailable(
                "wallet not configured — set AUTONOMI_WALLET_KEY",
            ));
        }

        let req = request.into_inner();
        let mode = parse_grpc_payment_mode(&req.payment_mode).map_err(Status::invalid_argument)?;
        let data = req.data;

        let client = self.state.client.clone();
        let data_map_hex = tokio::spawn(async move {
            let result = client
                .data_upload_with_mode(Bytes::from(data), mode)
                .await
                .map_err(AntdError::from_core)?;
            let data_map_bytes = rmp_serde::to_vec(&result.data_map)
                .map_err(|e| AntdError::Internal(format!("failed to serialize data map: {e}")))?;
            Ok::<_, AntdError>(hex::encode(data_map_bytes))
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::PutDataResponse {
            // ant-core's DataUploadResult does not expose per-upload storage
            // cost — REST mirrors this by omitting the field from its response
            // shape. Left empty for symmetry.
            cost: Some(pb::Cost {
                atto_tokens: String::new(),
                ..Default::default()
            }),
            data_map: data_map_hex,
        }))
    }

    async fn cost(
        &self,
        request: Request<pb::DataCostRequest>,
    ) -> Result<Response<pb::Cost>, Status> {
        let req = request.into_inner();
        let mode = parse_grpc_payment_mode(&req.payment_mode).map_err(Status::invalid_argument)?;
        let data = req.data;

        // estimate_upload_cost takes a path; stage the bytes in a temp file.
        let tmp = std::env::temp_dir().join(format!(
            "antd_cost_{}_{}.bin",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0)
        ));
        tokio::fs::write(&tmp, &data)
            .await
            .map_err(|e| Status::internal(format!("failed to stage tempfile: {e}")))?;

        let client = self.state.client.clone();
        let tmp_for_task = tmp.clone();
        let estimate =
            tokio::spawn(
                async move { client.estimate_upload_cost(&tmp_for_task, mode, None).await },
            )
            .await
            .map_err(|e| Status::internal(format!("task failed: {e}")))?;

        let _ = tokio::fs::remove_file(&tmp).await;
        let estimate = estimate
            .map_err(AntdError::from_core)
            .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::Cost {
            atto_tokens: estimate.storage_cost_atto,
            file_size: estimate.file_size,
            chunk_count: estimate.chunk_count as u32,
            estimated_gas_cost_wei: estimate.estimated_gas_cost_wei,
            payment_mode: format_payment_mode(estimate.payment_mode),
        }))
    }
}

// ── ChunkService ──

pub struct ChunkServiceImpl {
    pub state: Arc<AppState>,
}

#[tonic::async_trait]
impl pb::chunk_service_server::ChunkService for ChunkServiceImpl {
    async fn get(
        &self,
        request: Request<pb::GetChunkRequest>,
    ) -> Result<Response<pb::GetChunkResponse>, Status> {
        let addr = request.into_inner().address;
        let address_bytes = hex::decode(&addr)
            .map_err(|e| Status::invalid_argument(format!("invalid hex address: {e}")))?;
        let address: [u8; 32] = address_bytes
            .try_into()
            .map_err(|_| Status::invalid_argument("address must be 32 bytes"))?;

        let chunk = self
            .state
            .client
            .chunk_get(&address)
            .await
            .map_err(|e| tonic::Status::from(AntdError::from_core(e)))?
            .ok_or_else(|| Status::not_found("chunk not found"))?;

        Ok(Response::new(pb::GetChunkResponse {
            data: chunk.content.to_vec(),
        }))
    }

    async fn put(
        &self,
        request: Request<pb::PutChunkRequest>,
    ) -> Result<Response<pb::PutChunkResponse>, Status> {
        let data = request.into_inner().data;

        if self.state.client.wallet().is_none() {
            return Err(Status::unavailable(
                "wallet not configured — set AUTONOMI_WALLET_KEY",
            ));
        }

        let content = Bytes::from(data);
        let address = self
            .state
            .client
            .chunk_put(content)
            .await
            .map_err(|e| tonic::Status::from(AntdError::from_core(e)))?;

        Ok(Response::new(pb::PutChunkResponse {
            // ant-core chunk_put returns only the address; cost is pre-paid
            // via the wallet and not reported back per-chunk.
            cost: Some(pb::Cost {
                atto_tokens: String::new(),
                ..Default::default()
            }),
            address: hex::encode(address),
        }))
    }

    async fn prepare_chunk(
        &self,
        request: Request<pb::PrepareChunkRequest>,
    ) -> Result<Response<pb::PrepareChunkResponse>, Status> {
        let content = Bytes::from(request.into_inner().data);

        // Compute the content address up-front so the "already stored"
        // response can still return it without re-quoting (ant-core's prepare
        // returns Ok(None) without the address on that path).
        let address_hex = hex::encode(ant_core::data::compute_address(&content));

        let client = self.state.client.clone();
        let prepared = tokio::spawn(async move {
            client
                .prepare_chunk_payment(content)
                .await
                .map_err(AntdError::from_core)
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        let Some(prepared) = prepared else {
            return Ok(Response::new(pb::PrepareChunkResponse {
                address: address_hex,
                already_stored: true,
                ..Default::default()
            }));
        };

        let evm_cfg = crate::evm_defaults::resolve(&self.state.network);

        // Filter zero-amount quotes — they go into peer_quotes for
        // ProofOfPayment but the external signer doesn't need a
        // `payForQuotes` entry for them.
        let payments: Vec<pb::PaymentEntry> = prepared
            .payment
            .quotes
            .iter()
            .filter(|q| !q.amount.is_zero())
            .map(|q| pb::PaymentEntry {
                quote_hash: format!("{:#x}", q.quote_hash),
                rewards_address: format!("{:#x}", q.rewards_address),
                amount: q.amount.to_string(),
            })
            .collect();
        let total_amount = prepared.payment.total_amount().to_string();

        let upload_id = hex::encode(rand::random::<[u8; 16]>());
        self.state.pending_chunks.lock().await.insert(
            upload_id.clone(),
            crate::state::TimestampedChunk {
                prepared,
                created_at: std::time::Instant::now(),
            },
        );

        Ok(Response::new(pb::PrepareChunkResponse {
            address: address_hex,
            already_stored: false,
            upload_id,
            payment_type: "wave_batch".into(),
            payments,
            total_amount,
            payment_vault_address: evm_cfg.vault_addr,
            payment_token_address: evm_cfg.token_addr,
            rpc_url: evm_cfg.rpc_url,
        }))
    }

    async fn finalize_chunk(
        &self,
        request: Request<pb::FinalizeChunkRequest>,
    ) -> Result<Response<pb::FinalizeChunkResponse>, Status> {
        use evmlib::common::{QuoteHash, TxHash};
        use std::collections::HashMap;

        let req = request.into_inner();
        let timestamped = self
            .state
            .pending_chunks
            .lock()
            .await
            .remove(&req.upload_id)
            .ok_or_else(|| {
                Status::not_found(format!(
                    "upload_id {} not found — it may have expired or already been finalized",
                    req.upload_id
                ))
            })?;

        // Closure returns AntdError (small) rather than Status (>=176 bytes)
        // to keep clippy::result_large_err happy; converted at the boundary.
        let tx_hash_map: HashMap<QuoteHash, TxHash> = req
            .tx_hashes
            .iter()
            .map(|(quote_hex, tx_hex)| {
                let quote_bytes: [u8; 32] = hex::decode(quote_hex.trim_start_matches("0x"))
                    .map_err(|e| {
                        AntdError::BadRequest(format!("invalid quote_hash {quote_hex}: {e}"))
                    })?
                    .try_into()
                    .map_err(|_| AntdError::BadRequest("quote_hash must be 32 bytes".into()))?;
                let tx_bytes: [u8; 32] = hex::decode(tx_hex.trim_start_matches("0x"))
                    .map_err(|e| AntdError::BadRequest(format!("invalid tx_hash {tx_hex}: {e}")))?
                    .try_into()
                    .map_err(|_| AntdError::BadRequest("tx_hash must be 32 bytes".into()))?;
                Ok((quote_bytes.into(), tx_bytes.into()))
            })
            .collect::<Result<_, AntdError>>()
            .map_err(tonic::Status::from)?;

        let client = self.state.client.clone();
        let prepared = timestamped.prepared;
        let address = tokio::spawn(async move {
            client
                .finalize_chunk(prepared, &tx_hash_map)
                .await
                .map_err(AntdError::from_core)
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::FinalizeChunkResponse {
            address: hex::encode(address),
        }))
    }
}

// ── FileService ──

pub struct FileServiceImpl {
    pub state: Arc<AppState>,
}

#[tonic::async_trait]
impl pb::file_service_server::FileService for FileServiceImpl {
    async fn put(
        &self,
        request: Request<pb::PutFileRequest>,
    ) -> Result<Response<pb::PutFileResponse>, Status> {
        if self.state.client.wallet().is_none() {
            return Err(Status::unavailable(
                "wallet not configured — set AUTONOMI_WALLET_KEY",
            ));
        }

        let req = request.into_inner();
        let mode = parse_grpc_payment_mode(&req.payment_mode).map_err(Status::invalid_argument)?;
        let path = PathBuf::from(&req.path).canonicalize().map_err(|e| {
            tracing::warn!(path = %req.path, error = %e, "invalid upload path");
            Status::invalid_argument("invalid path")
        })?;

        let client = self.state.client.clone();
        let (result, data_map_hex) = tokio::spawn(async move {
            let result = client
                .file_upload_with_mode(&path, mode)
                .await
                .map_err(AntdError::from_core)?;
            let data_map_bytes = rmp_serde::to_vec(&result.data_map)
                .map_err(|e| AntdError::Internal(format!("failed to serialize data map: {e}")))?;
            Ok::<_, AntdError>((result, hex::encode(data_map_bytes)))
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::PutFileResponse {
            data_map: data_map_hex,
            storage_cost_atto: result.storage_cost_atto,
            gas_cost_wei: result.gas_cost_wei.to_string(),
            chunks_stored: result.chunks_stored as u64,
            payment_mode_used: format_payment_mode(result.payment_mode_used),
        }))
    }

    async fn put_public(
        &self,
        request: Request<pb::PutFileRequest>,
    ) -> Result<Response<pb::PutFilePublicResponse>, Status> {
        if self.state.client.wallet().is_none() {
            return Err(Status::unavailable(
                "wallet not configured — set AUTONOMI_WALLET_KEY",
            ));
        }

        let req = request.into_inner();
        let mode = parse_grpc_payment_mode(&req.payment_mode).map_err(Status::invalid_argument)?;
        let path = PathBuf::from(&req.path).canonicalize().map_err(|e| {
            tracing::warn!(path = %req.path, error = %e, "invalid upload path");
            Status::invalid_argument("invalid path")
        })?;

        let client = self.state.client.clone();
        let (result, address) = tokio::spawn(async move {
            let result = client
                .file_upload_with_mode(&path, mode)
                .await
                .map_err(AntdError::from_core)?;
            let address = client
                .data_map_store(&result.data_map)
                .await
                .map_err(AntdError::from_core)?;
            Ok::<_, AntdError>((result, address))
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::PutFilePublicResponse {
            address: hex::encode(address),
            storage_cost_atto: result.storage_cost_atto,
            gas_cost_wei: result.gas_cost_wei.to_string(),
            chunks_stored: result.chunks_stored as u64,
            payment_mode_used: format_payment_mode(result.payment_mode_used),
        }))
    }

    async fn get(
        &self,
        request: Request<pb::GetFileRequest>,
    ) -> Result<Response<pb::GetFileResponse>, Status> {
        let req = request.into_inner();

        let data_map_bytes = hex::decode(&req.data_map)
            .map_err(|e| Status::invalid_argument(format!("invalid hex data_map: {e}")))?;
        const MAX_DATA_MAP_SIZE: usize = 10 * 1024 * 1024;
        if data_map_bytes.len() > MAX_DATA_MAP_SIZE {
            return Err(Status::invalid_argument(format!(
                "data map too large: {} bytes exceeds {} byte limit",
                data_map_bytes.len(),
                MAX_DATA_MAP_SIZE,
            )));
        }
        let data_map: ant_core::data::DataMap = rmp_serde::from_slice(&data_map_bytes)
            .map_err(|e| Status::invalid_argument(format!("invalid data map: {e}")))?;

        let dest = PathBuf::from(&req.dest_path);
        let canonical_parent = dest
            .parent()
            .ok_or_else(|| Status::invalid_argument("dest_path has no parent directory"))?
            .canonicalize()
            .map_err(|e| {
                tracing::warn!(dest_path = %req.dest_path, error = %e, "invalid dest_path");
                Status::invalid_argument("invalid destination path")
            })?;
        let dest = canonical_parent.join(
            dest.file_name()
                .ok_or_else(|| Status::invalid_argument("dest_path has no filename"))?,
        );
        if !dest.starts_with(&canonical_parent) {
            return Err(Status::invalid_argument(
                "destination path escapes allowed directory",
            ));
        }

        let client = self.state.client.clone();
        tokio::spawn(async move {
            client
                .file_download(&data_map, &dest)
                .await
                .map_err(AntdError::from_core)
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::GetFileResponse {}))
    }

    async fn get_public(
        &self,
        request: Request<pb::GetFilePublicRequest>,
    ) -> Result<Response<pb::GetFileResponse>, Status> {
        let req = request.into_inner();

        if req.address.len() != 64 {
            return Err(Status::invalid_argument(
                "address must be exactly 64 hex characters",
            ));
        }
        let address_bytes = hex::decode(&req.address)
            .map_err(|e| Status::invalid_argument(format!("invalid hex address: {e}")))?;
        let address: [u8; 32] = address_bytes
            .try_into()
            .map_err(|_| Status::invalid_argument("address must be 32 bytes"))?;

        let dest = PathBuf::from(&req.dest_path);
        let canonical_parent = dest
            .parent()
            .ok_or_else(|| Status::invalid_argument("dest_path has no parent directory"))?
            .canonicalize()
            .map_err(|e| {
                tracing::warn!(dest_path = %req.dest_path, error = %e, "invalid dest_path");
                Status::invalid_argument("invalid destination path")
            })?;
        let dest = canonical_parent.join(
            dest.file_name()
                .ok_or_else(|| Status::invalid_argument("dest_path has no filename"))?,
        );
        if !dest.starts_with(&canonical_parent) {
            return Err(Status::invalid_argument(
                "destination path escapes allowed directory",
            ));
        }

        let client = self.state.client.clone();
        tokio::spawn(async move {
            let data_map = client
                .data_map_fetch(&address)
                .await
                .map_err(AntdError::from_core)?;
            client
                .file_download(&data_map, &dest)
                .await
                .map_err(AntdError::from_core)?;
            Ok::<_, AntdError>(())
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::GetFileResponse {}))
    }

    async fn cost(
        &self,
        request: Request<pb::FileCostRequest>,
    ) -> Result<Response<pb::Cost>, Status> {
        let req = request.into_inner();
        let mode = parse_grpc_payment_mode(&req.payment_mode).map_err(Status::invalid_argument)?;
        let path = PathBuf::from(&req.path).canonicalize().map_err(|e| {
            tracing::warn!(path = %req.path, error = %e, "invalid file cost path");
            Status::invalid_argument("invalid path")
        })?;

        let client = self.state.client.clone();
        let estimate =
            tokio::spawn(async move { client.estimate_upload_cost(&path, mode, None).await })
                .await
                .map_err(|e| Status::internal(format!("task failed: {e}")))?
                .map_err(AntdError::from_core)
                .map_err(tonic::Status::from)?;

        let (chunk_count, atto_tokens) = if req.is_public {
            adjust_for_public_upload(estimate.chunk_count, &estimate.storage_cost_atto)
        } else {
            (estimate.chunk_count, estimate.storage_cost_atto)
        };

        Ok(Response::new(pb::Cost {
            atto_tokens,
            file_size: estimate.file_size,
            chunk_count: chunk_count as u32,
            estimated_gas_cost_wei: estimate.estimated_gas_cost_wei,
            payment_mode: format_payment_mode(estimate.payment_mode),
        }))
    }
}

// ── UploadService ──
//
// External-signer two-phase upload flow. Mirrors the REST handlers in
// `antd/src/rest/upload.rs` exactly — same `pending_uploads` state, same
// `file_prepare_upload_with_visibility` / `data_prepare_upload_with_visibility`
// / `finalize_upload` / `finalize_upload_merkle` call shapes. Helper
// `build_grpc_prepare_response` (above) is the gRPC counterpart of REST's
// `build_prepare_response`.

pub struct UploadServiceImpl {
    pub state: Arc<AppState>,
}

#[tonic::async_trait]
impl pb::upload_service_server::UploadService for UploadServiceImpl {
    async fn prepare_file_upload(
        &self,
        request: Request<pb::PrepareFileUploadRequest>,
    ) -> Result<Response<pb::PrepareUploadResponse>, Status> {
        let req = request.into_inner();
        let path = PathBuf::from(&req.path).canonicalize().map_err(|e| {
            tracing::warn!(path = %req.path, error = %e, "invalid prepare-file-upload path");
            Status::invalid_argument("invalid path")
        })?;
        let visibility =
            parse_grpc_visibility(&req.visibility).map_err(Status::invalid_argument)?;

        let client = self.state.client.clone();
        let prepared = tokio::spawn(async move {
            client
                .file_prepare_upload_with_visibility(&path, visibility)
                .await
                .map_err(AntdError::from_core)
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        let upload_id = hex::encode(rand::random::<[u8; 16]>());
        let response =
            build_grpc_prepare_response(upload_id.clone(), &prepared, &self.state.network);

        self.state.pending_uploads.lock().await.insert(
            upload_id,
            crate::state::TimestampedUpload {
                prepared,
                created_at: std::time::Instant::now(),
            },
        );

        Ok(Response::new(response))
    }

    async fn prepare_data_upload(
        &self,
        request: Request<pb::PrepareDataUploadRequest>,
    ) -> Result<Response<pb::PrepareUploadResponse>, Status> {
        let req = request.into_inner();
        let visibility =
            parse_grpc_visibility(&req.visibility).map_err(Status::invalid_argument)?;
        let data = Bytes::from(req.data);

        let client = self.state.client.clone();
        let prepared = tokio::spawn(async move {
            client
                .data_prepare_upload_with_visibility(data, visibility)
                .await
                .map_err(AntdError::from_core)
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        let upload_id = hex::encode(rand::random::<[u8; 16]>());
        let response =
            build_grpc_prepare_response(upload_id.clone(), &prepared, &self.state.network);

        self.state.pending_uploads.lock().await.insert(
            upload_id,
            crate::state::TimestampedUpload {
                prepared,
                created_at: std::time::Instant::now(),
            },
        );

        Ok(Response::new(response))
    }

    async fn finalize_upload(
        &self,
        request: Request<pb::FinalizeUploadRequest>,
    ) -> Result<Response<pb::FinalizeUploadResponse>, Status> {
        use evmlib::common::{QuoteHash, TxHash};
        use std::collections::HashMap;

        let req = request.into_inner();
        let timestamped = self
            .state
            .pending_uploads
            .lock()
            .await
            .remove(&req.upload_id)
            .ok_or_else(|| {
                Status::not_found(format!(
                    "upload_id {} not found — it may have expired or already been finalized",
                    req.upload_id
                ))
            })?;
        let prepared = timestamped.prepared;
        let store_on_network = req.store_data_map;
        let client = self.state.client.clone();

        let (data_map_hex, address, data_map_address, chunks_stored) = match &prepared.payment_info
        {
            ant_core::data::ExternalPaymentInfo::WaveBatch { .. } => {
                if !req.winner_pool_hash.is_empty() {
                    return Err(Status::invalid_argument(
                        "winner_pool_hash not applicable for wave-batch upload",
                    ));
                }
                if req.tx_hashes.is_empty() {
                    return Err(Status::invalid_argument(
                        "tx_hashes required for wave-batch upload (this upload used wave_batch payment)",
                    ));
                }

                // Closure returns AntdError (small) rather than Status
                // (>=176 bytes) to keep clippy::result_large_err happy;
                // converted at the boundary.
                let tx_hash_map: HashMap<QuoteHash, TxHash> = req
                    .tx_hashes
                    .iter()
                    .map(|(quote_hex, tx_hex)| {
                        let quote_bytes: [u8; 32] = hex::decode(quote_hex.trim_start_matches("0x"))
                            .map_err(|e| {
                                AntdError::BadRequest(format!(
                                    "invalid quote_hash {quote_hex}: {e}"
                                ))
                            })?
                            .try_into()
                            .map_err(|_| {
                                AntdError::BadRequest("quote_hash must be 32 bytes".into())
                            })?;
                        let tx_bytes: [u8; 32] = hex::decode(tx_hex.trim_start_matches("0x"))
                            .map_err(|e| {
                                AntdError::BadRequest(format!("invalid tx_hash {tx_hex}: {e}"))
                            })?
                            .try_into()
                            .map_err(|_| {
                                AntdError::BadRequest("tx_hash must be 32 bytes".into())
                            })?;
                        Ok((quote_bytes.into(), tx_bytes.into()))
                    })
                    .collect::<Result<_, AntdError>>()
                    .map_err(tonic::Status::from)?;

                tokio::spawn(async move {
                    let result = client
                        .finalize_upload(prepared, &tx_hash_map)
                        .await
                        .map_err(AntdError::from_core)?;

                    let data_map_bytes = rmp_serde::to_vec(&result.data_map)
                        .map_err(|e| AntdError::Internal(format!("serialize data map: {e}")))?;
                    let data_map_hex = hex::encode(data_map_bytes);

                    let address = if store_on_network {
                        let addr = client
                            .data_map_store(&result.data_map)
                            .await
                            .map_err(AntdError::from_core)?;
                        Some(hex::encode(addr))
                    } else {
                        None
                    };

                    let data_map_address = result.data_map_address.map(hex::encode);

                    Ok::<_, AntdError>((
                        data_map_hex,
                        address,
                        data_map_address,
                        result.chunks_stored,
                    ))
                })
                .await
                .map_err(|e| Status::internal(format!("task failed: {e}")))?
                .map_err(tonic::Status::from)?
            }

            ant_core::data::ExternalPaymentInfo::Merkle { .. } => {
                if !req.tx_hashes.is_empty() {
                    return Err(Status::invalid_argument(
                        "tx_hashes not applicable for merkle upload",
                    ));
                }
                if req.winner_pool_hash.is_empty() {
                    return Err(Status::invalid_argument(
                        "winner_pool_hash required for merkle upload (this upload used merkle payment)",
                    ));
                }

                let winner_pool_hash: [u8; 32] =
                    hex::decode(req.winner_pool_hash.trim_start_matches("0x"))
                        .map_err(|e| {
                            Status::invalid_argument(format!("invalid winner_pool_hash: {e}"))
                        })?
                        .try_into()
                        .map_err(|_| {
                            Status::invalid_argument("winner_pool_hash must be 32 bytes")
                        })?;

                tokio::spawn(async move {
                    let result = client
                        .finalize_upload_merkle(prepared, winner_pool_hash)
                        .await
                        .map_err(AntdError::from_core)?;

                    let data_map_bytes = rmp_serde::to_vec(&result.data_map)
                        .map_err(|e| AntdError::Internal(format!("serialize data map: {e}")))?;
                    let data_map_hex = hex::encode(data_map_bytes);

                    let address = if store_on_network {
                        let addr = client
                            .data_map_store(&result.data_map)
                            .await
                            .map_err(AntdError::from_core)?;
                        Some(hex::encode(addr))
                    } else {
                        None
                    };

                    let data_map_address = result.data_map_address.map(hex::encode);

                    Ok::<_, AntdError>((
                        data_map_hex,
                        address,
                        data_map_address,
                        result.chunks_stored,
                    ))
                })
                .await
                .map_err(|e| Status::internal(format!("task failed: {e}")))?
                .map_err(tonic::Status::from)?
            }
        };

        Ok(Response::new(pb::FinalizeUploadResponse {
            data_map: data_map_hex,
            address: address.unwrap_or_default(),
            data_map_address: data_map_address.unwrap_or_default(),
            chunks_stored: chunks_stored as u64,
        }))
    }
}

// ── EventService ──
//
// Intentionally stubbed: the upstream ant-core event system is not yet wired
// into the daemon. The Subscribe RPC returns an open stream that will never
// emit events. This will be implemented once ant-core exposes a client event
// channel that the daemon can forward.

pub struct EventServiceImpl {
    #[allow(dead_code)]
    pub state: Arc<AppState>,
}

#[tonic::async_trait]
impl pb::event_service_server::EventService for EventServiceImpl {
    type SubscribeStream =
        tokio_stream::wrappers::ReceiverStream<Result<pb::ClientEventProto, Status>>;

    async fn subscribe(
        &self,
        _request: Request<pb::SubscribeRequest>,
    ) -> Result<Response<Self::SubscribeStream>, Status> {
        let (_tx, rx) = tokio::sync::mpsc::channel(1);
        Ok(Response::new(tokio_stream::wrappers::ReceiverStream::new(
            rx,
        )))
    }
}

// ── WalletService ──
//
// Mirrors `antd/src/rest/wallet.rs` 1:1; the underlying `Client::wallet()`
// access is transport-agnostic. Same error mapping: a missing wallet returns
// `Status::failed_precondition` (the gRPC analog of REST's 503 service-
// unavailable for this case).

pub struct WalletServiceImpl {
    pub state: Arc<AppState>,
}

#[tonic::async_trait]
impl pb::wallet_service_server::WalletService for WalletServiceImpl {
    async fn get_address(
        &self,
        _request: Request<pb::GetWalletAddressRequest>,
    ) -> Result<Response<pb::GetWalletAddressResponse>, Status> {
        let wallet = self.state.client.wallet().ok_or_else(|| {
            Status::failed_precondition("wallet not configured — set AUTONOMI_WALLET_KEY")
        })?;
        Ok(Response::new(pb::GetWalletAddressResponse {
            address: format!("{:#x}", wallet.address()),
        }))
    }

    async fn get_balance(
        &self,
        _request: Request<pb::GetWalletBalanceRequest>,
    ) -> Result<Response<pb::GetWalletBalanceResponse>, Status> {
        let wallet = self.state.client.wallet().ok_or_else(|| {
            Status::failed_precondition("wallet not configured — set AUTONOMI_WALLET_KEY")
        })?;

        let balance = wallet
            .balance_of_tokens()
            .await
            .map_err(|e| Status::internal(format!("failed to get token balance: {e}")))?;
        let gas_balance = wallet
            .balance_of_gas_tokens()
            .await
            .map_err(|e| Status::internal(format!("failed to get gas balance: {e}")))?;

        Ok(Response::new(pb::GetWalletBalanceResponse {
            balance: balance.to_string(),
            gas_balance: gas_balance.to_string(),
        }))
    }

    async fn approve(
        &self,
        _request: Request<pb::WalletApproveRequest>,
    ) -> Result<Response<pb::WalletApproveResponse>, Status> {
        if self.state.client.wallet().is_none() {
            return Err(Status::failed_precondition(
                "wallet not configured — set AUTONOMI_WALLET_KEY",
            ));
        }

        let client = self.state.client.clone();
        // Spawn so the approve tx can run on its own task (matches REST handler
        // shape; ant-core's approve_token_spend is async and may be long).
        tokio::spawn(async move {
            client
                .approve_token_spend()
                .await
                .map_err(AntdError::from_core)
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(|e| Status::internal(format!("approve failed: {e}")))?;

        Ok(Response::new(pb::WalletApproveResponse { approved: true }))
    }
}
