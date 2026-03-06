use autonomi::scratchpad::{
    Scratchpad as AutonomiScratchpad, ScratchpadAddress as AutonomiScratchpadAddress,
};
use bytes::Bytes;
use std::sync::Arc;

use crate::keys::{PublicKey, SecretKey};

#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum ScratchpadError {
    #[error("Invalid scratchpad: {reason}")]
    InvalidScratchpad { reason: String },
    #[error("Parsing failed: {reason}")]
    ParsingFailed { reason: String },
    #[error("Decryption failed: {reason}")]
    DecryptionFailed { reason: String },
}

#[derive(uniffi::Object, Clone, Copy, Debug)]
pub struct ScratchpadAddress {
    pub(crate) inner: AutonomiScratchpadAddress,
}

#[uniffi::export]
impl ScratchpadAddress {
    #[uniffi::constructor]
    pub fn new(public_key: Arc<PublicKey>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiScratchpadAddress::new(public_key.inner),
        })
    }

    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, ScratchpadError> {
        let inner = AutonomiScratchpadAddress::from_hex(&hex).map_err(|e| {
            ScratchpadError::ParsingFailed {
                reason: format!("Failed to parse hex: {}", e),
            }
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
pub struct Scratchpad {
    pub(crate) inner: AutonomiScratchpad,
}

#[uniffi::export]
impl Scratchpad {
    #[uniffi::constructor]
    pub fn new(
        owner: Arc<SecretKey>,
        data_encoding: u64,
        unencrypted_data: Vec<u8>,
        counter: u64,
    ) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiScratchpad::new(
                &owner.inner,
                data_encoding,
                &Bytes::from(unencrypted_data),
                counter,
            ),
        })
    }

    pub fn address(&self) -> Arc<ScratchpadAddress> {
        Arc::new(ScratchpadAddress {
            inner: *self.inner.address(),
        })
    }

    pub fn data_encoding(&self) -> u64 {
        self.inner.data_encoding()
    }

    pub fn counter(&self) -> u64 {
        self.inner.counter()
    }

    pub fn decrypt_data(&self, sk: Arc<SecretKey>) -> Result<Vec<u8>, ScratchpadError> {
        let data =
            self.inner
                .decrypt_data(&sk.inner)
                .map_err(|e| ScratchpadError::DecryptionFailed {
                    reason: format!("Failed to decrypt: {}", e),
                })?;
        Ok(data.to_vec())
    }

    pub fn owner(&self) -> Arc<PublicKey> {
        Arc::new(PublicKey {
            inner: *self.inner.owner(),
        })
    }

    pub fn scratchpad_hash(&self) -> String {
        hex::encode(self.inner.scratchpad_hash().0)
    }

    pub fn encrypted_data_hash(&self) -> String {
        hex::encode(self.inner.encrypted_data_hash())
    }

    pub fn encrypted_data(&self) -> Vec<u8> {
        self.inner.encrypted_data().to_vec()
    }
}
