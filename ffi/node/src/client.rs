//! The `Client` — a direct-network (daemon-less) Autonomi client.
//!
//! One `Client` per process is the intended model: the process itself becomes a
//! network peer, so `connect*` pays a bootstrap latency and the returned client
//! holds live QUIC connections for its lifetime. Each `#[napi]` method wraps
//! `ant-ffi`'s `Arc<Client>` and delegates; napi drives async methods to JS
//! `Promise`s on its tokio runtime.
//!
//! Every async method clones the inner `Arc` before awaiting so the spawned
//! future owns it (`'static`) rather than borrowing `&self`.

use std::collections::HashMap;
use std::sync::Arc;

use napi::bindgen_prelude::*;
use napi_derive::napi;

use crate::convert::{
    client_err, ChunkPutResult, CostEstimate, DataPutPrivateResult, DataPutPublicResult,
    ExternalUploadResult, FilePutPrivateResult, FilePutPublicResult, PaymentMode,
    PreparedUploadInfo, TxRequest, Visibility,
};
use crate::progress::{listener, ProgressTsfn};

#[napi]
pub struct Client {
    inner: Arc<ant_ffi::Client>,
}

// ===== Constructors =====
//
// Exposed as static async methods returning `Promise<Client>`. All take an
// optional trailing `dataDir` — required on Android (the app's files dir; the
// process has no HOME), leave undefined on desktop/iOS.
#[napi]
impl Client {
    /// Connect to a local test network (loopback).
    #[napi]
    pub async fn connect_local(data_dir: Option<String>) -> Result<Client> {
        let inner = ant_ffi::Client::connect_local(data_dir)
            .await
            .map_err(client_err)?;
        Ok(Client { inner })
    }

    /// Connect using explicit bootstrap peers (`/ip4/<ip>/udp/<port>/quic`
    /// multiaddr strings). Read-only; use a wallet/external-signer variant to
    /// write.
    #[napi]
    pub async fn connect(peers: Vec<String>, data_dir: Option<String>) -> Result<Client> {
        let inner = ant_ffi::Client::connect(peers, data_dir)
            .await
            .map_err(client_err)?;
        Ok(Client { inner })
    }

    /// Connect to the Autonomi **production network** using the SDK's vendored
    /// bootstrap peers — no configuration. Read-only.
    #[napi]
    pub async fn connect_default(data_dir: Option<String>) -> Result<Client> {
        let inner = ant_ffi::Client::connect_default(data_dir)
            .await
            .map_err(client_err)?;
        Ok(Client { inner })
    }

    /// `connectDefault` with a wallet attached for writes, preset for the
    /// production EVM network.
    #[napi]
    pub async fn connect_default_with_wallet(
        private_key: String,
        data_dir: Option<String>,
    ) -> Result<Client> {
        let inner = ant_ffi::Client::connect_default_with_wallet(private_key, data_dir)
            .await
            .map_err(client_err)?;
        Ok(Client { inner })
    }

    /// `connectDefault` configured for the **external-signer** flow (mobile
    /// wallets / WalletConnect): production peers + EVM network for quotes, no
    /// wallet attached.
    #[napi]
    pub async fn connect_default_for_external_signer(data_dir: Option<String>) -> Result<Client> {
        let inner = ant_ffi::Client::connect_default_for_external_signer(data_dir)
            .await
            .map_err(client_err)?;
        Ok(Client { inner })
    }

    /// Connect with a wallet configured for writes on a custom EVM network.
    #[napi]
    pub async fn connect_with_wallet(
        peers: Vec<String>,
        private_key: String,
        rpc_url: String,
        payment_token_address: String,
        payment_vault_address: String,
        data_dir: Option<String>,
    ) -> Result<Client> {
        let inner = ant_ffi::Client::connect_with_wallet(
            peers,
            private_key,
            rpc_url,
            payment_token_address,
            payment_vault_address,
            data_dir,
        )
        .await
        .map_err(client_err)?;
        Ok(Client { inner })
    }

    /// Connect to a local devnet described by a devnet manifest JSON file (the
    /// file written by `ant-devnet`). **Development/testing only.** Fails if the
    /// manifest is missing, malformed, or has no `evm` section.
    #[napi]
    pub async fn connect_from_devnet_manifest(
        manifest_path: String,
        data_dir: Option<String>,
    ) -> Result<Client> {
        let inner = ant_ffi::Client::connect_from_devnet_manifest(manifest_path, data_dir)
            .await
            .map_err(client_err)?;
        Ok(Client { inner })
    }

    /// Like `connectFromDevnetManifest` but for the **external-signer** flow:
    /// configures the devnet EVM network for quotes but attaches no wallet.
    #[napi]
    pub async fn connect_from_devnet_manifest_external_signer(
        manifest_path: String,
        data_dir: Option<String>,
    ) -> Result<Client> {
        let inner =
            ant_ffi::Client::connect_from_devnet_manifest_external_signer(manifest_path, data_dir)
                .await
                .map_err(client_err)?;
        Ok(Client { inner })
    }

    /// Connect with an EVM network configured but **no wallet** — the
    /// external-signer entry point. Quote/price queries work; payment is signed
    /// off-device. Pay via `prepare*` + your signer + `finalize*`.
    #[napi]
    pub async fn connect_for_external_signer(
        peers: Vec<String>,
        rpc_url: String,
        payment_token_address: String,
        payment_vault_address: String,
        data_dir: Option<String>,
    ) -> Result<Client> {
        let inner = ant_ffi::Client::connect_for_external_signer(
            peers,
            rpc_url,
            payment_token_address,
            payment_vault_address,
            data_dir,
        )
        .await
        .map_err(client_err)?;
        Ok(Client { inner })
    }
}

// ===== Chunk operations =====
#[napi]
impl Client {
    /// Store a single chunk on the network.
    #[napi]
    pub async fn chunk_put(&self, data: Uint8Array) -> Result<ChunkPutResult> {
        let inner = self.inner.clone();
        inner
            .chunk_put(data.to_vec())
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// Retrieve a chunk by hex-encoded address.
    #[napi]
    pub async fn chunk_get(&self, address_hex: String) -> Result<Buffer> {
        let inner = self.inner.clone();
        let bytes = inner.chunk_get(address_hex).await.map_err(client_err)?;
        Ok(bytes.into())
    }

    /// Check whether a chunk exists on the network.
    #[napi]
    pub async fn chunk_exists(&self, address_hex: String) -> Result<bool> {
        let inner = self.inner.clone();
        inner.chunk_exists(address_hex).await.map_err(client_err)
    }
}

// ===== Data operations =====
#[napi]
impl Client {
    /// Upload data publicly (retrievable by the returned address).
    #[napi]
    pub async fn data_put_public(
        &self,
        data: Uint8Array,
        payment_mode: PaymentMode,
    ) -> Result<DataPutPublicResult> {
        let inner = self.inner.clone();
        inner
            .data_put_public(data.to_vec(), payment_mode.into())
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// Retrieve public data by its hex-encoded data-map address.
    #[napi]
    pub async fn data_get_public(&self, address_hex: String) -> Result<Buffer> {
        let inner = self.inner.clone();
        let bytes = inner.data_get_public(address_hex).await.map_err(client_err)?;
        Ok(bytes.into())
    }

    /// Upload data privately. Returns the serialized data map (hex) — keep it
    /// secret; it is required to retrieve the data.
    #[napi]
    pub async fn data_put_private(
        &self,
        data: Uint8Array,
        payment_mode: PaymentMode,
    ) -> Result<DataPutPrivateResult> {
        let inner = self.inner.clone();
        inner
            .data_put_private(data.to_vec(), payment_mode.into())
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// Retrieve private data using a hex-encoded data map.
    #[napi]
    pub async fn data_get_private(&self, data_map_hex: String) -> Result<Buffer> {
        let inner = self.inner.clone();
        let bytes = inner
            .data_get_private(data_map_hex)
            .await
            .map_err(client_err)?;
        Ok(bytes.into())
    }
}

// ===== File operations =====
#[napi]
impl Client {
    /// Upload a file from disk publicly. Returns the shareable address plus
    /// chunk/cost details.
    #[napi]
    pub async fn file_upload_public(
        &self,
        path: String,
        payment_mode: PaymentMode,
    ) -> Result<FilePutPublicResult> {
        let inner = self.inner.clone();
        inner
            .file_upload_public(path, payment_mode.into())
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// `fileUploadPublic` with live progress (`Encrypting`/`Quoting`/`Storing`).
    #[napi(
        ts_args_type = "path: string, paymentMode: PaymentMode, onProgress: (progress: ProgressUpdate) => void"
    )]
    pub async fn file_upload_public_with_progress(
        &self,
        path: String,
        payment_mode: PaymentMode,
        on_progress: ProgressTsfn,
    ) -> Result<FilePutPublicResult> {
        let inner = self.inner.clone();
        inner
            .file_upload_public_with_progress(path, payment_mode.into(), listener(on_progress))
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// Upload a file from disk privately. Returns the serialized data map (hex);
    /// keep it secret to retrieve the file later.
    #[napi]
    pub async fn file_upload_private(
        &self,
        path: String,
        payment_mode: PaymentMode,
    ) -> Result<FilePutPrivateResult> {
        let inner = self.inner.clone();
        inner
            .file_upload_private(path, payment_mode.into())
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// `fileUploadPrivate` with live progress.
    #[napi(
        ts_args_type = "path: string, paymentMode: PaymentMode, onProgress: (progress: ProgressUpdate) => void"
    )]
    pub async fn file_upload_private_with_progress(
        &self,
        path: String,
        payment_mode: PaymentMode,
        on_progress: ProgressTsfn,
    ) -> Result<FilePutPrivateResult> {
        let inner = self.inner.clone();
        inner
            .file_upload_private_with_progress(path, payment_mode.into(), listener(on_progress))
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// Download a public file to disk by hex-encoded address.
    #[napi]
    pub async fn file_download_public(&self, address_hex: String, dest_path: String) -> Result<()> {
        let inner = self.inner.clone();
        inner
            .file_download_public(address_hex, dest_path)
            .await
            .map_err(client_err)
    }

    /// Download a private file to disk by hex-encoded data map.
    #[napi]
    pub async fn file_download_private(
        &self,
        data_map_hex: String,
        dest_path: String,
    ) -> Result<()> {
        let inner = self.inner.clone();
        inner
            .file_download_private(data_map_hex, dest_path)
            .await
            .map_err(client_err)
    }
}

// ===== Data-map helpers =====
#[napi]
impl Client {
    /// Publish an existing private data map (hex) as a public network chunk,
    /// returning its hex address — without re-uploading the underlying data.
    #[napi]
    pub async fn data_map_store(&self, data_map_hex: String) -> Result<String> {
        let inner = self.inner.clone();
        inner.data_map_store(data_map_hex).await.map_err(client_err)
    }

    /// Fetch a public data map by hex address and return it serialized (hex) —
    /// the inverse of `dataMapStore`.
    #[napi]
    pub async fn data_map_fetch(&self, address_hex: String) -> Result<String> {
        let inner = self.inner.clone();
        inner.data_map_fetch(address_hex).await.map_err(client_err)
    }
}

// ===== Cost estimation =====
#[napi]
impl Client {
    /// Estimate the cost of uploading a file *before* preparing or paying.
    /// Samples a few chunk addresses; fast and needs no wallet. Check
    /// `CostEstimate.confidence` before treating a `"0"` cost as free.
    #[napi]
    pub async fn estimate_file_cost(
        &self,
        path: String,
        payment_mode: PaymentMode,
    ) -> Result<CostEstimate> {
        let inner = self.inner.clone();
        inner
            .estimate_file_cost(path, payment_mode.into())
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// `estimateFileCost` with live progress (the `Encrypting` phase).
    #[napi(
        ts_args_type = "path: string, paymentMode: PaymentMode, onProgress: (progress: ProgressUpdate) => void"
    )]
    pub async fn estimate_file_cost_with_progress(
        &self,
        path: String,
        payment_mode: PaymentMode,
        on_progress: ProgressTsfn,
    ) -> Result<CostEstimate> {
        let inner = self.inner.clone();
        inner
            .estimate_file_cost_with_progress(path, payment_mode.into(), listener(on_progress))
            .await
            .map(Into::into)
            .map_err(client_err)
    }
}

// ===== Wallet operations (attached-wallet path) =====
#[napi]
impl Client {
    /// Approve token spend for storage payments (one-time; wallet-backed client).
    #[napi]
    pub async fn wallet_approve(&self) -> Result<()> {
        let inner = self.inner.clone();
        inner.wallet_approve().await.map_err(client_err)
    }
}

// ===== External-signer flow =====
#[napi]
impl Client {
    /// Phase 1: encrypt `data`, collect quotes, and return the payment summary.
    /// The prepared state is retained under the returned `uploadId` until finalize.
    #[napi]
    pub async fn prepare_data_upload(
        &self,
        data: Uint8Array,
        visibility: Visibility,
    ) -> Result<PreparedUploadInfo> {
        let inner = self.inner.clone();
        inner
            .prepare_data_upload(data.to_vec(), visibility.into())
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// Phase 1 for a file on disk.
    #[napi]
    pub async fn prepare_file_upload(
        &self,
        path: String,
        visibility: Visibility,
    ) -> Result<PreparedUploadInfo> {
        let inner = self.inner.clone();
        inner
            .prepare_file_upload(path, visibility.into())
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// Phase 1 for a file, with encryption/quoting progress.
    #[napi(
        ts_args_type = "path: string, visibility: Visibility, onProgress: (progress: ProgressUpdate) => void"
    )]
    pub async fn prepare_file_upload_with_progress(
        &self,
        path: String,
        visibility: Visibility,
        on_progress: ProgressTsfn,
    ) -> Result<PreparedUploadInfo> {
        let inner = self.inner.clone();
        inner
            .prepare_file_upload_with_progress(path, visibility.into(), listener(on_progress))
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// Phase 1.5: build the ordered transactions (ERC-20 `approve` + vault
    /// payment call(s)) the external wallet must sign to pay for a prepared
    /// upload. Empty when everything was already stored.
    #[napi]
    pub async fn payment_transactions(&self, upload_id: String) -> Result<Vec<TxRequest>> {
        let inner = self.inner.clone();
        let txs = inner
            .payment_transactions(upload_id)
            .await
            .map_err(client_err)?;
        Ok(txs.into_iter().map(Into::into).collect())
    }

    /// Phase 2 (wave-batch): after the wallet has paid, finalize by supplying the
    /// `quoteHash -> txHash` map (both 0x-prefixed hex). Pass an empty map if
    /// everything was already stored.
    #[napi]
    pub async fn finalize_upload(
        &self,
        upload_id: String,
        tx_hashes: HashMap<String, String>,
    ) -> Result<ExternalUploadResult> {
        let inner = self.inner.clone();
        inner
            .finalize_upload(upload_id, tx_hashes)
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// `finalizeUpload` with live storing progress.
    #[napi(
        ts_args_type = "uploadId: string, txHashes: Record<string, string>, onProgress: (progress: ProgressUpdate) => void"
    )]
    pub async fn finalize_upload_with_progress(
        &self,
        upload_id: String,
        tx_hashes: HashMap<String, String>,
        on_progress: ProgressTsfn,
    ) -> Result<ExternalUploadResult> {
        let inner = self.inner.clone();
        inner
            .finalize_upload_with_progress(upload_id, tx_hashes, listener(on_progress))
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// Phase 2 (merkle): finalize by supplying the `winnerPoolHash` read from the
    /// `MerklePaymentMade` event (see the `merkleWinnerPoolHash` free function).
    #[napi]
    pub async fn finalize_upload_merkle(
        &self,
        upload_id: String,
        winner_pool_hash: String,
    ) -> Result<ExternalUploadResult> {
        let inner = self.inner.clone();
        inner
            .finalize_upload_merkle(upload_id, winner_pool_hash)
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// `finalizeUploadMerkle` with live storing progress.
    #[napi(
        ts_args_type = "uploadId: string, winnerPoolHash: string, onProgress: (progress: ProgressUpdate) => void"
    )]
    pub async fn finalize_upload_merkle_with_progress(
        &self,
        upload_id: String,
        winner_pool_hash: String,
        on_progress: ProgressTsfn,
    ) -> Result<ExternalUploadResult> {
        let inner = self.inner.clone();
        inner
            .finalize_upload_merkle_with_progress(upload_id, winner_pool_hash, listener(on_progress))
            .await
            .map(Into::into)
            .map_err(client_err)
    }

    /// Discard a prepared upload that will not be finalized, freeing the chunk
    /// content it holds in memory. Returns `true` if an upload with this id was
    /// present. Safe to call with an unknown/already-finalized id.
    #[napi]
    pub fn cancel_upload(&self, upload_id: String) -> bool {
        self.inner.cancel_upload(upload_id)
    }
}

// ===== Streaming downloads to disk (with progress) =====
#[napi]
impl Client {
    /// Download public data by address straight to a file on disk, reporting
    /// live progress (`Resolving` then `Downloading`). Returns bytes written.
    #[napi(
        ts_args_type = "addressHex: string, destPath: string, onProgress: (progress: ProgressUpdate) => void"
    )]
    pub async fn download_public_to_file(
        &self,
        address_hex: String,
        dest_path: String,
        on_progress: ProgressTsfn,
    ) -> Result<i64> {
        let inner = self.inner.clone();
        let written = inner
            .download_public_to_file(address_hex, dest_path, listener(on_progress))
            .await
            .map_err(client_err)?;
        Ok(written as i64)
    }

    /// Download private data by hex-encoded data map straight to a file on disk,
    /// reporting live progress. Returns bytes written.
    #[napi(
        ts_args_type = "dataMapHex: string, destPath: string, onProgress: (progress: ProgressUpdate) => void"
    )]
    pub async fn download_private_to_file(
        &self,
        data_map_hex: String,
        dest_path: String,
        on_progress: ProgressTsfn,
    ) -> Result<i64> {
        let inner = self.inner.clone();
        let written = inner
            .download_private_to_file(data_map_hex, dest_path, listener(on_progress))
            .await
            .map_err(client_err)?;
        Ok(written as i64)
    }
}
