use autonomi::register::RegisterAddress as AutonomiRegisterAddress;
use std::sync::Arc;

use crate::keys::{PublicKey, SecretKey};

#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum RegisterError {
    #[error("Invalid register: {reason}")]
    InvalidRegister { reason: String },
    #[error("Parsing failed: {reason}")]
    ParsingFailed { reason: String },
}

#[derive(uniffi::Object, Clone, Copy, Debug)]
pub struct RegisterAddress {
    pub(crate) inner: AutonomiRegisterAddress,
}

#[uniffi::export]
impl RegisterAddress {
    #[uniffi::constructor]
    pub fn new(owner: Arc<PublicKey>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiRegisterAddress::new(owner.inner),
        })
    }

    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, RegisterError> {
        let inner =
            AutonomiRegisterAddress::from_hex(&hex).map_err(|e| RegisterError::ParsingFailed {
                reason: format!("Failed to parse hex: {}", e),
            })?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn owner(&self) -> Arc<PublicKey> {
        Arc::new(PublicKey {
            inner: self.inner.owner(),
        })
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }
}

#[uniffi::export]
pub fn register_key_from_name(owner: Arc<SecretKey>, name: String) -> Arc<SecretKey> {
    let key = autonomi::Client::register_key_from_name(&owner.inner, &name);
    Arc::new(SecretKey { inner: key })
}

#[uniffi::export]
pub fn register_value_from_bytes(bytes: Vec<u8>) -> Result<Vec<u8>, RegisterError> {
    let value = autonomi::Client::register_value_from_bytes(&bytes).map_err(|e| {
        RegisterError::InvalidRegister {
            reason: format!("Invalid register value: {}", e),
        }
    })?;
    Ok(value.to_vec())
}
