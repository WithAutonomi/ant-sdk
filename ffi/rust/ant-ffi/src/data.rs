use autonomi::data::{
    DataAddress as AutonomiDataAddress, private::DataMapChunk as AutonomiDataMapChunk,
};
use autonomi::{Chunk as AutonomiChunk, ChunkAddress as AutonomiChunkAddress, XorName};
use bytes::Bytes;
use std::sync::Arc;

#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum DataError {
    #[error("Invalid data: {reason}")]
    InvalidData { reason: String },
    #[error("Parsing failed: {reason}")]
    ParsingFailed { reason: String },
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct Chunk {
    pub(crate) inner: AutonomiChunk,
}

#[uniffi::export]
impl Chunk {
    #[uniffi::constructor]
    pub fn new(value: Vec<u8>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiChunk::new(Bytes::from(value)),
        })
    }

    pub fn value(&self) -> Vec<u8> {
        self.inner.value().to_vec()
    }

    pub fn address(&self) -> Arc<ChunkAddress> {
        Arc::new(ChunkAddress {
            inner: *self.inner.address(),
        })
    }

    pub fn network_address(&self) -> String {
        self.inner.network_address().to_string()
    }

    pub fn size(&self) -> u64 {
        self.inner.size() as u64
    }

    pub fn is_too_big(&self) -> bool {
        self.inner.is_too_big()
    }
}

#[uniffi::export]
pub fn chunk_max_raw_size() -> u64 {
    AutonomiChunk::MAX_RAW_SIZE as u64
}

#[uniffi::export]
pub fn chunk_max_size() -> u64 {
    AutonomiChunk::MAX_SIZE as u64
}

#[derive(uniffi::Object, Clone, Copy, Debug)]
pub struct ChunkAddress {
    pub(crate) inner: AutonomiChunkAddress,
}

#[uniffi::export]
impl ChunkAddress {
    #[uniffi::constructor]
    pub fn new(bytes: Vec<u8>) -> Result<Arc<Self>, DataError> {
        if bytes.len() != 32 {
            return Err(DataError::InvalidData {
                reason: format!("XorName must be exactly 32 bytes, got {}", bytes.len()),
            });
        }
        let mut array = [0u8; 32];
        array.copy_from_slice(&bytes);
        Ok(Arc::new(Self {
            inner: AutonomiChunkAddress::new(XorName(array)),
        }))
    }

    #[uniffi::constructor]
    pub fn from_content(data: Vec<u8>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiChunkAddress::new(XorName::from_content(&data)),
        })
    }

    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, DataError> {
        let inner = AutonomiChunkAddress::from_hex(&hex).map_err(|e| DataError::ParsingFailed {
            reason: format!("Failed to parse hex: {}", e),
        })?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        self.inner.xorname().0.to_vec()
    }
}

#[derive(uniffi::Object, Clone, Copy, Debug)]
pub struct DataAddress {
    pub(crate) inner: AutonomiDataAddress,
}

#[uniffi::export]
impl DataAddress {
    #[uniffi::constructor]
    pub fn new(bytes: Vec<u8>) -> Result<Arc<Self>, DataError> {
        if bytes.len() != 32 {
            return Err(DataError::InvalidData {
                reason: format!("XorName must be exactly 32 bytes, got {}", bytes.len()),
            });
        }
        let mut array = [0u8; 32];
        array.copy_from_slice(&bytes);
        Ok(Arc::new(Self {
            inner: AutonomiDataAddress::new(XorName(array)),
        }))
    }

    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, DataError> {
        let inner = AutonomiDataAddress::from_hex(&hex).map_err(|e| DataError::ParsingFailed {
            reason: format!("Failed to parse hex: {}", e),
        })?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        self.inner.xorname().0.to_vec()
    }
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct DataMapChunk {
    pub(crate) inner: AutonomiDataMapChunk,
}

#[uniffi::export]
impl DataMapChunk {
    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, DataError> {
        let inner = AutonomiDataMapChunk::from_hex(&hex).map_err(|e| DataError::ParsingFailed {
            reason: format!("Failed to parse hex: {}", e),
        })?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }

    pub fn address(&self) -> String {
        self.inner.address().to_string()
    }
}
