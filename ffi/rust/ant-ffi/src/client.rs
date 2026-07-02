use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use bytes::Bytes;
use zeroize::Zeroize;

use ant_core::data::{
    Client as CoreClient, ClientConfig, CoreNodeConfig, DevnetManifest, ExternalPaymentInfo,
    MultiAddr, NodeMode, P2PNode, PreparedUpload, Visibility, Wallet as CoreWallet,
};
use ant_protocol::evm::{QuoteHash, TxHash};

use crate::data::{format_payment_mode, parse_payment_mode};
use crate::wallet::build_custom_network;
use crate::{
    ChunkPutResult, ClientError, DataPutPrivateResult, DataPutPublicResult, ExternalUploadResult,
    FilePutPublicResult, PaymentEntry, PreparedUploadInfo,
};

/// Autonomi network client (wraps ant-core Client).
///
/// Provides direct access to the Autonomi network without needing
/// an antd daemon. Suitable for mobile apps (Android/iOS).
#[derive(uniffi::Object)]
pub struct Client {
    inner: CoreClient,
    /// External-signer prepared uploads awaiting finalize, keyed by upload_id.
    /// The `PreparedUpload` holds chunk content in memory until finalize stores
    /// it, so entries live only between `prepare_*` and `finalize_upload`.
    sessions: Mutex<HashMap<String, PreparedUpload>>,
    /// Monotonic source of unique upload_ids for this client instance.
    next_id: AtomicU64,
}

impl Client {
    /// Wrap a core client with fresh external-signer session state.
    fn wrap(inner: CoreClient) -> Arc<Self> {
        Arc::new(Self {
            inner,
            sessions: Mutex::new(HashMap::new()),
            next_id: AtomicU64::new(1),
        })
    }
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

        Ok(Self::wrap(client))
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

        Ok(Self::wrap(client))
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
        payment_vault_address: String,
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

        let network = build_custom_network(&rpc_url, &payment_token_address, &payment_vault_address)
            .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;
        let result = CoreWallet::new_from_private_key(network, &private_key);
        // Clear the private key from memory as soon as possible
        private_key.zeroize();
        let wallet = result.map_err(|e| ClientError::InitializationFailed {
                reason: format!("failed to create wallet: {e}"),
            })?;

        let client =
            CoreClient::from_node(Arc::new(node), ClientConfig::default()).with_wallet(wallet);

        Ok(Self::wrap(client))
    }

    /// Connect to a locally running devnet using the manifest JSON file the
    /// devnet wrote on startup (`LocalDevnet::write_manifest`).
    ///
    /// Reads bootstrap peers, EVM RPC URL + contract addresses, and the
    /// funded wallet private key from the manifest, then constructs a Client
    /// with the wallet attached. Suitable for **development and testing
    /// only** — production code should provide bootstrap peers and wallet
    /// material explicitly via [`Self::connect_with_wallet`].
    ///
    /// Fails if the manifest doesn't exist, is malformed, or has no `evm`
    /// section (a devnet started without payment enforcement).
    #[uniffi::constructor]
    pub async fn connect_from_devnet_manifest(path: String) -> Result<Arc<Self>, ClientError> {
        let bytes = std::fs::read(&path).map_err(|e| ClientError::InitializationFailed {
            reason: format!("failed to read manifest at {path}: {e}"),
        })?;
        let manifest: DevnetManifest = serde_json::from_slice(&bytes).map_err(|e| {
            ClientError::InitializationFailed {
                reason: format!("invalid manifest JSON: {e}"),
            }
        })?;
        let evm = manifest.evm.ok_or_else(|| ClientError::InitializationFailed {
            reason: "manifest has no `evm` section — devnet started without payments?".into(),
        })?;

        // `allow_loopback(true)` is the critical bit — the devnet's bootstrap
        // peers are at 127.0.0.1:<port>, and saorsa-core / libp2p filter
        // loopback addresses by default as "non-routable". Without this the
        // peer connections silently never form and chunk_put fails with
        // "Found 0 peers, need 7". `local(true)` mirrors `connect_local()`
        // since this constructor is also a local-devnet flow.
        let mut builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0)
            .local(true)
            .allow_loopback(true)
            .ipv6(false);
        for peer in &manifest.bootstrap {
            builder = builder.bootstrap_peer(peer.clone());
        }
        let config = builder
            .build()
            .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;
        let node = P2PNode::new(config)
            .await
            .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;
        node.start()
            .await
            .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;

        // Poll for peer connections. We need at least the close-group size
        // (~7) for chunk_put to succeed, not just "any peer" — wait up to
        // 15s for the network to stabilize.
        for _ in 0..60 {
            let count = node.connected_peers().await.len();
            if count >= 7 {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        }

        let network = build_custom_network(
            &evm.rpc_url,
            &evm.payment_token_address,
            &evm.payment_vault_address,
        )
        .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;
        let wallet = CoreWallet::new_from_private_key(network, &evm.wallet_private_key).map_err(
            |e| ClientError::InitializationFailed {
                reason: format!("failed to create wallet from manifest: {e}"),
            },
        )?;

        let client =
            CoreClient::from_node(Arc::new(node), ClientConfig::default()).with_wallet(wallet);
        Ok(Self::wrap(client))
    }

    /// Like [`Self::connect_from_devnet_manifest`] but for the **external-signer**
    /// flow: configures the devnet's EVM network for quote/price queries but
    /// attaches **no wallet** (the manifest's `wallet_private_key` may be empty
    /// — e.g. the Sepolia devnet, which expects you to bring your own wallet).
    /// Pay via `prepare_*` + an external signer + `finalize_upload`.
    #[uniffi::constructor]
    pub async fn connect_from_devnet_manifest_external_signer(
        path: String,
    ) -> Result<Arc<Self>, ClientError> {
        let bytes = std::fs::read(&path).map_err(|e| ClientError::InitializationFailed {
            reason: format!("failed to read manifest at {path}: {e}"),
        })?;
        let manifest: DevnetManifest =
            serde_json::from_slice(&bytes).map_err(|e| ClientError::InitializationFailed {
                reason: format!("invalid manifest JSON: {e}"),
            })?;
        let evm = manifest.evm.ok_or_else(|| ClientError::InitializationFailed {
            reason: "manifest has no `evm` section — devnet started without payments?".into(),
        })?;

        // Same devnet-tuned node config as the wallet variant (local +
        // loopback), so the client joins the local devnet the same way.
        let mut builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0)
            .local(true)
            .allow_loopback(true)
            .ipv6(false);
        for peer in &manifest.bootstrap {
            builder = builder.bootstrap_peer(peer.clone());
        }
        let config = builder
            .build()
            .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;
        let node = P2PNode::new(config)
            .await
            .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;
        node.start()
            .await
            .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;
        for _ in 0..60 {
            if node.connected_peers().await.len() >= 7 {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        }

        let network = build_custom_network(
            &evm.rpc_url,
            &evm.payment_token_address,
            &evm.payment_vault_address,
        )
        .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;
        let client = CoreClient::from_node(Arc::new(node), ClientConfig::default())
            .with_evm_network(network);
        Ok(Self::wrap(client))
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

    // ===== External-signer (WalletConnect) operations =====

    /// Connect with an EVM network configured but **no wallet / private key**.
    ///
    /// This is the external-signer entry point: quote collection and price
    /// queries work (they need the network), but payment is signed off-device
    /// by an external wallet (e.g. WalletConnect). Use [`Self::prepare_data_upload`]
    /// / [`Self::prepare_file_upload`] then [`Self::finalize_upload`].
    #[uniffi::constructor]
    pub async fn connect_for_external_signer(
        peers: Vec<String>,
        rpc_url: String,
        payment_token_address: String,
        payment_vault_address: String,
    ) -> Result<Arc<Self>, ClientError> {
        let mut builder = CoreNodeConfig::builder().mode(NodeMode::Client).port(0);
        for peer_str in &peers {
            let addr: MultiAddr =
                peer_str
                    .parse()
                    .map_err(|e| ClientError::InitializationFailed {
                        reason: format!("invalid peer address {peer_str}: {e}"),
                    })?;
            builder = builder.bootstrap_peer(addr);
        }
        let config = builder
            .build()
            .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;
        let node = P2PNode::new(config)
            .await
            .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;
        node.start()
            .await
            .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;
        for _ in 0..20 {
            if !node.connected_peers().await.is_empty() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        }

        let network =
            build_custom_network(&rpc_url, &payment_token_address, &payment_vault_address)
                .map_err(|e| ClientError::InitializationFailed { reason: e.to_string() })?;
        let client = CoreClient::from_node(Arc::new(node), ClientConfig::default())
            .with_evm_network(network);
        Ok(Self::wrap(client))
    }

    /// Phase 1 (external signer): encrypt `data`, collect quotes, and return
    /// the payment summary. `visibility` is `"public"` or `"private"`. The
    /// prepared state is retained under the returned `upload_id` until
    /// [`Self::finalize_upload`].
    pub async fn prepare_data_upload(
        &self,
        data: Vec<u8>,
        visibility: String,
    ) -> Result<PreparedUploadInfo, ClientError> {
        let vis = parse_visibility(&visibility)?;
        let prepared = self
            .inner
            .data_prepare_upload_with_visibility(Bytes::from(data), vis)
            .await?;
        self.stash_prepared(prepared)
    }

    /// Phase 1 (external signer): same as [`Self::prepare_data_upload`] but for
    /// a file on disk.
    pub async fn prepare_file_upload(
        &self,
        path: String,
        visibility: String,
    ) -> Result<PreparedUploadInfo, ClientError> {
        let vis = parse_visibility(&visibility)?;
        let prepared = self
            .inner
            .file_prepare_upload_with_visibility(&PathBuf::from(path), vis)
            .await?;
        self.stash_prepared(prepared)
    }

    /// Phase 2 (external signer): after the external wallet has paid
    /// (`payForQuotes`), finalize the upload by supplying the resulting
    /// `quote_hash -> tx_hash` map (both 0x-prefixed hex). Stores the chunks
    /// and returns the data map / address. `upload_id` comes from a prior
    /// `prepare_*` call. If everything was already stored, pass an empty map.
    pub async fn finalize_upload(
        &self,
        upload_id: String,
        tx_hashes: HashMap<String, String>,
    ) -> Result<ExternalUploadResult, ClientError> {
        let prepared = self
            .sessions
            .lock()
            .expect("sessions mutex poisoned")
            .remove(&upload_id)
            .ok_or_else(|| ClientError::InvalidInput {
                reason: format!("unknown or already-finalized upload_id: {upload_id}"),
            })?;

        let mut tx_hash_map: HashMap<QuoteHash, TxHash> =
            HashMap::with_capacity(tx_hashes.len());
        for (quote_hex, tx_hex) in &tx_hashes {
            let quote_bytes = decode_hash(quote_hex, "quote hash")?;
            let tx_bytes = decode_hash(tx_hex, "tx hash")?;
            tx_hash_map.insert(QuoteHash::from(quote_bytes), TxHash::from(tx_bytes));
        }

        let result = self.inner.finalize_upload(prepared, &tx_hash_map).await?;

        let data_map_bytes =
            rmp_serde::to_vec(&result.data_map).map_err(|e| ClientError::InternalError {
                reason: format!("failed to serialize data map: {e}"),
            })?;

        Ok(ExternalUploadResult {
            data_map: hex::encode(data_map_bytes),
            address: result.data_map_address.map(hex::encode),
            chunks_stored: result.chunks_stored as u64,
            storage_cost_atto: result.storage_cost_atto,
            gas_cost_wei: result.gas_cost_wei.to_string(),
        })
    }
}

impl Client {
    /// Build the FFI summary for a prepared upload and stash the heavy state
    /// under a fresh `upload_id`. Wave-batch only for now.
    fn stash_prepared(&self, prepared: PreparedUpload) -> Result<PreparedUploadInfo, ClientError> {
        let data_map_address = prepared.data_map_address.map(hex::encode);
        let (payment_type, payments, total_amount) = match &prepared.payment_info {
            ExternalPaymentInfo::WaveBatch { payment_intent, .. } => {
                let payments = payment_intent
                    .payments
                    .iter()
                    .map(|(quote_hash, rewards_addr, amount)| PaymentEntry {
                        quote_hash: format!("0x{}", hex::encode(quote_hash)),
                        rewards_address: format!("{rewards_addr}"),
                        amount: amount.to_string(),
                    })
                    .collect::<Vec<_>>();
                (
                    "wave_batch".to_string(),
                    payments,
                    payment_intent.total_amount.to_string(),
                )
            }
            ExternalPaymentInfo::Merkle { .. } => {
                return Err(ClientError::InvalidInput {
                    reason: "this upload triggered merkle batching, which the FFI external-signer \
                             surface does not support yet (wave-batch only). Use a smaller upload \
                             or a wallet-backed put for now."
                        .into(),
                });
            }
        };
        let already_stored = payments.is_empty();
        let upload_id = format!("upl-{}", self.next_id.fetch_add(1, Ordering::Relaxed));
        self.sessions
            .lock()
            .expect("sessions mutex poisoned")
            .insert(upload_id.clone(), prepared);
        Ok(PreparedUploadInfo {
            upload_id,
            payment_type,
            payments,
            total_amount,
            data_map_address,
            already_stored,
        })
    }
}

/// Parse a visibility string ("public" | "private") into ant-core's enum.
fn parse_visibility(s: &str) -> Result<Visibility, ClientError> {
    match s {
        "public" => Ok(Visibility::Public),
        "private" => Ok(Visibility::Private),
        other => Err(ClientError::InvalidInput {
            reason: format!("invalid visibility {other:?}; use \"public\" or \"private\""),
        }),
    }
}

/// Decode a 0x-prefixed (or bare) hex string into a 32-byte hash.
fn decode_hash(hex_str: &str, label: &str) -> Result<[u8; 32], ClientError> {
    let bytes =
        hex::decode(hex_str.trim_start_matches("0x")).map_err(|e| ClientError::InvalidInput {
            reason: format!("invalid {label} {hex_str}: {e}"),
        })?;
    bytes.try_into().map_err(|_| ClientError::InvalidInput {
        reason: format!("{label} {hex_str} must be 32 bytes"),
    })
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
