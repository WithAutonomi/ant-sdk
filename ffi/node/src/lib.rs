//! Node.js / Electron bindings for the Autonomi direct-network client.
//!
//! A thin `#[napi]` wrapper over the `ant-ffi` Rust crate — the same inner
//! client the Swift/Kotlin/C#/Python bindings wrap (those via UniFFI; Node via
//! napi-rs, since UniFFI has no maintained Node generator). No business logic
//! lives here: every export delegates to `ant-ffi` and re-packs its records.

use napi_derive::napi;

mod client;
mod convert;
mod progress;
mod wallet;

pub use client::Client;
pub use convert::{
    CandidateNodeEntry, ChunkPutResult, CostConfidence, CostEstimate, DataPutPrivateResult,
    DataPutPublicResult, ExternalUploadResult, FilePutPrivateResult, FilePutPublicResult,
    NetworkInfo, PaymentEntry, PaymentMode, PaymentType, PoolCommitmentEntry, PreparedUploadInfo,
    ProgressPhase, ProgressUpdate, TxKind, TxReceipt, TxRequest, Visibility,
};
pub use wallet::Wallet;

use convert::client_err;
use progress::ProgressTsfn;

/// The AntFfi SDK version (e.g. `"0.0.8"`) — matches the released SDK version
/// shared across all bindings.
#[napi]
pub fn ant_ffi_version() -> String {
    ant_ffi::ant_ffi_version()
}

/// On-chain configuration for a known Autonomi EVM network. `name` is one of
/// `"arbitrum-one"` / `"arbitrum-sepolia-test"` (and their short aliases).
#[napi]
pub fn network_info(name: String) -> napi::Result<NetworkInfo> {
    ant_ffi::network_info(name)
        .map(Into::into)
        .map_err(client_err)
}

/// Poll `rpcUrl` for the receipt of `txHash`, resolving once it's mined (or
/// rejecting on revert / after `timeoutSecs`). Moves the app's hand-rolled
/// `eth_getTransactionReceipt` polling loop into the SDK.
#[napi]
pub async fn wait_for_receipt(
    rpc_url: String,
    tx_hash: String,
    timeout_secs: u32,
) -> napi::Result<TxReceipt> {
    ant_ffi::wait_for_receipt(rpc_url, tx_hash, timeout_secs as u64)
        .await
        .map(Into::into)
        .map_err(client_err)
}

/// Read the winning pool hash from a settled `payForMerkleTree` transaction (the
/// `MerklePaymentMade` log emitted by `vaultAddress`), 0x-prefixed — pass it to
/// `client.finalizeUploadMerkle`.
#[napi]
pub async fn merkle_winner_pool_hash(
    rpc_url: String,
    vault_address: String,
    tx_hash: String,
) -> napi::Result<String> {
    ant_ffi::merkle_winner_pool_hash(rpc_url, vault_address, tx_hash)
        .await
        .map_err(client_err)
}

/// **Test hook — not part of the public API.** Fires `ticks` synthetic
/// `Encrypting` progress updates through the same bridge every `*WithProgress`
/// method uses, from a background thread, then resolves. Exists so the
/// callback-exception containment (a throwing `onProgress` becomes an
/// `AntProgressCallbackError` warning, never a fatal exception) has an offline
/// regression test.
#[napi(
    js_name = "_emitProgressForTest",
    ts_args_type = "onProgress: (progress: ProgressUpdate) => void, ticks: number"
)]
pub async fn emit_progress_for_test(on_progress: ProgressTsfn, ticks: u32) -> napi::Result<()> {
    std::thread::spawn(move || {
        for i in 0..ticks {
            progress::emit(
                &on_progress,
                ProgressUpdate {
                    phase: ProgressPhase::Encrypting,
                    done: i64::from(i) + 1,
                    total: i64::from(ticks),
                },
            );
        }
    })
    .join()
    .map_err(|_| napi::Error::from_reason("progress test thread panicked"))
}
