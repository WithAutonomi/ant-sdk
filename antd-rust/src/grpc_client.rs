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
    chunk_service_client::ChunkServiceClient, data_service_client::DataServiceClient,
    file_service_client::FileServiceClient, health_service_client::HealthServiceClient,
};

/// Default gRPC endpoint of the antd daemon.
pub const DEFAULT_GRPC_ENDPOINT: &str = "http://localhost:50051";

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
            version: resp.version,
            evm_network: resp.evm_network,
            uptime_seconds: resp.uptime_seconds,
            build_commit: resp.build_commit,
            payment_token_address: resp.payment_token_address,
            payment_vault_address: resp.payment_vault_address,
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
                payment_mode: String::new(),
            })
            .await?
            .into_inner();

        let cost = resp.cost.map(|c| c.atto_tokens).unwrap_or_default();

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
            .put(proto::antd::v1::PutDataRequest {
                data: data.to_vec(),
                payment_mode: String::new(),
            })
            .await?
            .into_inner();

        let cost = resp.cost.map(|c| c.atto_tokens).unwrap_or_default();

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
            .get(proto::antd::v1::GetDataRequest {
                data_map: data_map.to_string(),
            })
            .await?
            .into_inner();

        Ok(resp.data)
    }

    /// Returns a pre-upload cost breakdown for the given bytes.
    pub async fn data_cost(&self, data: &[u8]) -> Result<UploadCostEstimate, AntdError> {
        let resp = self
            .data
            .clone()
            .cost(proto::antd::v1::DataCostRequest {
                data: data.to_vec(),
                payment_mode: String::new(),
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

    // --- Files ---

    /// Uploads a local file to the network.
    pub async fn file_upload_public(&self, path: &str) -> Result<FileUploadResult, AntdError> {
        let resp = self
            .files
            .clone()
            .put_public(proto::antd::v1::PutFileRequest {
                path: path.to_string(),
                payment_mode: String::new(),
            })
            .await?
            .into_inner();

        Ok(FileUploadResult {
            address: resp.address,
            storage_cost_atto: resp.storage_cost_atto,
            gas_cost_wei: resp.gas_cost_wei,
            chunks_stored: resp.chunks_stored,
            payment_mode_used: resp.payment_mode_used,
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
            .get_public(proto::antd::v1::GetFilePublicRequest {
                address: address.to_string(),
                dest_path: dest_path.to_string(),
            })
            .await?;

        Ok(())
    }

    /// Returns a pre-upload cost breakdown for the file at `path`.
    pub async fn file_cost(
        &self,
        path: &str,
        is_public: bool,
    ) -> Result<UploadCostEstimate, AntdError> {
        let resp = self
            .files
            .clone()
            .cost(proto::antd::v1::FileCostRequest {
                path: path.to_string(),
                is_public,
                payment_mode: String::new(),
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
}
