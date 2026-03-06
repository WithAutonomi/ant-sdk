use autonomi::client::key_derivation::{
    DerivationIndex as AutonomiDerivationIndex, DerivedPubkey as AutonomiDerivedPubkey,
    DerivedSecretKey as AutonomiDerivedSecretKey, MainPubkey as AutonomiMainPubkey,
    MainSecretKey as AutonomiMainSecretKey,
};
use blsttc::Signature as AutonomiSignature;
use blsttc::rand as bls_rand;
use std::sync::Arc;

use crate::keys::{KeyError, PublicKey, SecretKey};

#[derive(uniffi::Object, Clone, Copy, Debug)]
pub struct DerivationIndex {
    pub(crate) inner: AutonomiDerivationIndex,
}

#[uniffi::export]
impl DerivationIndex {
    #[uniffi::constructor]
    pub fn random() -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiDerivationIndex::random(&mut bls_rand::thread_rng()),
        })
    }

    #[uniffi::constructor]
    pub fn from_bytes(bytes: Vec<u8>) -> Result<Arc<Self>, KeyError> {
        if bytes.len() != 32 {
            return Err(KeyError::InvalidKey {
                reason: format!(
                    "DerivationIndex must be exactly 32 bytes, got {}",
                    bytes.len()
                ),
            });
        }
        let mut array = [0u8; 32];
        array.copy_from_slice(&bytes);
        Ok(Arc::new(Self {
            inner: AutonomiDerivationIndex::from_bytes(array),
        }))
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        self.inner.into_bytes().to_vec()
    }
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct Signature {
    pub(crate) inner: AutonomiSignature,
}

#[uniffi::export]
impl Signature {
    #[uniffi::constructor]
    pub fn from_bytes(bytes: Vec<u8>) -> Result<Arc<Self>, KeyError> {
        if bytes.len() != 96 {
            return Err(KeyError::InvalidKey {
                reason: format!("Signature must be exactly 96 bytes, got {}", bytes.len()),
            });
        }
        let mut array = [0u8; 96];
        array.copy_from_slice(&bytes);
        AutonomiSignature::from_bytes(array)
            .map(|inner| Arc::new(Self { inner }))
            .map_err(|e| KeyError::ParsingFailed {
                reason: format!("Invalid signature: {}", e),
            })
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        self.inner.to_bytes().to_vec()
    }

    pub fn parity(&self) -> bool {
        self.inner.parity()
    }

    pub fn to_hex(&self) -> String {
        hex::encode(self.inner.to_bytes())
    }
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct MainSecretKey {
    pub(crate) inner: AutonomiMainSecretKey,
}

#[uniffi::export]
impl MainSecretKey {
    #[uniffi::constructor]
    pub fn new(secret_key: Arc<SecretKey>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiMainSecretKey::new(secret_key.inner.clone()),
        })
    }

    #[uniffi::constructor]
    pub fn random() -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiMainSecretKey::random(),
        })
    }

    pub fn public_key(&self) -> Arc<MainPubkey> {
        Arc::new(MainPubkey {
            inner: self.inner.public_key(),
        })
    }

    pub fn sign(&self, msg: Vec<u8>) -> Arc<Signature> {
        Arc::new(Signature {
            inner: self.inner.sign(&msg),
        })
    }

    pub fn derive_key(&self, index: Arc<DerivationIndex>) -> Arc<DerivedSecretKey> {
        Arc::new(DerivedSecretKey {
            inner: self.inner.derive_key(&index.inner),
        })
    }

    pub fn random_derived_key(&self) -> Arc<DerivedSecretKey> {
        Arc::new(DerivedSecretKey {
            inner: self.inner.random_derived_key(&mut bls_rand::thread_rng()),
        })
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        self.inner.to_bytes()
    }
}

#[derive(uniffi::Object, Clone, Copy, Debug)]
pub struct MainPubkey {
    pub(crate) inner: AutonomiMainPubkey,
}

#[uniffi::export]
impl MainPubkey {
    #[uniffi::constructor]
    pub fn new(public_key: Arc<PublicKey>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiMainPubkey::new(public_key.inner),
        })
    }

    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, KeyError> {
        AutonomiMainPubkey::from_hex(&hex)
            .map(|inner| Arc::new(Self { inner }))
            .map_err(|e| KeyError::ParsingFailed {
                reason: format!("Failed to parse hex: {}", e),
            })
    }

    pub fn verify(&self, signature: Arc<Signature>, msg: Vec<u8>) -> bool {
        self.inner.verify(&signature.inner, &msg)
    }

    pub fn derive_key(&self, index: Arc<DerivationIndex>) -> Arc<DerivedPubkey> {
        Arc::new(DerivedPubkey {
            inner: self.inner.derive_key(&index.inner),
        })
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        self.inner.to_bytes().to_vec()
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }
}

#[derive(uniffi::Object, Clone, Debug)]
pub struct DerivedSecretKey {
    pub(crate) inner: AutonomiDerivedSecretKey,
}

#[uniffi::export]
impl DerivedSecretKey {
    #[uniffi::constructor]
    pub fn new(secret_key: Arc<SecretKey>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiDerivedSecretKey::new(secret_key.inner.clone()),
        })
    }

    pub fn public_key(&self) -> Arc<DerivedPubkey> {
        Arc::new(DerivedPubkey {
            inner: self.inner.public_key(),
        })
    }

    pub fn sign(&self, msg: Vec<u8>) -> Arc<Signature> {
        Arc::new(Signature {
            inner: self.inner.sign(&msg),
        })
    }
}

#[derive(uniffi::Object, Clone, Copy, Debug)]
pub struct DerivedPubkey {
    pub(crate) inner: AutonomiDerivedPubkey,
}

#[uniffi::export]
impl DerivedPubkey {
    #[uniffi::constructor]
    pub fn new(public_key: Arc<PublicKey>) -> Arc<Self> {
        Arc::new(Self {
            inner: AutonomiDerivedPubkey::new(public_key.inner),
        })
    }

    #[uniffi::constructor]
    pub fn from_hex(hex: String) -> Result<Arc<Self>, KeyError> {
        AutonomiDerivedPubkey::from_hex(&hex)
            .map(|inner| Arc::new(Self { inner }))
            .map_err(|e| KeyError::ParsingFailed {
                reason: format!("Failed to parse hex: {}", e),
            })
    }

    pub fn verify(&self, signature: Arc<Signature>, msg: Vec<u8>) -> bool {
        self.inner.verify(&signature.inner, &msg)
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        self.inner.to_bytes().to_vec()
    }

    pub fn to_hex(&self) -> String {
        self.inner.to_hex()
    }
}
