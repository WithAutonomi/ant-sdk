use autonomi::client::vault::{
    UserData as AutonomiUserData, VaultSecretKey as AutonomiVaultSecretKey,
};
use std::sync::Arc;

#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum VaultError {
    #[error("Invalid vault key: {reason}")]
    InvalidKey { reason: String },
    #[error("Parsing failed: {reason}")]
    ParsingFailed { reason: String },
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct VaultSecretKey {
    pub(crate) inner: AutonomiVaultSecretKey,
}

#[uniffi::export]
impl VaultSecretKey {
    #[uniffi::constructor]
    pub fn random() -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiVaultSecretKey::random(),
        })
    }

    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, VaultError> {
        let inner =
            AutonomiVaultSecretKey::from_hex(&hex).map_err(|e| VaultError::ParsingFailed {
                reason: format!("Failed to parse hex: {}", e),
            })?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct UserData {
    pub(crate) inner: AutonomiUserData,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FileArchiveEntry {
    pub address: String,
    pub name: String,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct PrivateFileArchiveEntry {
    pub data_map: String,
    pub name: String,
}

#[uniffi::export]
impl UserData {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiUserData::new(),
        })
    }

    pub fn file_archives(&self) -> Vec<FileArchiveEntry> {
        self.inner
            .file_archives
            .iter()
            .map(|(addr, name)| FileArchiveEntry {
                address: addr.to_hex(),
                name: name.clone(),
            })
            .collect()
    }

    pub fn private_file_archives(&self) -> Vec<PrivateFileArchiveEntry> {
        self.inner
            .private_file_archives
            .iter()
            .map(|(data_map, name)| PrivateFileArchiveEntry {
                data_map: data_map.to_hex(),
                name: name.clone(),
            })
            .collect()
    }
}

#[derive(uniffi::Record)]
pub struct VaultGetResult {
    pub data: Vec<u8>,
    pub content_type: u64,
}
