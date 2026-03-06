use autonomi::files::archive_private::PrivateArchiveDataMap as AutonomiPrivateArchiveDataMap;
use autonomi::files::archive_public::ArchiveAddress as AutonomiArchiveAddress;
use autonomi::files::{
    Metadata as AutonomiMetadata, PrivateArchive as AutonomiPrivateArchive,
    PublicArchive as AutonomiPublicArchive,
};
use std::sync::Arc;

use crate::data::{DataAddress, DataMapChunk};

#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum ArchiveError {
    #[error("Invalid archive: {reason}")]
    InvalidArchive { reason: String },
    #[error("Parsing failed: {reason}")]
    ParsingFailed { reason: String },
    #[error("File not found: {path}")]
    FileNotFound { path: String },
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct Metadata {
    pub(crate) inner: AutonomiMetadata,
}

#[uniffi::export]
impl Metadata {
    #[uniffi::constructor]
    pub fn new(size: u64) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiMetadata::new_with_size(size),
        })
    }

    #[uniffi::constructor]
    pub fn with_timestamps(size: u64, created: u64, modified: u64) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiMetadata {
                size,
                created,
                modified,
                extra: None,
            },
        })
    }

    pub fn size(&self) -> u64 {
        self.inner.size
    }

    pub fn created(&self) -> u64 {
        self.inner.created
    }

    pub fn modified(&self) -> u64 {
        self.inner.modified
    }
}

#[derive(uniffi::Object, Clone, Copy, Debug)]
pub struct ArchiveAddress {
    pub(crate) inner: AutonomiArchiveAddress,
}

#[uniffi::export]
impl ArchiveAddress {
    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, ArchiveError> {
        let inner =
            AutonomiArchiveAddress::from_hex(&hex).map_err(|e| ArchiveError::ParsingFailed {
                reason: format!("Failed to parse hex: {}", e),
            })?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct PrivateArchiveDataMap {
    pub(crate) inner: AutonomiPrivateArchiveDataMap,
}

#[uniffi::export]
impl PrivateArchiveDataMap {
    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, ArchiveError> {
        let inner = AutonomiPrivateArchiveDataMap::from_hex(&hex).map_err(|e| {
            ArchiveError::ParsingFailed {
                reason: format!("Failed to parse hex: {}", e),
            }
        })?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }
}

#[derive(uniffi::Record)]
pub struct PublicArchiveFileEntry {
    pub path: String,
    pub address: Arc<DataAddress>,
    pub metadata: Arc<Metadata>,
}

#[derive(uniffi::Record)]
pub struct PrivateArchiveFileEntry {
    pub path: String,
    pub data_map: Arc<DataMapChunk>,
    pub metadata: Arc<Metadata>,
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct PublicArchive {
    pub(crate) inner: AutonomiPublicArchive,
}

#[uniffi::export]
impl PublicArchive {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiPublicArchive::new(),
        })
    }

    pub fn add_file(
        &self,
        path: String,
        address: Arc<DataAddress>,
        metadata: Arc<Metadata>,
    ) -> Arc<Self> {
        let mut archive = self.inner.clone();
        archive.add_file(
            std::path::PathBuf::from(path),
            address.inner,
            metadata.inner.clone(),
        );
        Arc::new(Self { inner: archive })
    }

    pub fn rename_file(
        &self,
        old_path: String,
        new_path: String,
    ) -> Result<Arc<Self>, ArchiveError> {
        let mut archive = self.inner.clone();
        archive
            .rename_file(
                &std::path::PathBuf::from(&old_path),
                &std::path::PathBuf::from(&new_path),
            )
            .map_err(|e| ArchiveError::InvalidArchive {
                reason: format!("Failed to rename file: {}", e),
            })?;
        Ok(Arc::new(Self { inner: archive }))
    }

    pub fn files(&self) -> Vec<PublicArchiveFileEntry> {
        self.inner
            .map()
            .iter()
            .map(|(path, (addr, meta))| PublicArchiveFileEntry {
                path: path.to_string_lossy().to_string(),
                address: Arc::new(DataAddress { inner: *addr }),
                metadata: Arc::new(Metadata {
                    inner: meta.clone(),
                }),
            })
            .collect()
    }

    pub fn file_count(&self) -> u64 {
        self.inner.map().len() as u64
    }

    pub fn addresses(&self) -> Vec<String> {
        self.inner
            .addresses()
            .into_iter()
            .map(|a| a.to_hex())
            .collect()
    }
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct PrivateArchive {
    pub(crate) inner: AutonomiPrivateArchive,
}

#[uniffi::export]
impl PrivateArchive {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiPrivateArchive::new(),
        })
    }

    pub fn add_file(
        &self,
        path: String,
        data_map: Arc<DataMapChunk>,
        metadata: Arc<Metadata>,
    ) -> Arc<Self> {
        let mut archive = self.inner.clone();
        archive.add_file(
            std::path::PathBuf::from(path),
            data_map.inner.clone(),
            metadata.inner.clone(),
        );
        Arc::new(Self { inner: archive })
    }

    pub fn rename_file(
        &self,
        old_path: String,
        new_path: String,
    ) -> Result<Arc<Self>, ArchiveError> {
        let mut archive = self.inner.clone();
        archive
            .rename_file(
                &std::path::PathBuf::from(&old_path),
                &std::path::PathBuf::from(&new_path),
            )
            .map_err(|e| ArchiveError::InvalidArchive {
                reason: format!("Failed to rename file: {}", e),
            })?;
        Ok(Arc::new(Self { inner: archive }))
    }

    pub fn files(&self) -> Vec<PrivateArchiveFileEntry> {
        self.inner
            .map()
            .iter()
            .map(|(path, (data_map, meta))| PrivateArchiveFileEntry {
                path: path.to_string_lossy().to_string(),
                data_map: Arc::new(DataMapChunk {
                    inner: data_map.clone(),
                }),
                metadata: Arc::new(Metadata {
                    inner: meta.clone(),
                }),
            })
            .collect()
    }

    pub fn file_count(&self) -> u64 {
        self.inner.map().len() as u64
    }

    pub fn data_maps(&self) -> Vec<Arc<DataMapChunk>> {
        self.inner
            .data_maps()
            .into_iter()
            .map(|dm| Arc::new(DataMapChunk { inner: dm }))
            .collect()
    }
}
