use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use bytes::Bytes;
use tokio::sync::Mutex;
use zeroize::Zeroize;

use ant_core::data::{
    Client as CoreClient, ClientConfig, CoreNodeConfig, MultiAddr, NodeMode, P2PNode,
    PreparedUpload, finalize_batch_payment,
};

use crate::data::{format_payment_mode, parse_payment_mode};
use crate::wallet::Wallet;
use crate::{
    ChunkPutResult, ClientError, DataPutPrivateResult, DataPutPublicResult,
    FinalizeUploadResult, FilePutPublicResult, PaymentEntry, PrepareUploadResult,
};

/// Autonomi network client (wraps ant-core Client).
///
/// Provides direct access to the Autonomi network without needing
/// an antd daemon. Suitable for mobile apps (Android/iOS).
#[derive(uniffi::Object)]
pub struct Client {
    inner: CoreClient,
    /// Pending prepared uploads (external signer flow).
    pending_uploads: Mutex<HashMap<String, PreparedUpload>>,
}

#[uniffi::export(async_runtime = "tokio")]
impl Client {
    /// Connect to a local test network.
    #[uniffi::constructor]
    pub async fn connect_local() -> Result<Arc<Self>, ClientError> {
        let builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0)
            .local(true)
            .allow_loopback(true)
            .ipv6(false);

        let config = builder
            .build()
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        let node = P2PNode::new(config)
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        node.start()
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        let client = CoreClient::from_node(Arc::new(node), ClientConfig::default());

        Ok(Arc::new(Self { inner: client, pending_uploads: Mutex::new(HashMap::new()) }))
    }

    /// Connect to the network using explicit bootstrap peers.
    #[uniffi::constructor]
    pub async fn connect(peers: Vec<String>) -> Result<Arc<Self>, ClientError> {
        let mut builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0);

        for peer_str in &peers {
            let addr: MultiAddr = peer_str
                .parse()
                .map_err(|e| ClientError::InitializationFailed {
                    reason: format!("invalid peer address {peer_str}: {e}"),
                })?;
            builder = builder.bootstrap_peer(addr);
        }

        let config = builder
            .build()
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        let node = P2PNode::new(config)
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        node.start()
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        // Wait briefly for peer connections
        for _ in 0..20 {
            if !node.connected_peers().await.is_empty() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        }

        let client = CoreClient::from_node(Arc::new(node), ClientConfig::default());

        Ok(Arc::new(Self { inner: client, pending_uploads: Mutex::new(HashMap::new()) }))
    }

    /// Connect to the network with a wallet configured for write operations.
    ///
    /// Takes the wallet private key and EVM network details directly,
    /// since the wallet must be constructed fresh for ownership transfer.
    #[uniffi::constructor]
    pub async fn connect_with_wallet(
        peers: Vec<String>,
        mut private_key: String,
        rpc_url: String,
        payment_token_address: String,
        data_payments_address: String,
    ) -> Result<Arc<Self>, ClientError> {
        let mut builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0);

        for peer_str in &peers {
            let addr: MultiAddr = peer_str
                .parse()
                .map_err(|e| ClientError::InitializationFailed {
                    reason: format!("invalid peer address {peer_str}: {e}"),
                })?;
            builder = builder.bootstrap_peer(addr);
        }

        let config = builder
            .build()
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        let node = P2PNode::new(config)
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        node.start()
            .await
            .map_err(|e| ClientError::InitializationFailed {
                reason: e.to_string(),
            })?;

        for _ in 0..20 {
            if !node.connected_peers().await.is_empty() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        }

        let network = evmlib::Network::new_custom(
            &rpc_url,
            &payment_token_address,
            &data_payments_address,
            None,
        );
        let result = evmlib::wallet::Wallet::new_from_private_key(network, &private_key);
        // Clear the private key from memory as soon as possible
        private_key.zeroize();
        let wallet = result.map_err(|e| ClientError::InitializationFailed {
                reason: format!("failed to create wallet: {e}"),
            })?;

        let client =
            CoreClient::from_node(Arc::new(node), ClientConfig::default()).with_wallet(wallet);

        Ok(Arc::new(Self { inner: client, pending_uploads: Mutex::new(HashMap::new()) }))
    }

    // ===== Chunk Operations =====

    /// Store a chunk on the network.
    pub async fn chunk_put(&self, data: Vec<u8>) -> Result<ChunkPutResult, ClientError> {
        let address = self.inner.chunk_put(Bytes::from(data)).await?;
        Ok(ChunkPutResult {
            address: hex::encode(address),
        })
    }

    /// Retrieve a chunk by hex-encoded address.
    pub async fn chunk_get(&self, address_hex: String) -> Result<Vec<u8>, ClientError> {
        let address = hex_to_address(&address_hex)?;
        let chunk = self
            .inner
            .chunk_get(&address)
            .await?
            .ok_or_else(|| ClientError::NotFound {
                reason: format!("chunk {address_hex} not found"),
            })?;
        Ok(chunk.content.to_vec())
    }

    /// Check if a chunk exists on the network.
    pub async fn chunk_exists(&self, address_hex: String) -> Result<bool, ClientError> {
        let address = hex_to_address(&address_hex)?;
        Ok(self.inner.chunk_exists(&address).await?)
    }

    // ===== Data Operations =====

    /// Upload public data. Returns the address of the stored data map.
    pub async fn data_put_public(
        &self,
        data: Vec<u8>,
        payment_mode: String,
    ) -> Result<DataPutPublicResult, ClientError> {
        let mode = parse_payment_mode(&payment_mode).map_err(|e| ClientError::InvalidInput {
            reason: e,
        })?;

        let result = self
            .inner
            .data_upload_with_mode(Bytes::from(data), mode)
            .await?;

        let address = self.inner.data_map_store(&result.data_map).await?;

        Ok(DataPutPublicResult {
            address: hex::encode(address),
            chunks_stored: result.chunks_stored as u64,
            payment_mode_used: format_payment_mode(result.payment_mode_used),
        })
    }

    /// Retrieve public data by hex-encoded address.
    pub async fn data_get_public(&self, address_hex: String) -> Result<Vec<u8>, ClientError> {
        let address = hex_to_address(&address_hex)?;
        let data_map = self.inner.data_map_fetch(&address).await?;
        let content = self.inner.data_download(&data_map).await?;
        Ok(content.to_vec())
    }

    /// Upload private data. Returns the serialized data map (hex).
    pub async fn data_put_private(
        &self,
        data: Vec<u8>,
        payment_mode: String,
    ) -> Result<DataPutPrivateResult, ClientError> {
        let mode = parse_payment_mode(&payment_mode).map_err(|e| ClientError::InvalidInput {
            reason: e,
        })?;

        let result = self
            .inner
            .data_upload_with_mode(Bytes::from(data), mode)
            .await?;

        let data_map_bytes = rmp_serde::to_vec(&result.data_map).map_err(|e| {
            ClientError::InternalError {
                reason: format!("failed to serialize data map: {e}"),
            }
        })?;

        Ok(DataPutPrivateResult {
            data_map: hex::encode(data_map_bytes),
            chunks_stored: result.chunks_stored as u64,
            payment_mode_used: format_payment_mode(result.payment_mode_used),
        })
    }

    /// Retrieve private data using a hex-encoded data map.
    pub async fn data_get_private(&self, data_map_hex: String) -> Result<Vec<u8>, ClientError> {
        // Reject unreasonably large hex input (20 MB hex = 10 MB decoded)
        const MAX_HEX_INPUT: usize = 20 * 1024 * 1024;
        if data_map_hex.len() > MAX_HEX_INPUT {
            return Err(ClientError::InvalidInput {
                reason: format!(
                    "data map hex too large: {} bytes (max {})",
                    data_map_hex.len(),
                    MAX_HEX_INPUT
                ),
            });
        }
        let data_map_bytes =
            hex::decode(&data_map_hex).map_err(|e| ClientError::InvalidInput {
                reason: format!("invalid hex: {e}"),
            })?;
        let data_map: ant_core::data::DataMap =
            rmp_serde::from_slice(&data_map_bytes).map_err(|e| ClientError::InvalidInput {
                reason: format!("invalid data map: {e}"),
            })?;
        let content = self.inner.data_download(&data_map).await?;
        Ok(content.to_vec())
    }

    // ===== File Operations =====

    /// Upload a file from disk (public). Returns the address.
    pub async fn file_upload_public(
        &self,
        path: String,
        payment_mode: String,
    ) -> Result<FilePutPublicResult, ClientError> {
        let mode = parse_payment_mode(&payment_mode).map_err(|e| ClientError::InvalidInput {
            reason: e,
        })?;
        let file_path = PathBuf::from(&path);

        let result = self
            .inner
            .file_upload_with_mode(&file_path, mode)
            .await?;

        let address = self.inner.data_map_store(&result.data_map).await?;

        Ok(FilePutPublicResult {
            address: hex::encode(address),
        })
    }

    /// Download a file to disk by hex-encoded address.
    pub async fn file_download_public(
        &self,
        address_hex: String,
        dest_path: String,
    ) -> Result<(), ClientError> {
        let address = hex_to_address(&address_hex)?;
        let data_map = self.inner.data_map_fetch(&address).await?;
        let dest = PathBuf::from(&dest_path);
        self.inner
            .file_download(&data_map, &dest)
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: e.to_string(),
            })?;
        Ok(())
    }

    // ===== External Signer Operations =====

    /// Prepare a data upload for external signing.
    /// Encrypts data, collects quotes, returns payment details.
    /// Call finalize_upload() with tx hashes after signing externally.
    pub async fn prepare_data_upload(
        &self,
        data: Vec<u8>,
    ) -> Result<PrepareUploadResult, ClientError> {
        let prepared = self.inner.data_prepare_upload(Bytes::from(data)).await?;

        let payments: Vec<PaymentEntry> = prepared.payment_intent.payments.iter().map(|(qh, ra, amt)| {
            PaymentEntry {
                quote_hash: format!("{:#x}", qh),
                rewards_address: format!("{:#x}", ra),
                amount: amt.to_string(),
            }
        }).collect();

        let total_amount = prepared.payment_intent.total_amount.to_string();

        let data_map_bytes = rmp_serde::to_vec(&prepared.data_map).map_err(|e| {
            ClientError::InternalError { reason: format!("serialize data map: {e}") }
        })?;
        let data_map = hex::encode(data_map_bytes);

        let upload_id = hex::encode(rand::random::<[u8; 16]>());
        self.pending_uploads.lock().await.insert(upload_id.clone(), prepared);

        Ok(PrepareUploadResult { payments, total_amount, data_map })
    }

    /// Prepare a file upload for external signing.
    pub async fn prepare_file_upload(
        &self,
        path: String,
    ) -> Result<PrepareUploadResult, ClientError> {
        let file_path = PathBuf::from(&path);
        let prepared = self.inner.file_prepare_upload(&file_path).await?;

        let payments: Vec<PaymentEntry> = prepared.payment_intent.payments.iter().map(|(qh, ra, amt)| {
            PaymentEntry {
                quote_hash: format!("{:#x}", qh),
                rewards_address: format!("{:#x}", ra),
                amount: amt.to_string(),
            }
        }).collect();

        let total_amount = prepared.payment_intent.total_amount.to_string();

        let data_map_bytes = rmp_serde::to_vec(&prepared.data_map).map_err(|e| {
            ClientError::InternalError { reason: format!("serialize data map: {e}") }
        })?;
        let data_map = hex::encode(data_map_bytes);

        let upload_id = hex::encode(rand::random::<[u8; 16]>());
        self.pending_uploads.lock().await.insert(upload_id.clone(), prepared);

        Ok(PrepareUploadResult { payments, total_amount, data_map })
    }

    /// Finalize an upload after external payment.
    /// Takes a map of quote_hash (hex) → tx_hash (hex).
    pub async fn finalize_upload(
        &self,
        upload_id: String,
        tx_hashes: HashMap<String, String>,
    ) -> Result<FinalizeUploadResult, ClientError> {
        let prepared = self.pending_uploads.lock().await
            .remove(&upload_id)
            .ok_or_else(|| ClientError::NotFound {
                reason: format!("upload_id {upload_id} not found"),
            })?;

        let tx_hash_map: HashMap<evmlib::common::QuoteHash, evmlib::common::TxHash> =
            tx_hashes.iter().map(|(qh, th)| {
                let q: [u8; 32] = hex::decode(qh.trim_start_matches("0x"))
                    .map_err(|e| ClientError::InvalidInput { reason: format!("invalid quote_hash: {e}") })?
                    .try_into()
                    .map_err(|_| ClientError::InvalidInput { reason: "quote_hash must be 32 bytes".into() })?;
                let t: [u8; 32] = hex::decode(th.trim_start_matches("0x"))
                    .map_err(|e| ClientError::InvalidInput { reason: format!("invalid tx_hash: {e}") })?
                    .try_into()
                    .map_err(|_| ClientError::InvalidInput { reason: "tx_hash must be 32 bytes".into() })?;
                Ok((q.into(), t.into()))
            }).collect::<Result<_, ClientError>>()?;

        let result = self.inner.finalize_upload(prepared, &tx_hash_map).await?;

        Ok(FinalizeUploadResult {
            chunks_stored: result.chunks_stored as u64,
        })
    }

    // ===== Wallet Operations =====

    /// Approve token spend for storage payments (one-time).
    pub async fn wallet_approve(&self) -> Result<(), ClientError> {
        self.inner
            .approve_token_spend()
            .await
            .map_err(|e| ClientError::PaymentError {
                reason: e.to_string(),
            })?;
        Ok(())
    }
}

/// Parse a hex string into a 32-byte address.
fn hex_to_address(hex: &str) -> Result<[u8; 32], ClientError> {
    let bytes = hex::decode(hex).map_err(|e| ClientError::InvalidInput {
        reason: format!("invalid hex address: {e}"),
    })?;
    bytes
        .try_into()
        .map_err(|_| ClientError::InvalidInput {
            reason: "address must be 32 bytes".into(),
        })
}
