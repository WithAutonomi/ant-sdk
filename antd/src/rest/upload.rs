use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use axum::extract::State;
use axum::Json;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

/// Phase 1: Prepare a file upload for external signing.
///
/// Encrypts the file, collects storage quotes from the network, and returns
/// a payment intent with an upload_id. The caller signs and submits the EVM
/// payment transaction externally, then calls finalize with the tx hashes.
///
/// The prepared upload state is held server-side (not serialized to the client)
/// so that internal types like PeerId and peer addresses are preserved.
pub async fn prepare_upload(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PrepareUploadRequest>,
) -> Result<Json<PrepareUploadResponse>, AntdError> {
    let path = PathBuf::from(&req.path)
        .canonicalize()
        .map_err(|e| AntdError::BadRequest(format!("invalid path {}: {e}", req.path)))?;

    let client = state.client.clone();
    let prepared = tokio::spawn(async move {
        client.file_prepare_upload(&path).await
            .map_err(AntdError::from_core)
    }).await.map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    // Build payment entries from the intent
    let payments: Vec<PaymentEntry> = prepared.payment_intent.payments.iter().map(|(quote_hash, rewards_addr, amount)| {
        PaymentEntry {
            quote_hash: format!("{:#x}", quote_hash),
            rewards_address: format!("{:#x}", rewards_addr),
            amount: amount.to_string(),
        }
    }).collect();

    let total_amount = prepared.payment_intent.total_amount.to_string();

    // Generate a unique upload ID and store the prepared state
    let upload_id = hex::encode(rand::random::<[u8; 16]>());
    state.pending_uploads.lock().await.insert(upload_id.clone(), prepared);

    // EVM network details from env
    let rpc_url = std::env::var("EVM_RPC_URL")
        .unwrap_or_else(|_| "http://127.0.0.1:8545".to_string());
    let payment_token_address = std::env::var("EVM_PAYMENT_TOKEN_ADDRESS")
        .unwrap_or_default();
    let data_payments_address = std::env::var("EVM_DATA_PAYMENTS_ADDRESS")
        .unwrap_or_default();

    Ok(Json(PrepareUploadResponse {
        upload_id,
        payments,
        total_amount,
        data_payments_address,
        payment_token_address,
        rpc_url,
    }))
}

/// Phase 1 (data): Prepare an in-memory data upload for external signing.
///
/// Same as prepare_upload but takes base64-encoded data instead of a file path.
pub async fn prepare_data_upload(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PrepareDataUploadRequest>,
) -> Result<Json<PrepareUploadResponse>, AntdError> {
    use base64::Engine;
    use base64::engine::general_purpose::STANDARD as BASE64;
    use bytes::Bytes;

    let data = BASE64.decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let client = state.client.clone();
    let prepared = tokio::spawn(async move {
        client.data_prepare_upload(Bytes::from(data)).await
            .map_err(AntdError::from_core)
    }).await.map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    let payments: Vec<PaymentEntry> = prepared.payment_intent.payments.iter().map(|(quote_hash, rewards_addr, amount)| {
        PaymentEntry {
            quote_hash: format!("{:#x}", quote_hash),
            rewards_address: format!("{:#x}", rewards_addr),
            amount: amount.to_string(),
        }
    }).collect();

    let total_amount = prepared.payment_intent.total_amount.to_string();

    let upload_id = hex::encode(rand::random::<[u8; 16]>());
    state.pending_uploads.lock().await.insert(upload_id.clone(), prepared);

    let rpc_url = std::env::var("EVM_RPC_URL")
        .unwrap_or_else(|_| "http://127.0.0.1:8545".to_string());
    let payment_token_address = std::env::var("EVM_PAYMENT_TOKEN_ADDRESS")
        .unwrap_or_default();
    let data_payments_address = std::env::var("EVM_DATA_PAYMENTS_ADDRESS")
        .unwrap_or_default();

    Ok(Json(PrepareUploadResponse {
        upload_id,
        payments,
        total_amount,
        data_payments_address,
        payment_token_address,
        rpc_url,
    }))
}

/// Phase 2: Finalize an upload after external payment.
///
/// Takes the upload_id from prepare and a map of quote_hash → tx_hash
/// from the on-chain payment. Builds proofs and uploads chunks.
pub async fn finalize_upload(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FinalizeUploadRequest>,
) -> Result<Json<FinalizeUploadResponse>, AntdError> {
    // Remove the prepared upload from server state
    let prepared = state.pending_uploads.lock().await
        .remove(&req.upload_id)
        .ok_or_else(|| AntdError::NotFound(format!(
            "upload_id {} not found — it may have expired or already been finalized",
            req.upload_id
        )))?;

    // Parse tx_hashes from hex strings
    let tx_hash_map: HashMap<evmlib::common::QuoteHash, evmlib::common::TxHash> =
        req.tx_hashes
            .iter()
            .map(|(quote_hex, tx_hex)| {
                let quote_bytes: [u8; 32] = hex::decode(quote_hex.trim_start_matches("0x"))
                    .map_err(|e| AntdError::BadRequest(format!("invalid quote_hash {quote_hex}: {e}")))?
                    .try_into()
                    .map_err(|_| AntdError::BadRequest("quote_hash must be 32 bytes".into()))?;
                let tx_bytes: [u8; 32] = hex::decode(tx_hex.trim_start_matches("0x"))
                    .map_err(|e| AntdError::BadRequest(format!("invalid tx_hash {tx_hex}: {e}")))?
                    .try_into()
                    .map_err(|_| AntdError::BadRequest("tx_hash must be 32 bytes".into()))?;
                Ok((quote_bytes.into(), tx_bytes.into()))
            })
            .collect::<Result<_, AntdError>>()?;

    let store_on_network = req.store_data_map;
    let client = state.client.clone();
    let (data_map_hex, address, chunks_stored) = tokio::spawn(async move {
        let result = client.finalize_upload(prepared, &tx_hash_map).await
            .map_err(AntdError::from_core)?;

        let data_map_bytes = rmp_serde::to_vec(&result.data_map)
            .map_err(|e| AntdError::Internal(format!("serialize data map: {e}")))?;
        let data_map_hex = hex::encode(data_map_bytes);

        // Optionally store the DataMap on-network (requires a wallet).
        let address = if store_on_network {
            let addr = client.data_map_store(&result.data_map).await
                .map_err(AntdError::from_core)?;
            Some(hex::encode(addr))
        } else {
            None
        };

        Ok::<_, AntdError>((data_map_hex, address, result.chunks_stored))
    }).await.map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(FinalizeUploadResponse {
        data_map: data_map_hex,
        address,
        chunks_stored: chunks_stored as u64,
    }))
}
