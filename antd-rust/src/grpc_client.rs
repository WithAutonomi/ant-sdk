use tonic::transport::{Channel, Endpoint};

use crate::discover::discover_grpc_target;
use crate::errors::AntdError;
use crate::models::*;

/// Generated protobuf types for the antd gRPC API.
pub mod proto {
    pub mod antd {
        pub mod v1 {
            tonic::include_proto!("antd.v1");
        }
    }
}

use proto::antd::v1::{
    chunk_service_client::ChunkServiceClient,
    data_service_client::DataServiceClient,
    file_service_client::FileServiceClient,
    graph_service_client::GraphServiceClient,
    health_service_client::HealthServiceClient,
};

/// Default gRPC endpoint of the antd daemon.
pub const DEFAULT_GRPC_ENDPOINT: &str = "http://localhost:50051";

/// gRPC client for the antd daemon.
///
/// Provides the same 19 async methods as [`crate::Client`] but communicates
/// over gRPC instead of REST/JSON.
#[derive(Debug, Clone)]
pub struct GrpcClient {
    health: HealthServiceClient<Channel>,
    data: DataServiceClient<Channel>,
    chunks: ChunkServiceClient<Channel>,
    graph: GraphServiceClient<Channel>,
    files: FileServiceClient<Channel>,
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
        let endpoint = discover_grpc_target()
            .unwrap_or_else(|| DEFAULT_GRPC_ENDPOINT.to_string());
        Self::connect(&endpoint).await
    }

    /// Connects to the antd gRPC server at the given endpoint.
    pub async fn connect(endpoint: &str) -> Result<Self, AntdError> {
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| AntdError::Internal(format!("invalid endpoint: {e}")))?
            .connect()
            .await
            .map_err(|e| AntdError::Internal(format!("grpc connect: {e}")))?;

        Ok(Self {
            health: HealthServiceClient::new(channel.clone()),
            data: DataServiceClient::new(channel.clone()),
            chunks: ChunkServiceClient::new(channel.clone()),
            graph: GraphServiceClient::new(channel.clone()),
            files: FileServiceClient::new(channel),
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
        })
    }

    // --- Data ---

    /// Stores public immutable data on the network.
    pub async fn data_put_public(&self, data: &[u8]) -> Result<PutResult, AntdError> {
        let resp = self
            .data
            .clone()
            .put_public(proto::antd::v1::PutPublicDataRequest {
                data: data.to_vec(),
            })
            .await?
            .into_inner();

        let cost = resp
            .cost
            .map(|c| c.atto_tokens)
            .unwrap_or_default();

        Ok(PutResult {
            cost,
            address: resp.address,
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

    /// Stores private encrypted data on the network.
    pub async fn data_put_private(&self, data: &[u8]) -> Result<PutResult, AntdError> {
        let resp = self
            .data
            .clone()
            .put_private(proto::antd::v1::PutPrivateDataRequest {
                data: data.to_vec(),
            })
            .await?
            .into_inner();

        let cost = resp
            .cost
            .map(|c| c.atto_tokens)
            .unwrap_or_default();

        Ok(PutResult {
            cost,
            address: resp.data_map,
        })
    }

    /// Retrieves private data using a data map.
    pub async fn data_get_private(&self, data_map: &str) -> Result<Vec<u8>, AntdError> {
        let resp = self
            .data
            .clone()
            .get_private(proto::antd::v1::GetPrivateDataRequest {
                data_map: data_map.to_string(),
            })
            .await?
            .into_inner();

        Ok(resp.data)
    }

    /// Estimates the cost of storing data.
    pub async fn data_cost(&self, data: &[u8]) -> Result<String, AntdError> {
        let resp = self
            .data
            .clone()
            .get_cost(proto::antd::v1::DataCostRequest {
                data: data.to_vec(),
            })
            .await?
            .into_inner();

        Ok(resp.atto_tokens)
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

        let cost = resp
            .cost
            .map(|c| c.atto_tokens)
            .unwrap_or_default();

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

    // --- Graph ---

    /// Creates a new graph entry (DAG node).
    pub async fn graph_entry_put(
        &self,
        owner_secret_key: &str,
        parents: &[String],
        content: &str,
        descendants: &[GraphDescendant],
    ) -> Result<PutResult, AntdError> {
        let proto_descendants: Vec<proto::antd::v1::GraphDescendant> = descendants
            .iter()
            .map(|d| proto::antd::v1::GraphDescendant {
                public_key: d.public_key.clone(),
                content: d.content.clone(),
            })
            .collect();

        let resp = self
            .graph
            .clone()
            .put(proto::antd::v1::PutGraphEntryRequest {
                owner_secret_key: owner_secret_key.to_string(),
                parents: parents.to_vec(),
                content: content.to_string(),
                descendants: proto_descendants,
            })
            .await?
            .into_inner();

        let cost = resp
            .cost
            .map(|c| c.atto_tokens)
            .unwrap_or_default();

        Ok(PutResult {
            cost,
            address: resp.address,
        })
    }

    /// Retrieves a graph entry by address.
    pub async fn graph_entry_get(&self, address: &str) -> Result<GraphEntry, AntdError> {
        let resp = self
            .graph
            .clone()
            .get(proto::antd::v1::GetGraphEntryRequest {
                address: address.to_string(),
            })
            .await?
            .into_inner();

        let descendants = resp
            .descendants
            .into_iter()
            .map(|d| GraphDescendant {
                public_key: d.public_key,
                content: d.content,
            })
            .collect();

        Ok(GraphEntry {
            owner: resp.owner,
            parents: resp.parents,
            content: resp.content,
            descendants,
        })
    }

    /// Checks if a graph entry exists at the given address.
    pub async fn graph_entry_exists(&self, address: &str) -> Result<bool, AntdError> {
        let resp = self
            .graph
            .clone()
            .check_existence(proto::antd::v1::CheckGraphEntryRequest {
                address: address.to_string(),
            })
            .await?
            .into_inner();

        Ok(resp.exists)
    }

    /// Estimates the cost of creating a graph entry.
    pub async fn graph_entry_cost(&self, public_key: &str) -> Result<String, AntdError> {
        let resp = self
            .graph
            .clone()
            .get_cost(proto::antd::v1::GraphEntryCostRequest {
                public_key: public_key.to_string(),
            })
            .await?
            .into_inner();

        Ok(resp.atto_tokens)
    }

    // --- Files ---

    /// Uploads a local file to the network.
    pub async fn file_upload_public(&self, path: &str) -> Result<PutResult, AntdError> {
        let resp = self
            .files
            .clone()
            .upload_public(proto::antd::v1::UploadFileRequest {
                path: path.to_string(),
            })
            .await?
            .into_inner();

        let cost = resp
            .cost
            .map(|c| c.atto_tokens)
            .unwrap_or_default();

        Ok(PutResult {
            cost,
            address: resp.address,
        })
    }

    /// Downloads a file from the network to a local path.
    pub async fn file_download_public(
        &self,
        address: &str,
        dest_path: &str,
    ) -> Result<(), AntdError> {
        self.files
            .clone()
            .download_public(proto::antd::v1::DownloadPublicRequest {
                address: address.to_string(),
                dest_path: dest_path.to_string(),
            })
            .await?;

        Ok(())
    }

    /// Uploads a local directory to the network.
    pub async fn dir_upload_public(&self, path: &str) -> Result<PutResult, AntdError> {
        let resp = self
            .files
            .clone()
            .dir_upload_public(proto::antd::v1::UploadFileRequest {
                path: path.to_string(),
            })
            .await?
            .into_inner();

        let cost = resp
            .cost
            .map(|c| c.atto_tokens)
            .unwrap_or_default();

        Ok(PutResult {
            cost,
            address: resp.address,
        })
    }

    /// Downloads a directory from the network to a local path.
    pub async fn dir_download_public(
        &self,
        address: &str,
        dest_path: &str,
    ) -> Result<(), AntdError> {
        self.files
            .clone()
            .dir_download_public(proto::antd::v1::DownloadPublicRequest {
                address: address.to_string(),
                dest_path: dest_path.to_string(),
            })
            .await?;

        Ok(())
    }

    /// Retrieves an archive manifest by address.
    pub async fn archive_get_public(&self, address: &str) -> Result<Archive, AntdError> {
        let resp = self
            .files
            .clone()
            .archive_get_public(proto::antd::v1::ArchiveGetRequest {
                address: address.to_string(),
            })
            .await?
            .into_inner();

        let entries = resp
            .entries
            .into_iter()
            .map(|e| ArchiveEntry {
                path: e.path,
                address: e.address,
                created: e.created as i64,
                modified: e.modified as i64,
                size: e.size as i64,
            })
            .collect();

        Ok(Archive { entries })
    }

    /// Creates an archive manifest on the network.
    pub async fn archive_put_public(&self, archive: &Archive) -> Result<PutResult, AntdError> {
        let proto_entries: Vec<proto::antd::v1::ArchiveEntry> = archive
            .entries
            .iter()
            .map(|e| proto::antd::v1::ArchiveEntry {
                path: e.path.clone(),
                address: e.address.clone(),
                created: e.created as u64,
                modified: e.modified as u64,
                size: e.size as u64,
            })
            .collect();

        let resp = self
            .files
            .clone()
            .archive_put_public(proto::antd::v1::ArchivePutRequest {
                entries: proto_entries,
            })
            .await?
            .into_inner();

        let cost = resp
            .cost
            .map(|c| c.atto_tokens)
            .unwrap_or_default();

        Ok(PutResult {
            cost,
            address: resp.address,
        })
    }

    /// Estimates the cost of uploading a file.
    pub async fn file_cost(
        &self,
        path: &str,
        is_public: bool,
        include_archive: bool,
    ) -> Result<String, AntdError> {
        let resp = self
            .files
            .clone()
            .get_file_cost(proto::antd::v1::FileCostRequest {
                path: path.to_string(),
                is_public,
                include_archive,
            })
            .await?
            .into_inner();

        Ok(resp.atto_tokens)
    }
}
