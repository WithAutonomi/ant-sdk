use blsttc::{PublicKey as AutonomiPublicKey, SecretKey as AutonomiSecretKey};
use std::sync::Arc;

#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum KeyError {
    #[error("Invalid key: {reason}")]
    InvalidKey { reason: String },
    #[error("Parsing failed: {reason}")]
    ParsingFailed { reason: String },
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct SecretKey {
    pub(crate) inner: AutonomiSecretKey,
}

#[uniffi::export]
impl SecretKey {
    #[uniffi::constructor]
    pub fn random() -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiSecretKey::random(),
        })
    }

    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, KeyError> {
        let inner = AutonomiSecretKey::from_hex(&hex).map_err(|e| KeyError::ParsingFailed {
            reason: format!("Failed to parse hex: {}", e),
        })?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }

    pub fn public_key(&self) -> Arc<PublicKey> {
        Arc::new(PublicKey {
            inner: self.inner.public_key(),
        })
    }
}

#[derive(uniffi::Object, Clone, Copy, Debug)]
pub struct PublicKey {
    pub(crate) inner: AutonomiPublicKey,
}

#[uniffi::export]
impl PublicKey {
    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, KeyError> {
        let inner = AutonomiPublicKey::from_hex(&hex).map_err(|e| KeyError::ParsingFailed {
            reason: format!("Failed to parse hex: {}", e),
        })?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }
}
