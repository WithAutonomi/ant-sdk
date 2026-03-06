use autonomi::pointer::{
    Pointer as AutonomiPointer, PointerAddress as AutonomiPointerAddress,
    PointerTarget as AutonomiPointerTarget,
};
use std::sync::Arc;

use crate::data::ChunkAddress;
use crate::graph::GraphEntryAddress;
use crate::keys::{PublicKey, SecretKey};
use crate::scratchpad::ScratchpadAddress;

#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum PointerError {
    #[error("Invalid pointer: {reason}")]
    InvalidPointer { reason: String },
    #[error("Parsing failed: {reason}")]
    ParsingFailed { reason: String },
}

#[derive(uniffi::Object, Clone, Copy, Debug)]
pub struct PointerAddress {
    pub(crate) inner: AutonomiPointerAddress,
}

#[uniffi::export]
impl PointerAddress {
    #[uniffi::constructor]
    pub fn new(public_key: Arc<PublicKey>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiPointerAddress::new(public_key.inner),
        })
    }

    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, PointerError> {
        let inner =
            AutonomiPointerAddress::from_hex(&hex).map_err(|e| PointerError::ParsingFailed {
                reason: format!("Failed to parse hex: {}", e),
            })?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn owner(&self) -> Arc<PublicKey> {
        Arc::new(PublicKey {
            inner: *self.inner.owner(),
        })
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct NetworkPointer {
    pub(crate) inner: AutonomiPointer,
}

#[uniffi::export]
impl NetworkPointer {
    #[uniffi::constructor]
    pub fn new(key: Arc<SecretKey>, counter: u64, target: Arc<PointerTarget>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiPointer::new(&key.inner, counter, target.inner.clone()),
        })
    }

    pub fn address(&self) -> Arc<PointerAddress> {
        Arc::new(PointerAddress {
            inner: self.inner.address(),
        })
    }

    pub fn target(&self) -> Arc<PointerTarget> {
        Arc::new(PointerTarget {
            inner: self.inner.target().clone(),
        })
    }

    pub fn counter(&self) -> u64 {
        self.inner.counter()
    }
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct PointerTarget {
    pub(crate) inner: AutonomiPointerTarget,
}

#[uniffi::export]
impl PointerTarget {
    #[uniffi::constructor]
    pub fn chunk(addr: Arc<ChunkAddress>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiPointerTarget::ChunkAddress(addr.inner),
        })
    }

    #[uniffi::constructor]
    pub fn pointer(addr: Arc<PointerAddress>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiPointerTarget::PointerAddress(addr.inner),
        })
    }

    #[uniffi::constructor]
    pub fn graph_entry(addr: Arc<GraphEntryAddress>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiPointerTarget::GraphEntryAddress(addr.inner),
        })
    }

    #[uniffi::constructor]
    pub fn scratchpad(addr: Arc<ScratchpadAddress>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiPointerTarget::ScratchpadAddress(addr.inner),
        })
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }
}
