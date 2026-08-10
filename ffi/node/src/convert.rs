//! Type marshaling between `ant-ffi`'s UniFFI record/enum types and the
//! napi-exposed shapes, plus error mapping.
//!
//! The napi types are deliberately distinct from `ant-ffi`'s (`#[napi]` and
//! `#[uniffi::*]` can't share a type), but they mirror them field-for-field.
//! Conventions shared with the other bindings: token/gas amounts are decimal
//! strings (they exceed 2^53); counts/timestamps are JS numbers.

use napi_derive::napi;

// ===== Enums =====

/// How an upload is paid for.
#[napi]
pub enum PaymentMode {
    /// Let the SDK pick: merkle batching for large uploads, single otherwise.
    Auto,
    /// Merkle-batched payment — one on-chain payment covering many chunks.
    Merkle,
    /// Per-quote wave payment.
    Single,
}

impl From<PaymentMode> for ant_ffi::PaymentMode {
    fn from(m: PaymentMode) -> Self {
        match m {
            PaymentMode::Auto => ant_ffi::PaymentMode::Auto,
            PaymentMode::Merkle => ant_ffi::PaymentMode::Merkle,
            PaymentMode::Single => ant_ffi::PaymentMode::Single,
        }
    }
}

impl From<ant_ffi::PaymentMode> for PaymentMode {
    fn from(m: ant_ffi::PaymentMode) -> Self {
        match m {
            ant_ffi::PaymentMode::Auto => PaymentMode::Auto,
            ant_ffi::PaymentMode::Merkle => PaymentMode::Merkle,
            ant_ffi::PaymentMode::Single => PaymentMode::Single,
        }
    }
}

/// Whether an upload is publicly retrievable by address, or private (the data
/// map is returned to the caller only).
#[napi]
pub enum Visibility {
    Public,
    Private,
}

impl From<Visibility> for ant_ffi::Visibility {
    fn from(v: Visibility) -> Self {
        match v {
            Visibility::Public => ant_ffi::Visibility::Public,
            Visibility::Private => ant_ffi::Visibility::Private,
        }
    }
}

/// Which phase a [`ProgressUpdate`] belongs to.
#[napi]
pub enum ProgressPhase {
    Encrypting,
    Quoting,
    Storing,
    Resolving,
    Downloading,
}

impl From<ant_ffi::ProgressPhase> for ProgressPhase {
    fn from(p: ant_ffi::ProgressPhase) -> Self {
        match p {
            ant_ffi::ProgressPhase::Encrypting => ProgressPhase::Encrypting,
            ant_ffi::ProgressPhase::Quoting => ProgressPhase::Quoting,
            ant_ffi::ProgressPhase::Storing => ProgressPhase::Storing,
            ant_ffi::ProgressPhase::Resolving => ProgressPhase::Resolving,
            ant_ffi::ProgressPhase::Downloading => ProgressPhase::Downloading,
        }
    }
}

/// Payment shape of a prepared external-signer upload — selects which finalize
/// call to use (see [`PreparedUploadInfo`]).
#[napi]
pub enum PaymentType {
    WaveBatch,
    Merkle,
}

impl From<ant_ffi::PaymentType> for PaymentType {
    fn from(t: ant_ffi::PaymentType) -> Self {
        match t {
            ant_ffi::PaymentType::WaveBatch => PaymentType::WaveBatch,
            ant_ffi::PaymentType::Merkle => PaymentType::Merkle,
        }
    }
}

/// What a [`TxRequest`] is for.
#[napi]
pub enum TxKind {
    /// ERC-20 allowance approval (sent to the token contract).
    Approve,
    /// The vault payment call.
    Pay,
}

impl From<ant_ffi::TxKind> for TxKind {
    fn from(k: ant_ffi::TxKind) -> Self {
        match k {
            ant_ffi::TxKind::Approve => TxKind::Approve,
            ant_ffi::TxKind::Pay => TxKind::Pay,
        }
    }
}

/// How much to trust a [`CostEstimate`]'s `storageCostAtto`.
#[napi]
pub enum CostConfidence {
    /// Extrapolated from at least one live quote (the normal case).
    PricedSample,
    /// Every chunk was sampled and already stored; cost is exactly `"0"`.
    VerifiedAllAlreadyStored,
    /// Every *sampled* chunk was already stored but the tail was unsampled;
    /// `"0"` is a best-effort guess. Render as "likely already stored".
    AllSamplesAlreadyStoredIncomplete,
}

impl From<ant_ffi::CostConfidence> for CostConfidence {
    fn from(c: ant_ffi::CostConfidence) -> Self {
        match c {
            ant_ffi::CostConfidence::PricedSample => CostConfidence::PricedSample,
            ant_ffi::CostConfidence::VerifiedAllAlreadyStored => {
                CostConfidence::VerifiedAllAlreadyStored
            }
            ant_ffi::CostConfidence::AllSamplesAlreadyStoredIncomplete => {
                CostConfidence::AllSamplesAlreadyStoredIncomplete
            }
        }
    }
}

// ===== Records =====

/// Result of storing a single chunk on the network.
#[napi(object)]
pub struct ChunkPutResult {
    /// Hex-encoded chunk address (32 bytes).
    pub address: String,
}

impl From<ant_ffi::ChunkPutResult> for ChunkPutResult {
    fn from(r: ant_ffi::ChunkPutResult) -> Self {
        Self { address: r.address }
    }
}

/// Result of a public data upload (data map stored as a public chunk).
#[napi(object)]
pub struct DataPutPublicResult {
    /// Hex-encoded address of the stored data map.
    pub address: String,
    /// Number of chunks stored.
    pub chunks_stored: i64,
    /// Payment mode that was used.
    pub payment_mode_used: PaymentMode,
}

impl From<ant_ffi::DataPutPublicResult> for DataPutPublicResult {
    fn from(r: ant_ffi::DataPutPublicResult) -> Self {
        Self {
            address: r.address,
            chunks_stored: r.chunks_stored as i64,
            payment_mode_used: r.payment_mode_used.into(),
        }
    }
}

/// Result of a private data upload (data map returned to caller, kept secret).
#[napi(object)]
pub struct DataPutPrivateResult {
    /// Hex-encoded serialized data map (caller keeps this secret).
    pub data_map: String,
    /// Number of chunks stored.
    pub chunks_stored: i64,
    /// Payment mode that was used.
    pub payment_mode_used: PaymentMode,
}

impl From<ant_ffi::DataPutPrivateResult> for DataPutPrivateResult {
    fn from(r: ant_ffi::DataPutPrivateResult) -> Self {
        Self {
            data_map: r.data_map,
            chunks_stored: r.chunks_stored as i64,
            payment_mode_used: r.payment_mode_used.into(),
        }
    }
}

/// Result of uploading a public file.
#[napi(object)]
pub struct FilePutPublicResult {
    /// Hex-encoded address of the stored data map.
    pub address: String,
    /// Number of chunks stored on the network.
    pub chunks_stored: i64,
    /// Total storage cost paid, in atto-tokens (base-10). "0" if all pre-existed.
    pub storage_cost_atto: String,
    /// Total gas cost in wei (base-10).
    pub gas_cost_wei: String,
    /// Payment mode that was used.
    pub payment_mode_used: PaymentMode,
}

impl From<ant_ffi::FilePutPublicResult> for FilePutPublicResult {
    fn from(r: ant_ffi::FilePutPublicResult) -> Self {
        Self {
            address: r.address,
            chunks_stored: r.chunks_stored as i64,
            storage_cost_atto: r.storage_cost_atto,
            gas_cost_wei: r.gas_cost_wei,
            payment_mode_used: r.payment_mode_used.into(),
        }
    }
}

/// Result of uploading a private file. Keep `dataMap` secret — it is required
/// to retrieve the file and is not recoverable from the network.
#[napi(object)]
pub struct FilePutPrivateResult {
    /// Hex-encoded serialized data map (caller keeps this secret).
    pub data_map: String,
    /// Number of chunks stored on the network.
    pub chunks_stored: i64,
    /// Total storage cost paid, in atto-tokens (base-10). "0" if all pre-existed.
    pub storage_cost_atto: String,
    /// Total gas cost in wei (base-10).
    pub gas_cost_wei: String,
    /// Payment mode that was used.
    pub payment_mode_used: PaymentMode,
}

impl From<ant_ffi::FilePutPrivateResult> for FilePutPrivateResult {
    fn from(r: ant_ffi::FilePutPrivateResult) -> Self {
        Self {
            data_map: r.data_map,
            chunks_stored: r.chunks_stored as i64,
            storage_cost_atto: r.storage_cost_atto,
            gas_cost_wei: r.gas_cost_wei,
            payment_mode_used: r.payment_mode_used.into(),
        }
    }
}

/// Estimated cost of uploading a file, produced *before* any payment by
/// sampling a few of the file's chunk addresses. No wallet required.
#[napi(object)]
pub struct CostEstimate {
    /// Original file size in bytes.
    pub file_size: i64,
    /// Number of data chunks the file would split into (excludes the extra
    /// data-map chunk added for public uploads).
    pub chunk_count: i64,
    /// Estimated storage cost in atto-tokens (base-10 string; may exceed u64).
    pub storage_cost_atto: String,
    /// Rough estimated gas cost in wei (base-10 string). A heuristic, NOT a live
    /// gas-price query.
    pub estimated_gas_cost_wei: String,
    /// Payment mode that would be used.
    pub payment_mode: PaymentMode,
    /// How much to trust `storageCostAtto` — check before treating a `"0"` cost
    /// as free.
    pub confidence: CostConfidence,
}

impl From<ant_ffi::CostEstimate> for CostEstimate {
    fn from(e: ant_ffi::CostEstimate) -> Self {
        Self {
            file_size: e.file_size as i64,
            chunk_count: e.chunk_count as i64,
            storage_cost_atto: e.storage_cost_atto,
            estimated_gas_cost_wei: e.estimated_gas_cost_wei,
            payment_mode: e.payment_mode.into(),
            confidence: e.confidence.into(),
        }
    }
}

/// A single on-chain payment the external wallet must settle.
#[napi(object)]
pub struct PaymentEntry {
    /// 0x-prefixed quote hash (32 bytes) — the key in the tx-hash map at finalize.
    pub quote_hash: String,
    /// 0x-prefixed EVM rewards address to pay.
    pub rewards_address: String,
    /// Amount to pay in atto-tokens (base-10 string; exceeds u64).
    pub amount: String,
}

impl From<ant_ffi::PaymentEntry> for PaymentEntry {
    fn from(p: ant_ffi::PaymentEntry) -> Self {
        Self {
            quote_hash: p.quote_hash,
            rewards_address: p.rewards_address,
            amount: p.amount,
        }
    }
}

/// One candidate node inside a [`PoolCommitmentEntry`].
#[napi(object)]
pub struct CandidateNodeEntry {
    /// 0x-prefixed EVM rewards address (20 bytes).
    pub rewards_address: String,
    /// Node price in atto-tokens (base-10 string).
    pub amount: String,
}

impl From<ant_ffi::CandidateNodeEntry> for CandidateNodeEntry {
    fn from(c: ant_ffi::CandidateNodeEntry) -> Self {
        Self {
            rewards_address: c.rewards_address,
            amount: c.amount,
        }
    }
}

/// One pool commitment for the merkle payment call.
#[napi(object)]
pub struct PoolCommitmentEntry {
    /// 0x-prefixed pool hash (32 bytes).
    pub pool_hash: String,
    /// The pool's candidate nodes.
    pub candidates: Vec<CandidateNodeEntry>,
}

impl From<ant_ffi::PoolCommitmentEntry> for PoolCommitmentEntry {
    fn from(p: ant_ffi::PoolCommitmentEntry) -> Self {
        Self {
            pool_hash: p.pool_hash,
            candidates: p.candidates.into_iter().map(Into::into).collect(),
        }
    }
}

/// Summary of a prepared external-signer upload. `paymentType` selects which
/// fields are meaningful and which finalize call to use (see the client's
/// `paymentTransactions` / `finalizeUpload*` docs).
#[napi(object)]
pub struct PreparedUploadInfo {
    /// Opaque handle for this prepared upload; pass to the matching finalize call.
    pub upload_id: String,
    /// Payment shape — selects the finalize call.
    pub payment_type: PaymentType,
    /// Wave-batch only: per-quote payments to settle on-chain. Empty for merkle
    /// or if everything was already stored.
    pub payments: Vec<PaymentEntry>,
    /// Wave-batch: total across all payments (atto-tokens, base-10). `"0"` for merkle.
    pub total_amount: String,
    /// Merkle only: merkle tree depth for the `payForMerkleTree` call. 0 for wave-batch.
    pub depth: u32,
    /// Merkle only: pool commitments for the `payForMerkleTree` call. Empty for wave-batch.
    pub pool_commitments: Vec<PoolCommitmentEntry>,
    /// Merkle only: timestamp for the `payForMerkleTree` call. 0 for wave-batch.
    pub merkle_payment_timestamp: i64,
    /// For public uploads: hex address the data is retrievable from after
    /// finalize. Absent for private uploads.
    pub data_map_address: Option<String>,
    /// True if every chunk already existed on the network — nothing to pay.
    pub already_stored: bool,
}

impl From<ant_ffi::PreparedUploadInfo> for PreparedUploadInfo {
    fn from(p: ant_ffi::PreparedUploadInfo) -> Self {
        Self {
            upload_id: p.upload_id,
            payment_type: p.payment_type.into(),
            payments: p.payments.into_iter().map(Into::into).collect(),
            total_amount: p.total_amount,
            depth: p.depth,
            pool_commitments: p.pool_commitments.into_iter().map(Into::into).collect(),
            merkle_payment_timestamp: p.merkle_payment_timestamp as i64,
            data_map_address: p.data_map_address,
            already_stored: p.already_stored,
        }
    }
}

/// Result of finalizing an external-signer upload.
#[napi(object)]
pub struct ExternalUploadResult {
    /// Hex-encoded serialized data map (for private retrieval; always present).
    pub data_map: String,
    /// For public uploads: hex data-map address (shareable). Absent if private.
    pub address: Option<String>,
    /// Number of chunks stored on the network.
    pub chunks_stored: i64,
    /// Total storage cost paid, in atto-tokens (base-10). "0" if all pre-existed.
    pub storage_cost_atto: String,
    /// Total gas cost in wei (base-10).
    pub gas_cost_wei: String,
}

impl From<ant_ffi::ExternalUploadResult> for ExternalUploadResult {
    fn from(r: ant_ffi::ExternalUploadResult) -> Self {
        Self {
            data_map: r.data_map,
            address: r.address,
            chunks_stored: r.chunks_stored as i64,
            storage_cost_atto: r.storage_cost_atto,
            gas_cost_wei: r.gas_cost_wei,
        }
    }
}

/// On-chain configuration for a known Autonomi EVM network.
#[napi(object)]
pub struct NetworkInfo {
    /// EVM chain id (e.g. 42161 Arbitrum One, 421614 Arbitrum Sepolia).
    pub chain_id: u32,
    /// 0x-prefixed ANT payment-token address.
    pub token_address: String,
    /// 0x-prefixed payment-vault address.
    pub vault_address: String,
    /// Default HTTPS RPC URL for the network.
    pub rpc_url: String,
}

impl From<ant_ffi::NetworkInfo> for NetworkInfo {
    fn from(n: ant_ffi::NetworkInfo) -> Self {
        Self {
            chain_id: n.chain_id,
            token_address: n.token_address,
            vault_address: n.vault_address,
            rpc_url: n.rpc_url,
        }
    }
}

/// One transaction the external wallet must sign & send, in order, to pay for a
/// prepared upload (produced by `client.paymentTransactions`).
#[napi(object)]
pub struct TxRequest {
    /// 0x-prefixed contract address to send the transaction to.
    pub to: String,
    /// 0x-prefixed ABI-encoded calldata for the transaction's `data` field.
    pub data: String,
    /// What this transaction is for (allowance approval vs the payment call).
    pub kind: TxKind,
    /// Wave-batch `Pay` only: the 0x-prefixed quote hashes this payment settles.
    /// Map each to the resulting tx hash to build the `finalizeUpload` map.
    pub quote_hashes: Vec<String>,
}

impl From<ant_ffi::TxRequest> for TxRequest {
    fn from(t: ant_ffi::TxRequest) -> Self {
        Self {
            to: t.to,
            data: t.data,
            kind: t.kind.into(),
            quote_hashes: t.quote_hashes,
        }
    }
}

/// Outcome of a settled transaction, from `waitForReceipt`.
#[napi(object)]
pub struct TxReceipt {
    /// `true` if the transaction succeeded (receipt status `0x1`).
    pub success: bool,
    /// Gas units consumed (base-10 string).
    pub gas_used: String,
    /// Effective gas price paid in wei (base-10 string).
    pub effective_gas_price: String,
}

impl From<ant_ffi::TxReceipt> for TxReceipt {
    fn from(r: ant_ffi::TxReceipt) -> Self {
        Self {
            success: r.success,
            gas_used: r.gas_used,
            effective_gas_price: r.effective_gas_price,
        }
    }
}

/// A progress update for a long-running upload or download. `total` is 0 when
/// unknown yet (show an indeterminate bar); otherwise `done / total` is a 0..1
/// fraction of the current phase.
#[napi(object)]
pub struct ProgressUpdate {
    pub phase: ProgressPhase,
    pub done: i64,
    pub total: i64,
}

impl From<ant_ffi::ProgressUpdate> for ProgressUpdate {
    fn from(u: ant_ffi::ProgressUpdate) -> Self {
        Self {
            phase: u.phase.into(),
            done: u.done as i64,
            total: u.total as i64,
        }
    }
}

// ===== Error mapping =====
//
// Surface the `Display` message (which already carries variant context, e.g.
// "Not found: …", "Wallet not configured", "Partial upload: … (x/y chunks
// stored)") as a JS exception. A follow-up can promote each variant to a
// machine-readable `code` and attach PartialUpload's money-visible fields
// (storageCostAtto/gasCostWei) to the error object — see V2-881 / V2-571.

/// Map an `ant-ffi` client error into a JS exception.
pub fn client_err(e: ant_ffi::ClientError) -> napi::Error {
    napi::Error::new(napi::Status::GenericFailure, e.to_string())
}

/// Map an `ant-ffi` wallet error into a JS exception.
pub fn wallet_err(e: ant_ffi::WalletError) -> napi::Error {
    napi::Error::new(napi::Status::GenericFailure, e.to_string())
}
