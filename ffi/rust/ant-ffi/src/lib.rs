use std::sync::Arc;

mod client;
mod data;
mod files;
mod graph;
mod key_derivation;
mod keys;
mod network;
mod payment;
mod pointer;
mod register;
mod scratchpad;
mod vault;

pub use client::Client;
pub use data::{Chunk, ChunkAddress, DataAddress, DataError, DataMapChunk};
pub use files::{
    ArchiveAddress, ArchiveError, Metadata, PrivateArchive, PrivateArchiveDataMap,
    PrivateArchiveFileEntry, PublicArchive, PublicArchiveFileEntry,
};
pub use graph::{GraphDescendant, GraphEntry, GraphEntryAddress, GraphEntryError};
pub use key_derivation::{
    DerivationIndex, DerivedPubkey, DerivedSecretKey, MainPubkey, MainSecretKey, Signature,
};
pub use keys::{KeyError, PublicKey, SecretKey};
pub use network::{Network, NetworkError};
pub use payment::PaymentOption;
pub use pointer::{NetworkPointer, PointerAddress, PointerError, PointerTarget};
pub use register::{RegisterAddress, RegisterError, register_key_from_name, register_value_from_bytes};
pub use scratchpad::{Scratchpad, ScratchpadAddress, ScratchpadError};
pub use vault::{
    FileArchiveEntry, PrivateFileArchiveEntry, UserData, VaultError, VaultGetResult, VaultSecretKey,
};

uniffi::setup_scaffolding!();

// ===== Result types =====

/// Result of uploading data to the network
#[derive(uniffi::Record)]
pub struct UploadResult {
    pub price: String,
    pub address: String,
}

/// Result of uploading a chunk to the network
#[derive(uniffi::Record)]
pub struct ChunkPutResult {
    pub cost: String,
    pub address: Arc<ChunkAddress>,
}

/// Result of uploading private data to the network
#[derive(uniffi::Record)]
pub struct DataPutResult {
    pub cost: String,
    pub data_map: Arc<DataMapChunk>,
}

/// Result of creating a pointer on the network
#[derive(uniffi::Record)]
pub struct PointerCreateResult {
    pub cost: String,
    pub address: Arc<PointerAddress>,
}

/// Result of creating a scratchpad on the network
#[derive(uniffi::Record)]
pub struct ScratchpadCreateResult {
    pub cost: String,
    pub address: Arc<ScratchpadAddress>,
}

/// Result of uploading a graph entry to the network
#[derive(uniffi::Record)]
pub struct GraphEntryPutResult {
    pub cost: String,
    pub address: Arc<GraphEntryAddress>,
}

/// Result of creating a register on the network
#[derive(uniffi::Record)]
pub struct RegisterCreateResult {
    pub cost: String,
    pub address: Arc<RegisterAddress>,
}

/// Result of uploading a public archive to the network
#[derive(uniffi::Record)]
pub struct PublicArchivePutResult {
    pub cost: String,
    pub address: Arc<ArchiveAddress>,
}

/// Result of uploading a private archive to the network
#[derive(uniffi::Record)]
pub struct PrivateArchivePutResult {
    pub cost: String,
    pub data_map: Arc<DataMapChunk>,
}

/// Result of uploading a file to the network (private)
#[derive(uniffi::Record)]
pub struct FileUploadResult {
    pub cost: String,
    pub data_map: Arc<DataMapChunk>,
}

/// Result of uploading a file to the network (public)
#[derive(uniffi::Record)]
pub struct FileUploadPublicResult {
    pub cost: String,
    pub address: Arc<DataAddress>,
}

/// Result of uploading a directory to the network (private)
#[derive(uniffi::Record)]
pub struct DirUploadResult {
    pub cost: String,
    pub data_map: Arc<PrivateArchiveDataMap>,
}

/// Result of uploading a public directory to the network
#[derive(uniffi::Record)]
pub struct DirUploadPublicResult {
    pub cost: String,
    pub address: Arc<ArchiveAddress>,
}

// ===== Error types =====

/// Error type for Autonomi Client operations
#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum ClientError {
    #[error("Network error: {reason}")]
    NetworkError { reason: String },
    #[error("Client initialization failed: {reason}")]
    InitializationFailed { reason: String },
    #[error("Invalid data address: {reason}")]
    InvalidAddress { reason: String },
}

/// Error type for Wallet operations
#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum WalletError {
    #[error("Wallet creation failed: {reason}")]
    CreationFailed { reason: String },
    #[error("Balance check failed: {reason}")]
    BalanceCheckFailed { reason: String },
}
