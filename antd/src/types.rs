use serde::{Deserialize, Serialize};

// ── Data ──

#[derive(Deserialize)]
pub struct DataPutRequest {
    pub data: String, // base64
}

#[derive(Serialize)]
pub struct DataPutPublicResponse {
    pub cost: String,
    pub address: String,
}

#[derive(Serialize)]
pub struct DataGetResponse {
    pub data: String, // base64
}

#[derive(Deserialize)]
pub struct DataCostRequest {
    pub data: String, // base64
}

#[derive(Serialize)]
pub struct DataPutPrivateResponse {
    pub cost: String,
    pub data_map: String, // hex
}

#[derive(Deserialize)]
pub struct DataGetPrivateQuery {
    pub data_map: String, // hex
}

// ── Chunks ──

#[derive(Deserialize)]
pub struct ChunkPutRequest {
    pub data: String, // base64
}

#[derive(Serialize)]
pub struct ChunkPutResponse {
    pub cost: String,
    pub address: String,
}

#[derive(Serialize)]
pub struct ChunkGetResponse {
    pub data: String, // base64
}

// ── Graph ──

#[derive(Deserialize)]
pub struct GraphEntryPutRequest {
    pub owner_secret_key: String,              // hex
    pub parents: Vec<String>,                  // hex public keys
    pub content: String,                       // hex, 32 bytes
    pub descendants: Vec<GraphDescendantDto>,
}

#[derive(Serialize, Deserialize)]
pub struct GraphDescendantDto {
    pub public_key: String, // hex
    pub content: String,    // hex, 32 bytes
}

#[derive(Serialize)]
pub struct GraphEntryPutResponse {
    pub cost: String,
    pub address: String,
}

#[derive(Serialize)]
pub struct GraphEntryGetResponse {
    pub owner: String,
    pub parents: Vec<String>,
    pub content: String,
    pub descendants: Vec<GraphDescendantDto>,
}

#[derive(Deserialize)]
pub struct GraphEntryCostRequest {
    pub public_key: String, // hex
}

// ── Files ──

#[derive(Deserialize)]
pub struct FileUploadRequest {
    pub path: String,
}

#[derive(Serialize)]
pub struct FileUploadPublicResponse {
    pub cost: String,
    pub address: String,
}

#[derive(Deserialize)]
pub struct FileDownloadRequest {
    pub address: String,
    pub dest_path: String,
}

#[derive(Serialize)]
pub struct DirUploadPublicResponse {
    pub cost: String,
    pub address: String,
}

// ── Archives ──

#[derive(Serialize, Deserialize)]
pub struct ArchiveEntryDto {
    pub path: String,
    pub address: String,
    pub created: u64,
    pub modified: u64,
    pub size: u64,
}

#[derive(Serialize, Deserialize)]
pub struct ArchiveDto {
    pub entries: Vec<ArchiveEntryDto>,
}

#[derive(Serialize)]
pub struct ArchivePutResponse {
    pub cost: String,
    pub address: String,
}

// ── Cost ──

#[derive(Serialize)]
pub struct CostResponse {
    pub cost: String,
}

#[derive(Deserialize)]
#[allow(dead_code)]
pub struct CostEstimateRequest {
    pub content_addrs: Vec<CostEstimateEntry>,
}

#[derive(Deserialize)]
#[allow(dead_code)]
pub struct CostEstimateEntry {
    pub xorname: String, // hex
    pub size: usize,
}

#[derive(Deserialize)]
pub struct FileCostRequest {
    pub path: String,
    #[serde(default = "default_true")]
    pub is_public: bool,
    #[serde(default)]
    pub include_archive: bool,
}

fn default_true() -> bool {
    true
}

// ── Health ──

#[derive(Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub network: String,
}

// ── Events ──

#[derive(Serialize)]
#[allow(dead_code)]
pub struct ClientEventDto {
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub records_paid: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub records_already_paid: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tokens_spent: Option<String>,
}
