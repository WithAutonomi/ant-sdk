use serde::{Deserialize, Serialize};

/// Result of a health check against the antd daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthStatus {
    pub ok: bool,
    pub network: String,
}

/// Result of a put/create operation containing cost and address.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PutResult {
    /// Cost in atto tokens as a string.
    pub cost: String,
    /// Hex-encoded address.
    pub address: String,
}

/// A descendant entry in a graph node.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphDescendant {
    /// Hex-encoded public key.
    pub public_key: String,
    /// Hex-encoded content (32 bytes).
    pub content: String,
}

/// A DAG node from the network.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphEntry {
    pub owner: String,
    pub parents: Vec<String>,
    pub content: String,
    pub descendants: Vec<GraphDescendant>,
}

/// A single entry in a file archive.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArchiveEntry {
    pub path: String,
    pub address: String,
    pub created: i64,
    pub modified: i64,
    pub size: i64,
}

/// A collection of archive entries.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Archive {
    pub entries: Vec<ArchiveEntry>,
}
