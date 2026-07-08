use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use bytes::Bytes;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use zeroize::Zeroize;

use ant_core::data::{
    Client as CoreClient, ClientConfig, CoreNodeConfig, DevnetManifest, DownloadEvent,
    ExternalPaymentInfo, FileUploadResult, MultiAddr, NodeMode, P2PNode, PreparedUpload,
    UploadEvent, Visibility, Wallet as CoreWallet, MAX_WIRE_MESSAGE_SIZE,
};
use ant_protocol::evm::{QuoteHash, TxHash};

use crate::data::{format_payment_mode, parse_payment_mode};
use crate::wallet::build_custom_network;
use crate::{
    CandidateNodeEntry, ChunkPutResult, ClientError, DataPutPrivateResult, DataPutPublicResult,
    ExternalUploadResult, FilePutPublicResult, PaymentEntry, PoolCommitmentEntry,
    PreparedUploadInfo, ProgressListener, ProgressUpdate,
};

/// Map an ant-core [`UploadEvent`] to the FFI [`ProgressUpdate`] shape.
fn map_upload_event(ev: UploadEvent) -> ProgressUpdate {
    match ev {
        UploadEvent::Encrypting { chunks_done } => ProgressUpdate {
            phase: "encrypting".into(),
            done: chunks_done as u64,
            total: 0,
        },
        UploadEvent::Encrypted { total_chunks } => ProgressUpdate {
            phase: "encrypting".into(),
            done: total_chunks as u64,
            total: total_chunks as u64,
        },
        UploadEvent::QuotingChunks { .. } => ProgressUpdate {
            phase: "quoting".into(),
            done: 0,
            total: 0,
        },
        UploadEvent::ChunkQuoted { quoted, total } => ProgressUpdate {
            phase: "quoting".into(),
            done: quoted as u64,
            total: total as u64,
        },
        UploadEvent::ChunkStored { stored, total } => ProgressUpdate {
            phase: "storing".into(),
            done: stored as u64,
            total: total as u64,
        },
        // ant-core 0.3.0 removed `UploadEvent::WaveComplete`; per-chunk
        // `ChunkStored` already carries the running total.
    }
}

/// Map an ant-core [`DownloadEvent`] to the FFI [`ProgressUpdate`] shape.
fn map_download_event(ev: DownloadEvent) -> ProgressUpdate {
    match ev {
        DownloadEvent::ResolvingDataMap { total_map_chunks } => ProgressUpdate {
            phase: "resolving".into(),
            done: 0,
            total: total_map_chunks as u64,
        },
        DownloadEvent::MapChunkFetched { fetched } => ProgressUpdate {
            phase: "resolving".into(),
            done: fetched as u64,
            total: 0,
        },
        DownloadEvent::DataMapResolved { total_chunks } => ProgressUpdate {
            phase: "downloading".into(),
            done: 0,
            total: total_chunks as u64,
        },
        DownloadEvent::ChunksFetched { fetched, total } => ProgressUpdate {
            phase: "downloading".into(),
            done: fetched as u64,
            total: total as u64,
        },
    }
}

/// Spin up a channel + reader task that forwards ant-core upload events to a
/// foreign [`ProgressListener`]. The returned sender is handed to ant-core;
/// when it drops (the operation finishes) the task ends. Await the handle after
/// the operation to flush the last events.
fn upload_progress_bridge(
    listener: Box<dyn ProgressListener>,
) -> (mpsc::Sender<UploadEvent>, JoinHandle<()>) {
    let (tx, mut rx) = mpsc::channel::<UploadEvent>(64);
    let handle = tokio::spawn(async move {
        while let Some(ev) = rx.recv().await {
            listener.on_progress(map_upload_event(ev));
        }
    });
    (tx, handle)
}

/// Download counterpart of [`upload_progress_bridge`].
fn download_progress_bridge(
    listener: Box<dyn ProgressListener>,
) -> (mpsc::Sender<DownloadEvent>, JoinHandle<()>) {
    let (tx, mut rx) = mpsc::channel::<DownloadEvent>(64);
    let handle = tokio::spawn(async move {
        while let Some(ev) = rx.recv().await {
            listener.on_progress(map_download_event(ev));
        }
    });
    (tx, handle)
}

/// Autonomi network client (wraps ant-core Client).
///
/// Provides direct access to the Autonomi network without needing
/// an antd daemon. Suitable for mobile apps (Android/iOS).
#[derive(uniffi::Object)]
pub struct Client {
    inner: CoreClient,
    /// External-signer prepared uploads awaiting finalize, keyed by upload_id.
    ///
    /// Each `PreparedUpload` holds the upload's chunk content **in memory** so
    /// finalize can store it after the external wallet pays. Lifecycle &
    /// memory cost the caller must know:
    ///   - An entry is created by every successful `prepare_*` call and removed
    ///     only by a successful `finalize_upload*` or an explicit
    ///     `cancel_upload`. There is no TTL or automatic eviction.
    ///   - So a caller that prepares repeatedly without finalizing (e.g. the
    ///     user backs out of the confirm sheet) retains one payload-sized buffer
    ///     per abandoned upload for the life of the `Client`. Call
    ///     `cancel_upload` to release one, or drop the whole `Client`.
    ///
    /// A bounded cache / TTL is a possible follow-up if this proves a problem.
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
            .ipv6(false)
            .max_message_size(MAX_WIRE_MESSAGE_SIZE);

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
            .port(0)
            .max_message_size(MAX_WIRE_MESSAGE_SIZE);

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
            .port(0)
            .max_message_size(MAX_WIRE_MESSAGE_SIZE);

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

        let network =
            build_custom_network(&rpc_url, &payment_token_address, &payment_vault_address)
                .map_err(|e| ClientError::InitializationFailed {
                    reason: e.to_string(),
                })?;
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
        let manifest: DevnetManifest =
            serde_json::from_slice(&bytes).map_err(|e| ClientError::InitializationFailed {
                reason: format!("invalid manifest JSON: {e}"),
            })?;
        let evm = manifest
            .evm
            .ok_or_else(|| ClientError::InitializationFailed {
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
            .ipv6(false)
            .max_message_size(MAX_WIRE_MESSAGE_SIZE);
        for peer in &manifest.bootstrap {
            builder = builder.bootstrap_peer(peer.clone());
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
        .map_err(|e| ClientError::InitializationFailed {
            reason: e.to_string(),
        })?;
        let wallet =
            CoreWallet::new_from_private_key(network, &evm.wallet_private_key).map_err(|e| {
                ClientError::InitializationFailed {
                    reason: format!("failed to create wallet from manifest: {e}"),
                }
            })?;

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
        let evm = manifest
            .evm
            .ok_or_else(|| ClientError::InitializationFailed {
                reason: "manifest has no `evm` section — devnet started without payments?".into(),
            })?;

        // Same devnet-tuned node config as the wallet variant (local +
        // loopback), so the client joins the local devnet the same way.
        let mut builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0)
            .local(true)
            .allow_loopback(true)
            .ipv6(false)
            .max_message_size(MAX_WIRE_MESSAGE_SIZE);
        for peer in &manifest.bootstrap {
            builder = builder.bootstrap_peer(peer.clone());
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
        .map_err(|e| ClientError::InitializationFailed {
            reason: e.to_string(),
        })?;
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
        let mode = parse_payment_mode(&payment_mode)
            .map_err(|e| ClientError::InvalidInput { reason: e })?;

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
        let mode = parse_payment_mode(&payment_mode)
            .map_err(|e| ClientError::InvalidInput { reason: e })?;

        let result = self
            .inner
            .data_upload_with_mode(Bytes::from(data), mode)
            .await?;

        let data_map_bytes =
            rmp_serde::to_vec(&result.data_map).map_err(|e| ClientError::InternalError {
                reason: format!("failed to serialize data map: {e}"),
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
        let data_map_bytes = hex::decode(&data_map_hex).map_err(|e| ClientError::InvalidInput {
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
        let mode = parse_payment_mode(&payment_mode)
            .map_err(|e| ClientError::InvalidInput { reason: e })?;
        let file_path = PathBuf::from(&path);

        let result = self.inner.file_upload_with_mode(&file_path, mode).await?;

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
        let mut builder = CoreNodeConfig::builder()
            .mode(NodeMode::Client)
            .port(0)
            .max_message_size(MAX_WIRE_MESSAGE_SIZE);
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

        let network =
            build_custom_network(&rpc_url, &payment_token_address, &payment_vault_address)
                .map_err(|e| ClientError::InitializationFailed {
                    reason: e.to_string(),
                })?;
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
    ///
    /// # Retry / failure contract (IMPORTANT for paid uploads)
    ///
    /// - **Bad input** (a malformed `quote_hash`/`tx_hash`) is validated before
    ///   any state is touched, so it errors with the upload left intact — safe
    ///   to call again with a corrected map.
    /// - **A storage/network failure *after* payment is currently NOT
    ///   retryable.** ant-core consumes the prepared upload (and the paid
    ///   proofs) by value, so on such a failure the paid attempt is stranded:
    ///   a fresh `prepare_*` collects new quotes with different quote hashes
    ///   that will not match the already-paid tx map. Do not tell the user the
    ///   payment can simply be reused. Fixing this needs an ant-core retry-state
    ///   API — tracked in WithAutonomi/ant-client#140 (core) and
    ///   WithAutonomi/ant-sdk#201 (this surface).
    pub async fn finalize_upload(
        &self,
        upload_id: String,
        tx_hashes: HashMap<String, String>,
    ) -> Result<ExternalUploadResult, ClientError> {
        self.finalize_inner(upload_id, tx_hashes, None).await
    }

    /// Same as [`Self::finalize_upload`] but reports live storing progress:
    /// `listener` gets `"storing"` updates (`done`/`total` chunks) as chunks
    /// land on the network.
    pub async fn finalize_upload_with_progress(
        &self,
        upload_id: String,
        tx_hashes: HashMap<String, String>,
        listener: Box<dyn ProgressListener>,
    ) -> Result<ExternalUploadResult, ClientError> {
        self.finalize_inner(upload_id, tx_hashes, Some(listener))
            .await
    }

    /// Phase 2 (external signer, MERKLE): after the wallet has paid via
    /// `payForMerkleTree`, finalize by supplying the `winner_pool_hash`
    /// (0x-prefixed hex, 32 bytes) read from the `MerklePaymentMade` event in
    /// the payment receipt. Use this for uploads whose
    /// `PreparedUploadInfo.payment_type == "merkle"`; wave-batch uploads must
    /// use [`Self::finalize_upload`] (this rejects them with a clear error, and
    /// vice versa, without consuming the prepared upload).
    ///
    /// The same retry/failure contract as [`Self::finalize_upload`] applies: a
    /// storage failure after payment is currently not retryable
    /// (WithAutonomi/ant-client#140).
    pub async fn finalize_upload_merkle(
        &self,
        upload_id: String,
        winner_pool_hash: String,
    ) -> Result<ExternalUploadResult, ClientError> {
        self.finalize_merkle_inner(upload_id, winner_pool_hash, None)
            .await
    }

    /// Same as [`Self::finalize_upload_merkle`] but reports live storing
    /// progress via `listener` (the `"storing"` phase).
    pub async fn finalize_upload_merkle_with_progress(
        &self,
        upload_id: String,
        winner_pool_hash: String,
        listener: Box<dyn ProgressListener>,
    ) -> Result<ExternalUploadResult, ClientError> {
        self.finalize_merkle_inner(upload_id, winner_pool_hash, Some(listener))
            .await
    }

    /// Discard a prepared upload that will not be finalized, freeing the chunk
    /// content it holds in memory (see the `sessions` field docs on lifecycle).
    /// Returns `true` if an upload with this id was present. Safe to call with
    /// an unknown or already-finalized id — it simply returns `false`.
    pub fn cancel_upload(&self, upload_id: String) -> bool {
        self.sessions
            .lock()
            .expect("sessions mutex poisoned")
            .remove(&upload_id)
            .is_some()
    }

    /// Download public data by address straight to a file on disk, reporting
    /// live progress (`"resolving"` then `"downloading"` phases). Returns bytes
    /// written.
    pub async fn download_public_to_file(
        &self,
        address_hex: String,
        dest_path: String,
        listener: Box<dyn ProgressListener>,
    ) -> Result<u64, ClientError> {
        let address = hex_to_address(&address_hex)?;
        let data_map = self.inner.data_map_fetch(&address).await?;
        self.download_to_file(data_map, dest_path, listener).await
    }

    /// Download private data by hex-encoded data map straight to a file on
    /// disk, reporting live progress. Returns bytes written.
    pub async fn download_private_to_file(
        &self,
        data_map_hex: String,
        dest_path: String,
        listener: Box<dyn ProgressListener>,
    ) -> Result<u64, ClientError> {
        // Reject unreasonably large hex input (20 MB hex = 10 MB decoded),
        // matching the cap on `data_get_private` — this surface is reachable
        // from app/UI input, so guard against a decode-driven memory spike.
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
        let data_map_bytes = hex::decode(&data_map_hex).map_err(|e| ClientError::InvalidInput {
            reason: format!("invalid hex: {e}"),
        })?;
        let data_map: ant_core::data::DataMap =
            rmp_serde::from_slice(&data_map_bytes).map_err(|e| ClientError::InvalidInput {
                reason: format!("invalid data map: {e}"),
            })?;
        self.download_to_file(data_map, dest_path, listener).await
    }
}

impl Client {
    /// Shared finalize path — optionally bridges storing progress to `listener`.
    async fn finalize_inner(
        &self,
        upload_id: String,
        tx_hashes: HashMap<String, String>,
        listener: Option<Box<dyn ProgressListener>>,
    ) -> Result<ExternalUploadResult, ClientError> {
        // Parse & validate ALL tx hashes BEFORE removing the prepared upload
        // from the session map. The caller has already paid on-chain, so a
        // malformed hash must NOT destroy the only in-memory copy of the
        // prepared chunks — with this ordering, bad input returns an error and
        // leaves the upload intact and retryable.
        let mut tx_hash_map: HashMap<QuoteHash, TxHash> = HashMap::with_capacity(tx_hashes.len());
        for (quote_hex, tx_hex) in &tx_hashes {
            let quote_bytes = decode_hash(quote_hex, "quote hash")?;
            let tx_bytes = decode_hash(tx_hex, "tx hash")?;
            tx_hash_map.insert(QuoteHash::from(quote_bytes), TxHash::from(tx_bytes));
        }

        // Take ownership of the prepared upload only now that the input is
        // known-good, so bad-input retries stay lossless. WARNING: ant-core's
        // `finalize_upload_with_progress` consumes the `PreparedUpload` (and the
        // paid proofs) by value and does not hand them back on error, so a
        // *network* store failure below strands the paid attempt — it is NOT
        // safely retryable, because a re-prepare yields fresh quote hashes that
        // won't match the already-paid tx map. See the `finalize_upload` docs
        // and WithAutonomi/ant-client#140 + WithAutonomi/ant-sdk#201 for the fix.
        let prepared = self.take_session(&upload_id, PaymentKind::Wave)?;

        let (sender, handle) = match listener {
            Some(l) => {
                let (tx, h) = upload_progress_bridge(l);
                (Some(tx), Some(h))
            }
            None => (None, None),
        };

        let result = self
            .inner
            .finalize_upload_with_progress(prepared, &tx_hash_map, sender)
            .await?;

        if let Some(h) = handle {
            let _ = h.await;
        }

        Self::to_external_result(result)
    }

    /// Shared finalize path for MERKLE uploads. Validates `winner_pool_hash`
    /// before taking the session (bad input is lossless), then consumes the
    /// prepared upload via ant-core's merkle finalize. Same post-payment
    /// non-retryability caveat as [`Self::finalize_inner`] applies.
    async fn finalize_merkle_inner(
        &self,
        upload_id: String,
        winner_pool_hash: String,
        listener: Option<Box<dyn ProgressListener>>,
    ) -> Result<ExternalUploadResult, ClientError> {
        let winner = decode_hash(&winner_pool_hash, "winner pool hash")?;
        let prepared = self.take_session(&upload_id, PaymentKind::Merkle)?;

        let (sender, handle) = match listener {
            Some(l) => {
                let (tx, h) = upload_progress_bridge(l);
                (Some(tx), Some(h))
            }
            None => (None, None),
        };

        let result = self
            .inner
            .finalize_upload_merkle_with_progress(prepared, winner, sender)
            .await?;

        if let Some(h) = handle {
            let _ = h.await;
        }

        Self::to_external_result(result)
    }

    /// Remove the prepared upload for `upload_id`, but only if it matches the
    /// expected payment shape. An unknown id, or a call routed to the wrong
    /// finalize method, errors WITHOUT removing anything — so a mis-routed
    /// finalize is lossless and retryable via the correct method.
    fn take_session(
        &self,
        upload_id: &str,
        expect: PaymentKind,
    ) -> Result<PreparedUpload, ClientError> {
        let mut map = self.sessions.lock().expect("sessions mutex poisoned");
        let actual = match map.get(upload_id) {
            None => {
                return Err(ClientError::InvalidInput {
                    reason: format!("unknown or already-finalized upload_id: {upload_id}"),
                });
            }
            Some(p) => match p.payment_info {
                ExternalPaymentInfo::Merkle { .. } => PaymentKind::Merkle,
                ExternalPaymentInfo::WaveBatch { .. } => PaymentKind::Wave,
            },
        };
        if actual != expect {
            let (used, want) = match actual {
                PaymentKind::Merkle => ("merkle", "finalize_upload_merkle"),
                PaymentKind::Wave => ("wave-batch", "finalize_upload"),
            };
            return Err(ClientError::InvalidInput {
                reason: format!("upload {upload_id} used {used} payment; call {want} instead"),
            });
        }
        Ok(map
            .remove(upload_id)
            .expect("session entry present while holding the lock"))
    }

    /// Convert ant-core's [`FileUploadResult`] into the FFI [`ExternalUploadResult`].
    fn to_external_result(result: FileUploadResult) -> Result<ExternalUploadResult, ClientError> {
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

    /// Shared download-to-file path with progress bridging.
    async fn download_to_file(
        &self,
        data_map: ant_core::data::DataMap,
        dest_path: String,
        listener: Box<dyn ProgressListener>,
    ) -> Result<u64, ClientError> {
        let (tx, handle) = download_progress_bridge(listener);
        let written = self
            .inner
            .file_download_with_progress(&data_map, Path::new(&dest_path), Some(tx))
            .await?;
        let _ = handle.await;
        Ok(written)
    }

    /// Build the FFI summary for a prepared upload and stash the heavy state
    /// under a fresh `upload_id`. Handles both wave-batch and merkle payment.
    fn stash_prepared(&self, prepared: PreparedUpload) -> Result<PreparedUploadInfo, ClientError> {
        let data_map_address = prepared.data_map_address.map(hex::encode);
        // Everything already on the network (nothing to pay/store) when the
        // preflight found every chunk. Independent of payment shape — merkle
        // never produces per-quote `payments`, so we can't infer this from an
        // empty payments list.
        let already_stored = prepared.already_stored_addresses.len() >= prepared.total_chunks;

        // Defaults: wave leaves the merkle fields empty; merkle leaves `payments`
        // empty and `total_amount` "0".
        let mut payments = Vec::new();
        let mut total_amount = "0".to_string();
        let mut depth = 0u32;
        let mut pool_commitments = Vec::new();
        let mut merkle_payment_timestamp = 0u64;

        let payment_type = match &prepared.payment_info {
            ExternalPaymentInfo::WaveBatch { payment_intent, .. } => {
                payments = payment_intent
                    .payments
                    .iter()
                    .map(|(quote_hash, rewards_addr, amount)| PaymentEntry {
                        quote_hash: format!("0x{}", hex::encode(quote_hash)),
                        rewards_address: format!("{rewards_addr}"),
                        amount: amount.to_string(),
                    })
                    .collect::<Vec<_>>();
                total_amount = payment_intent.total_amount.to_string();
                "wave_batch".to_string()
            }
            // Merkle: expose depth + pool commitments + timestamp so the app can
            // build the `payForMerkleTree(uint8, PoolCommitment[], uint64)` call.
            // Mirrors the antd daemon's gRPC/REST mapping.
            ExternalPaymentInfo::Merkle { prepared_batch, .. } => {
                depth = prepared_batch.depth as u32;
                merkle_payment_timestamp = prepared_batch.merkle_payment_timestamp;
                pool_commitments = prepared_batch
                    .pool_commitments
                    .iter()
                    .map(|pc| PoolCommitmentEntry {
                        pool_hash: format!("0x{}", hex::encode(pc.pool_hash)),
                        candidates: pc
                            .candidates
                            .iter()
                            .map(|c| CandidateNodeEntry {
                                rewards_address: format!("0x{}", hex::encode(c.rewards_address)),
                                amount: c.price.to_string(),
                            })
                            .collect(),
                    })
                    .collect::<Vec<_>>();
                "merkle".to_string()
            }
        };
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
            depth,
            pool_commitments,
            merkle_payment_timestamp,
            data_map_address,
            already_stored,
        })
    }
}

/// Which external-signer payment shape a finalize call targets. Used to route
/// `finalize_upload` (wave) vs `finalize_upload_merkle` and reject mismatches.
#[derive(Clone, Copy, PartialEq)]
enum PaymentKind {
    Wave,
    Merkle,
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
    bytes.try_into().map_err(|_| ClientError::InvalidInput {
        reason: "address must be 32 bytes".into(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_hash_accepts_32_bytes_with_or_without_0x() {
        let bare = "11".repeat(32);
        let prefixed = format!("0x{bare}");
        let want = [0x11u8; 32];
        assert_eq!(decode_hash(&bare, "winner pool hash").unwrap(), want);
        assert_eq!(decode_hash(&prefixed, "winner pool hash").unwrap(), want);
    }

    #[test]
    fn decode_hash_rejects_wrong_length() {
        // 31 bytes — one short of a 32-byte hash.
        let short = "ab".repeat(31);
        let err = decode_hash(&short, "winner pool hash").unwrap_err();
        assert!(
            matches!(err, ClientError::InvalidInput { reason } if reason.contains("32 bytes")),
            "expected a 32-byte length error"
        );
    }

    #[test]
    fn decode_hash_rejects_non_hex() {
        let err = decode_hash("0xzz", "winner pool hash").unwrap_err();
        assert!(matches!(err, ClientError::InvalidInput { .. }));
    }

    #[test]
    fn parse_visibility_maps_known_values_and_rejects_others() {
        assert!(matches!(
            parse_visibility("public").unwrap(),
            Visibility::Public
        ));
        assert!(matches!(
            parse_visibility("private").unwrap(),
            Visibility::Private
        ));
        let err = parse_visibility("shared").unwrap_err();
        assert!(matches!(err, ClientError::InvalidInput { .. }));
    }
}
