use std::path::PathBuf;
use std::sync::Arc;

use bytes::Bytes;
use tonic::{Request, Response, Status};

use autonomi::{
    ChunkAddress, GraphEntryAddress, PublicKey, SecretKey, Chunk,
};
use autonomi::data::DataAddress;
use autonomi::graph::{GraphContent, GraphEntry};
use autonomi::files::{Metadata, PublicArchive};
use autonomi::client::payment::PaymentOption;

use crate::error::AntdError;
use crate::state::AppState;

// Generated protobuf modules
pub mod pb {
    #![allow(dead_code)]
    tonic::include_proto!("antd.v1");
}

// ── Helpers ──

fn parse_secret_key(hex_str: &str) -> Result<SecretKey, Status> {
    let bytes = hex::decode(hex_str).map_err(|e| Status::invalid_argument(format!("invalid hex: {e}")))?;
    let arr: [u8; 32] = bytes
        .try_into()
        .map_err(|_| Status::invalid_argument("secret key must be 32 bytes"))?;
    SecretKey::from_bytes(arr).map_err(|e| Status::invalid_argument(format!("invalid secret key: {e}")))
}

fn parse_graph_content(hex_str: &str) -> Result<GraphContent, Status> {
    let bytes = hex::decode(hex_str).map_err(|e| Status::invalid_argument(format!("invalid hex: {e}")))?;
    if bytes.len() != 32 {
        return Err(Status::invalid_argument(format!("content must be 32 bytes, got {}", bytes.len())));
    }
    let mut content = [0u8; 32];
    content.copy_from_slice(&bytes);
    Ok(content)
}

fn to_status(e: AntdError) -> Status {
    e.into()
}

fn wallet(state: &AppState) -> PaymentOption {
    PaymentOption::Wallet(state.wallet.clone())
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
        let addr = DataAddress::from_hex(&request.into_inner().address)
            .map_err(|e| Status::invalid_argument(format!("invalid address: {e}")))?;
        let data = self.state.client.data_get_public(&addr).await.map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::GetPublicDataResponse { data: data.to_vec() }))
    }

    async fn put_public(
        &self,
        request: Request<pb::PutPublicDataRequest>,
    ) -> Result<Response<pb::PutPublicDataResponse>, Status> {
        let data = request.into_inner().data;
        let (cost, address) = self
            .state
            .client
            .data_put_public(Bytes::from(data), wallet(&self.state))
            .await
            .map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::PutPublicDataResponse {
            cost: Some(pb::Cost { atto_tokens: cost.to_string() }),
            address: address.to_hex(),
        }))
    }

    type StreamPublicStream = tokio_stream::wrappers::ReceiverStream<Result<pb::DataChunk, Status>>;

    async fn stream_public(
        &self,
        request: Request<pb::StreamPublicDataRequest>,
    ) -> Result<Response<Self::StreamPublicStream>, Status> {
        let addr = DataAddress::from_hex(&request.into_inner().address)
            .map_err(|e| Status::invalid_argument(format!("invalid address: {e}")))?;
        let data_stream = self.state.client.data_stream_public(&addr).await.map_err(|e| to_status(e.into()))?;

        let (tx, rx) = tokio::sync::mpsc::channel(32);
        tokio::spawn(async move {
            for chunk_result in data_stream {
                let msg = match chunk_result {
                    Ok(chunk) => Ok(pb::DataChunk { data: chunk.to_vec() }),
                    Err(e) => Err(to_status(e.into())),
                };
                if tx.send(msg).await.is_err() {
                    break;
                }
            }
        });

        Ok(Response::new(tokio_stream::wrappers::ReceiverStream::new(rx)))
    }

    async fn get_private(
        &self,
        request: Request<pb::GetPrivateDataRequest>,
    ) -> Result<Response<pb::GetPrivateDataResponse>, Status> {
        let dm_hex = &request.into_inner().data_map;
        let chunk_bytes = hex::decode(dm_hex).map_err(|e| Status::invalid_argument(format!("invalid hex: {e}")))?;
        let data_map: autonomi::chunk::DataMapChunk =
            rmp_serde::from_slice(&chunk_bytes).map_err(|e| Status::invalid_argument(format!("invalid data map: {e}")))?;
        let data = self.state.client.data_get(&data_map).await.map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::GetPrivateDataResponse { data: data.to_vec() }))
    }

    async fn put_private(
        &self,
        request: Request<pb::PutPrivateDataRequest>,
    ) -> Result<Response<pb::PutPrivateDataResponse>, Status> {
        let data = request.into_inner().data;
        let (cost, data_map) = self
            .state
            .client
            .data_put(Bytes::from(data), wallet(&self.state))
            .await
            .map_err(|e| to_status(e.into()))?;
        let dm_bytes = rmp_serde::to_vec(&data_map).map_err(|e| Status::internal(format!("serialize: {e}")))?;
        Ok(Response::new(pb::PutPrivateDataResponse {
            cost: Some(pb::Cost { atto_tokens: cost.to_string() }),
            data_map: hex::encode(&dm_bytes),
        }))
    }

    async fn get_cost(
        &self,
        request: Request<pb::DataCostRequest>,
    ) -> Result<Response<pb::Cost>, Status> {
        let data = request.into_inner().data;
        let cost = self.state.client.data_cost(Bytes::from(data)).await.map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::Cost { atto_tokens: cost.to_string() }))
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
        let addr = ChunkAddress::from_hex(&request.into_inner().address)
            .map_err(|e| Status::invalid_argument(format!("invalid address: {e}")))?;
        let chunk = self.state.client.chunk_get(&addr).await.map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::GetChunkResponse { data: chunk.value().to_vec() }))
    }

    async fn put(
        &self,
        request: Request<pb::PutChunkRequest>,
    ) -> Result<Response<pb::PutChunkResponse>, Status> {
        let data = request.into_inner().data;
        let chunk = Chunk::new(Bytes::from(data));
        let (cost, address) = self
            .state
            .client
            .chunk_put(&chunk, wallet(&self.state))
            .await
            .map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::PutChunkResponse {
            cost: Some(pb::Cost { atto_tokens: cost.to_string() }),
            address: address.to_hex(),
        }))
    }
}

// ── GraphService ──

pub struct GraphServiceImpl {
    pub state: Arc<AppState>,
}

#[tonic::async_trait]
impl pb::graph_service_server::GraphService for GraphServiceImpl {
    async fn get(
        &self,
        request: Request<pb::GetGraphEntryRequest>,
    ) -> Result<Response<pb::GetGraphEntryResponse>, Status> {
        let addr = GraphEntryAddress::from_hex(&request.into_inner().address)
            .map_err(|e| Status::invalid_argument(format!("invalid address: {e}")))?;
        let entry = self.state.client.graph_entry_get(&addr).await.map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::GetGraphEntryResponse {
            owner: entry.owner.to_hex(),
            parents: entry.parents.iter().map(|p| p.to_hex()).collect(),
            content: hex::encode(entry.content),
            descendants: entry.descendants.iter().map(|(pk, c)| pb::GraphDescendant {
                public_key: pk.to_hex(),
                content: hex::encode(c),
            }).collect(),
        }))
    }

    async fn check_existence(
        &self,
        request: Request<pb::CheckGraphEntryRequest>,
    ) -> Result<Response<pb::GraphExistsResponse>, Status> {
        let addr = GraphEntryAddress::from_hex(&request.into_inner().address)
            .map_err(|e| Status::invalid_argument(format!("invalid address: {e}")))?;
        let exists = self.state.client.graph_entry_check_existence(&addr).await.map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::GraphExistsResponse { exists }))
    }

    async fn put(
        &self,
        request: Request<pb::PutGraphEntryRequest>,
    ) -> Result<Response<pb::PutGraphEntryResponse>, Status> {
        let req = request.into_inner();
        let owner = parse_secret_key(&req.owner_secret_key)?;
        let parents = req.parents.iter()
            .map(|p| PublicKey::from_hex(p).map_err(|e| Status::invalid_argument(format!("invalid parent key: {e}"))))
            .collect::<Result<Vec<_>, _>>()?;
        let content = parse_graph_content(&req.content)?;
        let descendants = req.descendants.iter()
            .map(|d| {
                let pk = PublicKey::from_hex(&d.public_key).map_err(|e| Status::invalid_argument(format!("invalid descendant key: {e}")))?;
                let c = parse_graph_content(&d.content)?;
                Ok((pk, c))
            })
            .collect::<Result<Vec<_>, Status>>()?;

        let entry = GraphEntry::new(&owner, parents, content, descendants);
        let (cost, address) = self.state.client.graph_entry_put(entry, wallet(&self.state)).await.map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::PutGraphEntryResponse {
            cost: Some(pb::Cost { atto_tokens: cost.to_string() }),
            address: address.to_hex(),
        }))
    }

    async fn get_cost(
        &self,
        request: Request<pb::GraphEntryCostRequest>,
    ) -> Result<Response<pb::Cost>, Status> {
        let pk = PublicKey::from_hex(&request.into_inner().public_key)
            .map_err(|e| Status::invalid_argument(format!("invalid public key: {e}")))?;
        let cost = self.state.client.graph_entry_cost(&pk).await.map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::Cost { atto_tokens: cost.to_string() }))
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
        let path = PathBuf::from(&request.into_inner().path);
        let (cost, address) = self.state.client
            .file_content_upload_public(path, wallet(&self.state).into())
            .await
            .map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::UploadPublicResponse {
            cost: Some(pb::Cost { atto_tokens: cost.to_string() }),
            address: address.to_hex(),
        }))
    }

    async fn download_public(
        &self,
        request: Request<pb::DownloadPublicRequest>,
    ) -> Result<Response<pb::DownloadResponse>, Status> {
        let req = request.into_inner();
        let addr = DataAddress::from_hex(&req.address)
            .map_err(|e| Status::invalid_argument(format!("invalid address: {e}")))?;
        self.state.client.file_download_public(&addr, PathBuf::from(&req.dest_path)).await.map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::DownloadResponse {}))
    }

    async fn dir_upload_public(
        &self,
        request: Request<pb::UploadFileRequest>,
    ) -> Result<Response<pb::UploadPublicResponse>, Status> {
        let path = PathBuf::from(&request.into_inner().path);
        let (cost, address) = self.state.client.dir_upload_public(path, &self.state.wallet).await.map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::UploadPublicResponse {
            cost: Some(pb::Cost { atto_tokens: cost.to_string() }),
            address: address.to_hex(),
        }))
    }

    async fn dir_download_public(
        &self,
        request: Request<pb::DownloadPublicRequest>,
    ) -> Result<Response<pb::DownloadResponse>, Status> {
        let req = request.into_inner();
        let addr = DataAddress::from_hex(&req.address)
            .map_err(|e| Status::invalid_argument(format!("invalid address: {e}")))?;
        self.state.client.dir_download_public(&addr, PathBuf::from(&req.dest_path)).await.map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::DownloadResponse {}))
    }

    async fn archive_get_public(
        &self,
        request: Request<pb::ArchiveGetRequest>,
    ) -> Result<Response<pb::ArchiveGetResponse>, Status> {
        let addr = DataAddress::from_hex(&request.into_inner().address)
            .map_err(|e| Status::invalid_argument(format!("invalid address: {e}")))?;
        let archive = self.state.client.archive_get_public(&addr).await.map_err(|e| to_status(e.into()))?;
        let entries = archive.iter().map(|(path, addr, meta)| pb::ArchiveEntry {
            path: path.display().to_string(),
            address: addr.to_hex(),
            created: meta.created,
            modified: meta.modified,
            size: meta.size,
        }).collect();
        Ok(Response::new(pb::ArchiveGetResponse { entries }))
    }

    async fn archive_put_public(
        &self,
        request: Request<pb::ArchivePutRequest>,
    ) -> Result<Response<pb::ArchivePutResponse>, Status> {
        let req = request.into_inner();
        let mut archive = PublicArchive::new();
        for entry in &req.entries {
            let addr = DataAddress::from_hex(&entry.address)
                .map_err(|e| Status::invalid_argument(format!("invalid address: {e}")))?;
            let meta = Metadata {
                created: entry.created,
                modified: entry.modified,
                size: entry.size,
                extra: None,
            };
            archive.add_file(PathBuf::from(&entry.path), addr, meta);
        }
        let (cost, address) = self.state.client.archive_put_public(&archive, wallet(&self.state)).await.map_err(|e| to_status(e.into()))?;
        Ok(Response::new(pb::ArchivePutResponse {
            cost: Some(pb::Cost { atto_tokens: cost.to_string() }),
            address: address.to_hex(),
        }))
    }

    async fn get_file_cost(
        &self,
        request: Request<pb::FileCostRequest>,
    ) -> Result<Response<pb::Cost>, Status> {
        let req = request.into_inner();
        let path = PathBuf::from(&req.path);
        let cost = self.state.client.file_cost(&path, req.is_public, req.include_archive).await
            .map_err(|e| Status::internal(format!("file cost error: {e}")))?;
        Ok(Response::new(pb::Cost { atto_tokens: cost.to_string() }))
    }
}

// ── EventService ──

pub struct EventServiceImpl {
    #[allow(dead_code)]
    pub state: Arc<AppState>,
}

#[tonic::async_trait]
impl pb::event_service_server::EventService for EventServiceImpl {
    type SubscribeStream = tokio_stream::wrappers::ReceiverStream<Result<pb::ClientEventProto, Status>>;

    async fn subscribe(
        &self,
        _request: Request<pb::SubscribeRequest>,
    ) -> Result<Response<Self::SubscribeStream>, Status> {
        // Events require enabling on the client - return empty stream for now
        let (_tx, rx) = tokio::sync::mpsc::channel(1);
        Ok(Response::new(tokio_stream::wrappers::ReceiverStream::new(rx)))
    }
}
