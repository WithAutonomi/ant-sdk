use std::sync::Arc;

use bytes::Bytes;
use tonic::{Request, Response, Status};

use crate::error::AntdError;
use crate::state::AppState;

// Generated protobuf modules
pub mod pb {
    #![allow(dead_code)]
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
    async fn get_public(&self, _r: Request<pb::GetPublicDataRequest>) -> Result<Response<pb::GetPublicDataResponse>, Status> {
        Err(not_implemented("data get public"))
    }
    async fn put_public(&self, _r: Request<pb::PutPublicDataRequest>) -> Result<Response<pb::PutPublicDataResponse>, Status> {
        Err(not_implemented("data put public"))
    }

    type StreamPublicStream = tokio_stream::wrappers::ReceiverStream<Result<pb::DataChunk, Status>>;
    async fn stream_public(&self, _r: Request<pb::StreamPublicDataRequest>) -> Result<Response<Self::StreamPublicStream>, Status> {
        Err(not_implemented("data stream public"))
    }

    async fn get_private(&self, _r: Request<pb::GetPrivateDataRequest>) -> Result<Response<pb::GetPrivateDataResponse>, Status> {
        Err(not_implemented("data get private"))
    }
    async fn put_private(&self, _r: Request<pb::PutPrivateDataRequest>) -> Result<Response<pb::PutPrivateDataResponse>, Status> {
        Err(not_implemented("data put private"))
    }
    async fn get_cost(&self, _r: Request<pb::DataCostRequest>) -> Result<Response<pb::Cost>, Status> {
        Err(not_implemented("data cost"))
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

        let chunk = self.state.client.chunk_get(&address).await
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
        let address = self.state.client.chunk_put(content).await
            .map_err(|e| tonic::Status::from(AntdError::from_core(e)))?;

        Ok(Response::new(pb::PutChunkResponse {
            cost: Some(pb::Cost { atto_tokens: String::new() }),
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
    async fn upload_public(&self, _r: Request<pb::UploadFileRequest>) -> Result<Response<pb::UploadPublicResponse>, Status> {
        Err(not_implemented("file upload public"))
    }
    async fn download_public(&self, _r: Request<pb::DownloadPublicRequest>) -> Result<Response<pb::DownloadResponse>, Status> {
        Err(not_implemented("file download public"))
    }
    async fn dir_upload_public(&self, _r: Request<pb::UploadFileRequest>) -> Result<Response<pb::UploadPublicResponse>, Status> {
        Err(not_implemented("dir upload public"))
    }
    async fn dir_download_public(&self, _r: Request<pb::DownloadPublicRequest>) -> Result<Response<pb::DownloadResponse>, Status> {
        Err(not_implemented("dir download public"))
    }
    async fn archive_get_public(&self, _r: Request<pb::ArchiveGetRequest>) -> Result<Response<pb::ArchiveGetResponse>, Status> {
        Err(not_implemented("archive get public"))
    }
    async fn archive_put_public(&self, _r: Request<pb::ArchivePutRequest>) -> Result<Response<pb::ArchivePutResponse>, Status> {
        Err(not_implemented("archive put public"))
    }
    async fn get_file_cost(&self, _r: Request<pb::FileCostRequest>) -> Result<Response<pb::Cost>, Status> {
        Err(not_implemented("file cost"))
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
        let (_tx, rx) = tokio::sync::mpsc::channel(1);
        Ok(Response::new(tokio_stream::wrappers::ReceiverStream::new(rx)))
    }
}
