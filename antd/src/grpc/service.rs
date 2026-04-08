use std::path::PathBuf;
use std::sync::Arc;

use bytes::Bytes;
use tonic::{Request, Response, Status};

use crate::error::AntdError;
use crate::state::AppState;

// Generated protobuf modules
pub mod pb {
    tonic::include_proto!("antd.v1");
}

fn not_implemented(op: &str) -> Status {
    Status::unimplemented(format!("{op} not yet implemented"))
}

// ── HealthService ──

pub struct HealthServiceImpl {
    pub network: String,
}

#[tonic::async_trait]
impl pb::health_service_server::HealthService for HealthServiceImpl {
    async fn check(
        &self,
        _request: Request<pb::HealthCheckRequest>,
    ) -> Result<Response<pb::HealthCheckResponse>, Status> {
        Ok(Response::new(pb::HealthCheckResponse {
            status: "ok".into(),
            network: self.network.clone(),
        }))
    }
}

// ── DataService ──

pub struct DataServiceImpl {
    pub state: Arc<AppState>,
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

        let data = request.into_inner().data;

        let client = self.state.client.clone();
        let address = tokio::spawn(async move {
            let result = client
                .data_upload_with_mode(Bytes::from(data), ant_core::data::PaymentMode::Auto)
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
            cost: Some(pb::Cost {
                atto_tokens: String::new(),
            }),
            address: hex::encode(address),
        }))
    }

    type StreamPublicStream = tokio_stream::wrappers::ReceiverStream<Result<pb::DataChunk, Status>>;
    async fn stream_public(
        &self,
        _r: Request<pb::StreamPublicDataRequest>,
    ) -> Result<Response<Self::StreamPublicStream>, Status> {
        Err(not_implemented("data stream public"))
    }

    async fn get_private(
        &self,
        request: Request<pb::GetPrivateDataRequest>,
    ) -> Result<Response<pb::GetPrivateDataResponse>, Status> {
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

        Ok(Response::new(pb::GetPrivateDataResponse {
            data: content.to_vec(),
        }))
    }

    async fn put_private(
        &self,
        request: Request<pb::PutPrivateDataRequest>,
    ) -> Result<Response<pb::PutPrivateDataResponse>, Status> {
        if self.state.client.wallet().is_none() {
            return Err(Status::unavailable(
                "wallet not configured — set AUTONOMI_WALLET_KEY",
            ));
        }

        let data = request.into_inner().data;

        let client = self.state.client.clone();
        let data_map_hex = tokio::spawn(async move {
            let result = client
                .data_upload_with_mode(Bytes::from(data), ant_core::data::PaymentMode::Auto)
                .await
                .map_err(AntdError::from_core)?;
            let data_map_bytes = rmp_serde::to_vec(&result.data_map)
                .map_err(|e| AntdError::Internal(format!("failed to serialize data map: {e}")))?;
            Ok::<_, AntdError>(hex::encode(data_map_bytes))
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::PutPrivateDataResponse {
            cost: Some(pb::Cost {
                atto_tokens: String::new(),
            }),
            data_map: data_map_hex,
        }))
    }

    async fn get_cost(
        &self,
        request: Request<pb::DataCostRequest>,
    ) -> Result<Response<pb::Cost>, Status> {
        let data = request.into_inner().data;

        let client = self.state.client.clone();
        let total_cost = tokio::spawn(async move {
            use self_encryption::encrypt;
            let (_data_map, encrypted_chunks) = encrypt(Bytes::from(data))
                .map_err(|e| AntdError::Internal(format!("encryption failed: {e}")))?;

            let mut total = ant_core::data::U256::ZERO;
            for chunk in &encrypted_chunks {
                let address = ant_core::data::compute_address(&chunk.content);
                let data_size = chunk.content.len() as u64;
                match client.get_store_quotes(&address, data_size, 0).await {
                    Ok(quotes) => {
                        for (_, _, _, price) in &quotes {
                            total = total.saturating_add(*price);
                        }
                    }
                    Err(e) => {
                        // AlreadyStored means no cost for this chunk
                        if !matches!(e, ant_core::data::Error::AlreadyStored) {
                            return Err(AntdError::from_core(e));
                        }
                    }
                }
            }
            Ok::<_, AntdError>(total)
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::Cost {
            atto_tokens: total_cost.to_string(),
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
            }),
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
    async fn upload_public(
        &self,
        request: Request<pb::UploadFileRequest>,
    ) -> Result<Response<pb::UploadPublicResponse>, Status> {
        if self.state.client.wallet().is_none() {
            return Err(Status::unavailable(
                "wallet not configured — set AUTONOMI_WALLET_KEY",
            ));
        }

        let req = request.into_inner();
        let path = PathBuf::from(&req.path).canonicalize().map_err(|e| {
            tracing::warn!(path = %req.path, error = %e, "invalid upload path");
            Status::invalid_argument("invalid path")
        })?;

        let client = self.state.client.clone();
        let address = tokio::spawn(async move {
            let result = client
                .file_upload_with_mode(&path, ant_core::data::PaymentMode::Auto)
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

        Ok(Response::new(pb::UploadPublicResponse {
            cost: Some(pb::Cost {
                atto_tokens: String::new(),
            }),
            address: hex::encode(address),
        }))
    }

    async fn download_public(
        &self,
        request: Request<pb::DownloadPublicRequest>,
    ) -> Result<Response<pb::DownloadResponse>, Status> {
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

        Ok(Response::new(pb::DownloadResponse {}))
    }

    async fn dir_upload_public(
        &self,
        request: Request<pb::UploadFileRequest>,
    ) -> Result<Response<pb::UploadPublicResponse>, Status> {
        if self.state.client.wallet().is_none() {
            return Err(Status::unavailable(
                "wallet not configured — set AUTONOMI_WALLET_KEY",
            ));
        }

        let req = request.into_inner();
        let path = PathBuf::from(&req.path).canonicalize().map_err(|e| {
            tracing::warn!(path = %req.path, error = %e, "invalid directory upload path");
            Status::invalid_argument("invalid path")
        })?;
        if !path.is_dir() {
            return Err(Status::invalid_argument("path is not a directory"));
        }

        let client = self.state.client.clone();
        let address = tokio::spawn(async move {
            let result = client
                .file_upload_with_mode(&path, ant_core::data::PaymentMode::Auto)
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

        Ok(Response::new(pb::UploadPublicResponse {
            cost: Some(pb::Cost {
                atto_tokens: String::new(),
            }),
            address: hex::encode(address),
        }))
    }

    async fn dir_download_public(
        &self,
        request: Request<pb::DownloadPublicRequest>,
    ) -> Result<Response<pb::DownloadResponse>, Status> {
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

        Ok(Response::new(pb::DownloadResponse {}))
    }

    async fn get_file_cost(
        &self,
        request: Request<pb::FileCostRequest>,
    ) -> Result<Response<pb::Cost>, Status> {
        let req = request.into_inner();
        let path = PathBuf::from(&req.path).canonicalize().map_err(|e| {
            tracing::warn!(path = %req.path, error = %e, "invalid file cost path");
            Status::invalid_argument("invalid path")
        })?;

        let client = self.state.client.clone();
        let total_cost = tokio::spawn(async move {
            use self_encryption::encrypt;
            let file_data = tokio::fs::read(&path)
                .await
                .map_err(|e| AntdError::Internal(format!("failed to read file: {e}")))?;

            let (_data_map, encrypted_chunks) = encrypt(bytes::Bytes::from(file_data))
                .map_err(|e| AntdError::Internal(format!("encryption failed: {e}")))?;

            let mut total = ant_core::data::U256::ZERO;
            for chunk in &encrypted_chunks {
                let address = ant_core::data::compute_address(&chunk.content);
                let data_size = chunk.content.len() as u64;
                match client.get_store_quotes(&address, data_size, 0).await {
                    Ok(quotes) => {
                        for (_, _, _, price) in &quotes {
                            total = total.saturating_add(*price);
                        }
                    }
                    Err(e) => {
                        // AlreadyStored means no cost for this chunk
                        if !matches!(e, ant_core::data::Error::AlreadyStored) {
                            return Err(AntdError::from_core(e));
                        }
                    }
                }
            }
            Ok::<_, AntdError>(total)
        })
        .await
        .map_err(|e| Status::internal(format!("task failed: {e}")))?
        .map_err(tonic::Status::from)?;

        Ok(Response::new(pb::Cost {
            atto_tokens: total_cost.to_string(),
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
