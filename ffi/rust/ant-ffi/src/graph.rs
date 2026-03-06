use crate::keys::{PublicKey, SecretKey};
use autonomi::client::graph::{
    GraphEntry as AutonomiGraphEntry, GraphEntryAddress as AutonomiGraphEntryAddress,
};
use std::sync::Arc;

#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum GraphEntryError {
    #[error("Invalid content: {reason}")]
    InvalidContent { reason: String },
    #[error("Parsing failed: {reason}")]
    ParsingFailed { reason: String },
}

#[derive(uniffi::Object, Clone, Copy, Debug)]
pub struct GraphEntryAddress {
    pub(crate) inner: AutonomiGraphEntryAddress,
}

#[uniffi::export]
impl GraphEntryAddress {
    #[uniffi::constructor]
    pub fn new(public_key: Arc<PublicKey>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiGraphEntryAddress::new(public_key.inner),
        })
    }

    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, GraphEntryError> {
        let inner = AutonomiGraphEntryAddress::from_hex(&hex).map_err(|e| {
            GraphEntryError::ParsingFailed {
                reason: e.to_string(),
            }
        })?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct GraphDescendant {
    pub public_key: Arc<PublicKey>,
    pub content: Vec<u8>,
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct GraphEntry {
    pub(crate) inner: AutonomiGraphEntry,
}

#[uniffi::export]
impl GraphEntry {
    #[uniffi::constructor]
    pub fn new(
        owner: Arc<SecretKey>,
        parents: Vec<Arc<PublicKey>>,
        content: Vec<u8>,
        descendants: Vec<GraphDescendant>,
    ) -> Result<Arc<Self>, GraphEntryError> {
        if content.len() != 32 {
            return Err(GraphEntryError::InvalidContent {
                reason: format!("Content must be exactly 32 bytes, got {}", content.len()),
            });
        }

        let mut content_array = [0u8; 32];
        content_array.copy_from_slice(&content);

        let descendants_mapped: Vec<(blsttc::PublicKey, [u8; 32])> = descendants
            .into_iter()
            .map(|d| {
                if d.content.len() != 32 {
                    return Err(GraphEntryError::InvalidContent {
                        reason: format!(
                            "Descendant content must be exactly 32 bytes, got {}",
                            d.content.len()
                        ),
                    });
                }
                let mut desc_content = [0u8; 32];
                desc_content.copy_from_slice(&d.content);
                Ok((d.public_key.inner, desc_content))
            })
            .collect::<Result<Vec<_>, GraphEntryError>>()?;

        let inner = AutonomiGraphEntry::new(
            &owner.inner,
            parents.into_iter().map(|p| p.inner).collect(),
            content_array,
            descendants_mapped,
        );

        Ok(Arc::new(Self { inner }))
    }

    pub fn address(&self) -> Arc<GraphEntryAddress> {
        Arc::new(GraphEntryAddress {
            inner: self.inner.address(),
        })
    }

    pub fn content(&self) -> Vec<u8> {
        self.inner.content.to_vec()
    }

    pub fn parents(&self) -> Vec<Arc<PublicKey>> {
        self.inner
            .parents
            .iter()
            .map(|&p| Arc::new(PublicKey { inner: p }))
            .collect()
    }

    pub fn descendants(&self) -> Vec<GraphDescendant> {
        self.inner
            .descendants
            .iter()
            .map(|&(pk, c)| GraphDescendant {
                public_key: Arc::new(PublicKey { inner: pk }),
                content: c.to_vec(),
            })
            .collect()
    }
}
