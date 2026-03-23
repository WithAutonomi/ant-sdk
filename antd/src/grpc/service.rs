use std::sync::Arc;

use tonic::{Request, Response, Status};

use crate::state::AppState;

// Generated protobuf modules
pub mod pb {
    #![allow(dead_code)]
    tonic::include_proto!("antd.v1");
}

fn not_implemented(op: &str) -> Status {
    Status::unimplemented(format!("{op} not yet implemented for ant-node"))
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

        // Use the same chunk_get logic as REST
        // TODO: Factor out shared chunk client logic
        use ant_node::ant_protocol::{
            ChunkGetRequest as ProtoGetReq, ChunkGetResponse as ProtoGetResp,
            ChunkMessage, ChunkMessageBody,
        };
        use ant_node::client::send_and_await_chunk_response;
        use std::time::Duration;

        let connected_peers = self.state.node.connected_peers().await;
        let peer_id = connected_peers.first()
            .ok_or_else(|| Status::unavailable("not connected to any peers"))?;
        let peer_addrs: Vec<_> = self.state.bootstrap_peers.clone();

        let request_id = rand::random::<u64>();
        let msg = ChunkMessage {
            request_id,
            body: ChunkMessageBody::GetRequest(ProtoGetReq::new(address)),
        };
        let msg_bytes = msg.encode()
            .map_err(|e| Status::internal(format!("encode error: {e}")))?;

        let content: Vec<u8> = send_and_await_chunk_response(
            &self.state.node,
            peer_id,
            msg_bytes,
            request_id,
            Duration::from_secs(30),
            &peer_addrs,
            |body| match body {
                ChunkMessageBody::GetResponse(ProtoGetResp::Success { content, .. }) => {
                    Some(Ok(content))
                }
                ChunkMessageBody::GetResponse(ProtoGetResp::NotFound { .. }) => {
                    Some(Err(Status::not_found("chunk not found")))
                }
                ChunkMessageBody::GetResponse(ProtoGetResp::Error(e)) => {
                    Some(Err(Status::internal(e.to_string())))
                }
                _ => None,
            },
            |e| Status::unavailable(format!("failed to send: {e}")),
            || Status::deadline_exceeded("chunk get timed out"),
        )
        .await?;

        Ok(Response::new(pb::GetChunkResponse { data: content }))
    }

    async fn put(
        &self,
        request: Request<pb::PutChunkRequest>,
    ) -> Result<Response<pb::PutChunkResponse>, Status> {
        let data = request.into_inner().data;

        use ant_node::ant_protocol::{
            ChunkMessage, ChunkMessageBody, MAX_CHUNK_SIZE,
            ChunkPutRequest as ProtoPutReq, ChunkPutResponse as ProtoPutResp,
        };
        use ant_node::client::{compute_address, send_and_await_chunk_response};
        use std::time::Duration;

        if data.len() > MAX_CHUNK_SIZE {
            return Err(Status::invalid_argument(format!(
                "chunk size {} exceeds maximum {MAX_CHUNK_SIZE}", data.len()
            )));
        }

        let address = compute_address(&data);

        let connected_peers = self.state.node.connected_peers().await;
        let peer_id = connected_peers.first()
            .ok_or_else(|| Status::unavailable("not connected to any peers"))?;
        let peer_addrs: Vec<_> = self.state.bootstrap_peers.clone();

        let request_id = rand::random::<u64>();
        let msg = ChunkMessage {
            request_id,
            body: ChunkMessageBody::PutRequest(ProtoPutReq::new(address, data)),
        };
        let msg_bytes = msg.encode()
            .map_err(|e| Status::internal(format!("encode error: {e}")))?;

        let result_address: [u8; 32] = send_and_await_chunk_response(
            &self.state.node,
            peer_id,
            msg_bytes,
            request_id,
            Duration::from_secs(30),
            &peer_addrs,
            |body| match body {
                ChunkMessageBody::PutResponse(ProtoPutResp::Success { address }) => {
                    Some(Ok(address))
                }
                ChunkMessageBody::PutResponse(ProtoPutResp::AlreadyExists { address }) => {
                    Some(Ok(address))
                }
                ChunkMessageBody::PutResponse(ProtoPutResp::PaymentRequired { message }) => {
                    Some(Err(Status::failed_precondition(message)))
                }
                ChunkMessageBody::PutResponse(ProtoPutResp::Error(e)) => {
                    Some(Err(Status::internal(e.to_string())))
                }
                _ => None,
            },
            |e| Status::unavailable(format!("failed to send: {e}")),
            || Status::deadline_exceeded("chunk put timed out"),
        )
        .await?;

        Ok(Response::new(pb::PutChunkResponse {
            cost: Some(pb::Cost { atto_tokens: "0".into() }),
            address: hex::encode(result_address),
        }))
    }
}

// ── GraphService ──

pub struct GraphServiceImpl {
    pub state: Arc<AppState>,
}

#[tonic::async_trait]
impl pb::graph_service_server::GraphService for GraphServiceImpl {
    async fn get(&self, _r: Request<pb::GetGraphEntryRequest>) -> Result<Response<pb::GetGraphEntryResponse>, Status> {
        Err(not_implemented("graph get"))
    }
    async fn check_existence(&self, _r: Request<pb::CheckGraphEntryRequest>) -> Result<Response<pb::GraphExistsResponse>, Status> {
        Err(not_implemented("graph check existence"))
    }
    async fn put(&self, _r: Request<pb::PutGraphEntryRequest>) -> Result<Response<pb::PutGraphEntryResponse>, Status> {
        Err(not_implemented("graph put"))
    }
    async fn get_cost(&self, _r: Request<pb::GraphEntryCostRequest>) -> Result<Response<pb::Cost>, Status> {
        Err(not_implemented("graph cost"))
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
