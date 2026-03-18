use autonomi::client::payment::PaymentOption as AutonomiPaymentOption;
use bytes::Bytes;
use std::sync::Arc;

use crate::data::{ChunkAddress, DataAddress, DataMapChunk};
use crate::files::{
    ArchiveAddress, PrivateArchive, PrivateArchiveDataMap, PublicArchive,
};
use crate::graph::{GraphEntry, GraphEntryAddress};
use crate::keys::{PublicKey, SecretKey};
use crate::network::Network;
use crate::payment::{PaymentOption, Wallet};
use crate::{
    ChunkPutResult, ClientError, DataPutResult, DirUploadPublicResult, DirUploadResult,
    FileUploadPublicResult, FileUploadResult, GraphEntryPutResult,
    PrivateArchivePutResult, PublicArchivePutResult,
    UploadResult,
};

/// Autonomi network client
#[derive(uniffi::Object)]
pub struct Client {
    inner: Arc<autonomi::Client>,
}

#[uniffi::export(async_runtime = "tokio")]
impl Client {
    // ===== Init Methods =====

    #[uniffi::constructor]
    pub async fn init() -> Result<Arc<Self>, ClientError> {
        let client =
            autonomi::Client::init()
                .await
                .map_err(|e| ClientError::InitializationFailed {
                    reason: e.to_string(),
                })?;
        Ok(Arc::new(Self {
            inner: Arc::new(client),
        }))
    }

    #[uniffi::constructor]
    pub async fn init_local() -> Result<Arc<Self>, ClientError> {
        let client = autonomi::Client::init_local().await.map_err(|e| {
            ClientError::InitializationFailed {
                reason: e.to_string(),
            }
        })?;
        Ok(Arc::new(Self {
            inner: Arc::new(client),
        }))
    }

    #[uniffi::constructor]
    pub async fn init_with_peers(
        peers: Vec<String>,
        evm_network: Arc<Network>,
        data_dir: Option<String>,
    ) -> Result<Arc<Self>, ClientError> {
        use std::str::FromStr;

        if let Some(dir) = data_dir {
            unsafe {
                std::env::set_var("HOME", &dir);
                std::env::set_var("TMPDIR", &dir);
            }
        }

        let multiaddrs: Vec<_> = peers
            .iter()
            .filter_map(|p| autonomi::Multiaddr::from_str(p).ok())
            .collect();

        if multiaddrs.is_empty() {
            return Err(ClientError::InitializationFailed {
                reason: "No valid peer addresses provided".to_string(),
            });
        }

        let local = !multiaddrs.iter().any(|addr| {
            addr.iter().any(|component| {
                use libp2p::multiaddr::Protocol;
                matches!(component, Protocol::Ip4(ip) if !ip.is_private() && !ip.is_loopback())
            })
        });

        let config = autonomi::ClientConfig {
            bootstrap_config: autonomi::BootstrapConfig {
                local,
                initial_peers: multiaddrs,
                ..Default::default()
            },
            evm_network: evm_network.inner.clone(),
            strategy: Default::default(),
            network_id: None,
        };

        let client = autonomi::Client::init_with_config(config)
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        Ok(Arc::new(Self {
            inner: Arc::new(client),
        }))
    }

    // ===== Data Methods =====

    pub async fn data_put_public(
        &self,
        data: Vec<u8>,
        payment: PaymentOption,
    ) -> Result<UploadResult, ClientError> {
        let bytes = Bytes::from(data);
        let autonomi_payment = match payment {
            PaymentOption::WalletPayment { wallet_ref } => {
                AutonomiPaymentOption::Wallet(wallet_ref.inner.clone())
            }
        };

        let (price, address) = self
            .inner
            .data_put_public(bytes, autonomi_payment)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;

        Ok(UploadResult {
            price: price.to_string(),
            address: address.to_hex(),
        })
    }

    pub async fn data_get_public(&self, address_hex: String) -> Result<Vec<u8>, ClientError> {
        let data_address = crate::data::DataAddress::from_hex(address_hex).map_err(|e| {
            ClientError::InvalidAddress {
                reason: e.to_string(),
            }
        })?;

        let bytes = self
            .inner
            .data_get_public(&data_address.inner)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;

        Ok(bytes.to_vec())
    }

    pub async fn data_put(
        &self,
        data: Vec<u8>,
        payment: PaymentOption,
    ) -> Result<DataPutResult, ClientError> {
        let bytes = Bytes::from(data);
        let autonomi_payment = match payment {
            PaymentOption::WalletPayment { wallet_ref } => {
                AutonomiPaymentOption::Wallet(wallet_ref.inner.clone())
            }
        };

        let (cost, data_map) = self
            .inner
            .data_put(bytes, autonomi_payment)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;

        Ok(DataPutResult {
            cost: cost.to_string(),
            data_map: Arc::new(DataMapChunk { inner: data_map }),
        })
    }

    pub async fn data_get(&self, data_map: Arc<DataMapChunk>) -> Result<Vec<u8>, ClientError> {
        let bytes = self
            .inner
            .data_get(&data_map.inner)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(bytes.to_vec())
    }

    pub async fn data_cost(&self, data: Vec<u8>) -> Result<String, ClientError> {
        let bytes = Bytes::from(data);
        let cost = self
            .inner
            .data_cost(bytes)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(cost.to_string())
    }

    // ===== Chunk Methods =====

    pub async fn chunk_put(
        &self,
        data: Vec<u8>,
        payment: PaymentOption,
    ) -> Result<ChunkPutResult, ClientError> {
        let chunk = autonomi::Chunk::new(Bytes::from(data));
        let autonomi_payment = match payment {
            PaymentOption::WalletPayment { wallet_ref } => {
                AutonomiPaymentOption::Wallet(wallet_ref.inner.clone())
            }
        };

        let (cost, addr) = self
            .inner
            .chunk_put(&chunk, autonomi_payment)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;

        Ok(ChunkPutResult {
            cost: cost.to_string(),
            address: Arc::new(ChunkAddress { inner: addr }),
        })
    }

    pub async fn chunk_get(&self, addr: Arc<ChunkAddress>) -> Result<Vec<u8>, ClientError> {
        let chunk = self
            .inner
            .chunk_get(&addr.inner)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(chunk.value.to_vec())
    }

    pub async fn chunk_cost(&self, addr: Arc<ChunkAddress>) -> Result<String, ClientError> {
        let cost = self
            .inner
            .chunk_cost(&addr.inner)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(cost.to_string())
    }

    // ===== Graph Entry Methods =====

    pub async fn graph_entry_get(
        &self,
        addr: Arc<GraphEntryAddress>,
    ) -> Result<Arc<GraphEntry>, ClientError> {
        let entry = self
            .inner
            .graph_entry_get(&addr.inner)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(Arc::new(GraphEntry { inner: entry }))
    }

    pub async fn graph_entry_check_existence(
        &self,
        addr: Arc<GraphEntryAddress>,
    ) -> Result<bool, ClientError> {
        let exists = self
            .inner
            .graph_entry_check_existence(&addr.inner)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(exists)
    }

    pub async fn graph_entry_put(
        &self,
        entry: Arc<GraphEntry>,
        payment: PaymentOption,
    ) -> Result<GraphEntryPutResult, ClientError> {
        let autonomi_payment = match payment {
            PaymentOption::WalletPayment { wallet_ref } => {
                AutonomiPaymentOption::Wallet(wallet_ref.inner.clone())
            }
        };

        let (cost, addr) = self
            .inner
            .graph_entry_put(entry.inner.clone(), autonomi_payment)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;

        Ok(GraphEntryPutResult {
            cost: cost.to_string(),
            address: Arc::new(GraphEntryAddress { inner: addr }),
        })
    }

    pub async fn graph_entry_cost(&self, key: Arc<PublicKey>) -> Result<String, ClientError> {
        let cost = self
            .inner
            .graph_entry_cost(&key.inner)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(cost.to_string())
    }

    // ===== Archive Methods =====

    pub async fn archive_cost(
        &self,
        archive: Arc<PublicArchive>,
    ) -> Result<String, ClientError> {
        let cost = self
            .inner
            .archive_cost(&archive.inner)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(cost.to_string())
    }

    pub async fn archive_get_public(
        &self,
        address: Arc<ArchiveAddress>,
    ) -> Result<Arc<PublicArchive>, ClientError> {
        let archive = self
            .inner
            .archive_get_public(&address.inner)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(Arc::new(PublicArchive { inner: archive }))
    }

    pub async fn archive_put_public(
        &self,
        archive: Arc<PublicArchive>,
        payment: PaymentOption,
    ) -> Result<PublicArchivePutResult, ClientError> {
        let autonomi_payment = match payment {
            PaymentOption::WalletPayment { wallet_ref } => {
                AutonomiPaymentOption::Wallet(wallet_ref.inner.clone())
            }
        };

        let (cost, addr) = self
            .inner
            .archive_put_public(&archive.inner, autonomi_payment)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;

        Ok(PublicArchivePutResult {
            cost: cost.to_string(),
            address: Arc::new(ArchiveAddress { inner: addr }),
        })
    }

    pub async fn archive_get(
        &self,
        data_map: Arc<DataMapChunk>,
    ) -> Result<Arc<PrivateArchive>, ClientError> {
        let archive = self
            .inner
            .archive_get(&data_map.inner)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(Arc::new(PrivateArchive { inner: archive }))
    }

    pub async fn archive_put(
        &self,
        archive: Arc<PrivateArchive>,
        payment: PaymentOption,
    ) -> Result<PrivateArchivePutResult, ClientError> {
        let autonomi_payment = match payment {
            PaymentOption::WalletPayment { wallet_ref } => {
                AutonomiPaymentOption::Wallet(wallet_ref.inner.clone())
            }
        };

        let (cost, data_map) = self
            .inner
            .archive_put(&archive.inner, autonomi_payment)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;

        Ok(PrivateArchivePutResult {
            cost: cost.to_string(),
            data_map: Arc::new(DataMapChunk { inner: data_map }),
        })
    }

    // ===== File Operations =====

    pub async fn file_cost(
        &self,
        path: String,
        follow_symlinks: bool,
        include_hidden: bool,
    ) -> Result<String, ClientError> {
        let path = std::path::PathBuf::from(path);
        let cost = self
            .inner
            .file_cost(&path, follow_symlinks, include_hidden)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(cost.to_string())
    }

    pub async fn file_upload(
        &self,
        path: String,
        payment: PaymentOption,
    ) -> Result<FileUploadResult, ClientError> {
        let path = std::path::PathBuf::from(path);
        let autonomi_payment = match payment {
            PaymentOption::WalletPayment { wallet_ref } => {
                AutonomiPaymentOption::Wallet(wallet_ref.inner.clone())
            }
        };

        let (cost, data_map) = self
            .inner
            .file_content_upload(path, autonomi_payment.into())
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;

        Ok(FileUploadResult {
            cost: cost.to_string(),
            data_map: Arc::new(DataMapChunk { inner: data_map }),
        })
    }

    pub async fn file_upload_public(
        &self,
        path: String,
        payment: PaymentOption,
    ) -> Result<FileUploadPublicResult, ClientError> {
        let path = std::path::PathBuf::from(path);
        let autonomi_payment = match payment {
            PaymentOption::WalletPayment { wallet_ref } => {
                AutonomiPaymentOption::Wallet(wallet_ref.inner.clone())
            }
        };

        let (cost, addr) = self
            .inner
            .file_content_upload_public(path, autonomi_payment.into())
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;

        Ok(FileUploadPublicResult {
            cost: cost.to_string(),
            address: Arc::new(DataAddress { inner: addr }),
        })
    }

    pub async fn file_download(
        &self,
        data_map: Arc<DataMapChunk>,
        path: String,
    ) -> Result<(), ClientError> {
        let path = std::path::PathBuf::from(path);
        self.inner
            .file_download(&data_map.inner, path)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(())
    }

    pub async fn file_download_public(
        &self,
        address: Arc<DataAddress>,
        path: String,
    ) -> Result<(), ClientError> {
        let path = std::path::PathBuf::from(path);
        self.inner
            .file_download_public(&address.inner, path)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(())
    }

    pub async fn dir_upload(
        &self,
        path: String,
        wallet: Arc<Wallet>,
    ) -> Result<DirUploadResult, ClientError> {
        let path = std::path::PathBuf::from(path);

        let (cost, data_map) = self
            .inner
            .dir_upload(path, &wallet.inner)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;

        Ok(DirUploadResult {
            cost: cost.to_string(),
            data_map: Arc::new(PrivateArchiveDataMap { inner: data_map }),
        })
    }

    pub async fn dir_upload_public(
        &self,
        path: String,
        wallet: Arc<Wallet>,
    ) -> Result<DirUploadPublicResult, ClientError> {
        let path = std::path::PathBuf::from(path);

        let (cost, addr) = self
            .inner
            .dir_upload_public(path, &wallet.inner)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;

        Ok(DirUploadPublicResult {
            cost: cost.to_string(),
            address: Arc::new(ArchiveAddress { inner: addr }),
        })
    }

    pub async fn dir_download(
        &self,
        data_map: Arc<PrivateArchiveDataMap>,
        path: String,
    ) -> Result<(), ClientError> {
        let path = std::path::PathBuf::from(path);
        self.inner
            .dir_download(&data_map.inner, path)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(())
    }

    pub async fn dir_download_public(
        &self,
        address: Arc<ArchiveAddress>,
        path: String,
    ) -> Result<(), ClientError> {
        let path = std::path::PathBuf::from(path);
        self.inner
            .dir_download_public(&address.inner, path)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(())
    }
}
