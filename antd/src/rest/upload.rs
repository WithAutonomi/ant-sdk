use std::collections::HashMap;
use std::sync::Arc;

use axum::extract::State;
use axum::Json;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

/// Build a [`PrepareUploadResponse`] from a prepared upload, matching on the
/// payment variant (wave-batch vs merkle) and serialising the appropriate fields.
fn build_prepare_response(
    upload_id: String,
    prepared: &ant_core::data::PreparedUpload,
) -> Result<PrepareUploadResponse, AntdError> {
    let rpc_url = std::env::var("EVM_RPC_URL")
        .unwrap_or_else(|_| "http://127.0.0.1:8545".to_string());
    let payment_token_address = std::env::var("EVM_PAYMENT_TOKEN_ADDRESS")
        .unwrap_or_default();

    match &prepared.payment_info {
        ant_core::data::ExternalPaymentInfo::WaveBatch {
            payment_intent, ..
        } => {
            let payments: Vec<PaymentEntry> = payment_intent
                .payments
                .iter()
                .map(|(quote_hash, rewards_addr, amount)| PaymentEntry {
                    quote_hash: format!("{:#x}", quote_hash),
                    rewards_address: format!("{:#x}", rewards_addr),
                    amount: amount.to_string(),
                })
                .collect();

            let data_payments_address = std::env::var("EVM_DATA_PAYMENTS_ADDRESS")
                .unwrap_or_default();

            Ok(PrepareUploadResponse {
                upload_id,
                payment_type: "wave_batch".into(),
                payments,
                data_payments_address: Some(data_payments_address),
                depth: None,
                pool_commitments: None,
                merkle_payment_timestamp: None,
                merkle_payments_address: None,
                total_amount: payment_intent.total_amount.to_string(),
                payment_token_address,
                rpc_url,
            })
        }
        ant_core::data::ExternalPaymentInfo::Merkle {
            prepared_batch, ..
        } => {
            let merkle_payments_address = std::env::var("EVM_MERKLE_PAYMENTS_ADDRESS")
                .unwrap_or_default();

            // Serialize pool commitments for JSON response.
            // Each candidate has rewards_address + price (maps to contract's amount).
            let pool_commitments: Vec<PoolCommitmentEntry> = prepared_batch
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
                .collect();

            Ok(PrepareUploadResponse {
                upload_id,
                payment_type: "merkle".into(),
                payments: vec![],
                data_payments_address: None,
                depth: Some(prepared_batch.depth),
                pool_commitments: Some(pool_commitments),
                merkle_payment_timestamp: Some(prepared_batch.merkle_payment_timestamp),
                merkle_payments_address: Some(merkle_payments_address),
                total_amount: "0".into(),
                payment_token_address,
                rpc_url,
            })
        }
    }
}

/// Phase 1: Prepare a file upload for external signing.
///
/// Encrypts the file, collects storage quotes from the network, and returns
/// payment details with an upload_id. The caller signs and submits the EVM
/// payment transaction externally, then calls finalize with the result.
///
/// For files with < 64 chunks, returns `payment_type: "wave_batch"` with
/// per-quote payment entries for `payForQuotes()`.
///
/// For files with >= 64 chunks, returns `payment_type: "merkle"` with
/// depth, pool commitments, and timestamp for `payForMerkleTree2()`.
pub async fn prepare_upload(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PrepareUploadRequest>,
) -> Result<Json<PrepareUploadResponse>, AntdError> {
    let path = std::path::PathBuf::from(&req.path)
        .canonicalize()
        .map_err(|e| {
            tracing::warn!(path = %req.path, error = %e, "invalid prepare-upload path");
            AntdError::BadRequest("invalid path".into())
        })?;

    let client = state.client.clone();
    let prepared = tokio::spawn(async move {
        client
            .file_prepare_upload(&path)
            .await
            .map_err(AntdError::from_core)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    // Generate a unique upload ID and store the prepared state
    let upload_id = hex::encode(rand::random::<[u8; 16]>());
    let response = build_prepare_response(upload_id.clone(), &prepared)?;

    state.pending_uploads.lock().await.insert(
        upload_id,
        crate::state::TimestampedUpload {
            prepared,
            created_at: std::time::Instant::now(),
        },
    );

    Ok(Json(response))
}

/// Phase 1 (data): Prepare an in-memory data upload for external signing.
///
/// Same as prepare_upload but takes base64-encoded data instead of a file path.
pub async fn prepare_data_upload(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PrepareDataUploadRequest>,
) -> Result<Json<PrepareUploadResponse>, AntdError> {
    use base64::engine::general_purpose::STANDARD as BASE64;
    use base64::Engine;
    use bytes::Bytes;

    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let client = state.client.clone();
    let prepared = tokio::spawn(async move {
        client
            .data_prepare_upload(Bytes::from(data))
            .await
            .map_err(AntdError::from_core)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    let upload_id = hex::encode(rand::random::<[u8; 16]>());
    let response = build_prepare_response(upload_id.clone(), &prepared)?;

    state.pending_uploads.lock().await.insert(
        upload_id,
        crate::state::TimestampedUpload {
            prepared,
            created_at: std::time::Instant::now(),
        },
    );

    Ok(Json(response))
}

/// Phase 2: Finalize an upload after external payment.
///
/// For wave-batch uploads, takes `tx_hashes` (map of quote_hash → tx_hash).
/// For merkle uploads, takes `winner_pool_hash` from the `MerklePaymentMade` event.
///
/// The handler detects the payment type from the stored prepared upload and
/// validates that the correct request fields are provided.
pub async fn finalize_upload(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FinalizeUploadRequest>,
) -> Result<Json<FinalizeUploadResponse>, AntdError> {
    // Remove the prepared upload from server state
    let timestamped = state
        .pending_uploads
        .lock()
        .await
        .remove(&req.upload_id)
        .ok_or_else(|| {
            AntdError::NotFound(format!(
                "upload_id {} not found — it may have expired or already been finalized",
                req.upload_id
            ))
        })?;
    let prepared = timestamped.prepared;

    let store_on_network = req.store_data_map;
    let client = state.client.clone();

    let (data_map_hex, address, chunks_stored) = match &prepared.payment_info {
        ant_core::data::ExternalPaymentInfo::WaveBatch { .. } => {
            // Wave-batch: require tx_hashes
            let tx_hashes_raw = req.tx_hashes.ok_or_else(|| {
                AntdError::BadRequest(
                    "tx_hashes required for wave-batch upload (this upload used wave_batch payment)"
                        .into(),
                )
            })?;

            if req.winner_pool_hash.is_some() {
                return Err(AntdError::BadRequest(
                    "winner_pool_hash not applicable for wave-batch upload".into(),
                ));
            }

            // Parse tx_hashes from hex strings
            let tx_hash_map: HashMap<evmlib::common::QuoteHash, evmlib::common::TxHash> =
                tx_hashes_raw
                    .iter()
                    .map(|(quote_hex, tx_hex)| {
                        let quote_bytes: [u8; 32] =
                            hex::decode(quote_hex.trim_start_matches("0x"))
                                .map_err(|e| {
                                    AntdError::BadRequest(format!(
                                        "invalid quote_hash {quote_hex}: {e}"
                                    ))
                                })?
                                .try_into()
                                .map_err(|_| {
                                    AntdError::BadRequest("quote_hash must be 32 bytes".into())
                                })?;
                        let tx_bytes: [u8; 32] = hex::decode(tx_hex.trim_start_matches("0x"))
                            .map_err(|e| {
                                AntdError::BadRequest(format!("invalid tx_hash {tx_hex}: {e}"))
                            })?
                            .try_into()
                            .map_err(|_| {
                                AntdError::BadRequest("tx_hash must be 32 bytes".into())
                            })?;
                        Ok((quote_bytes.into(), tx_bytes.into()))
                    })
                    .collect::<Result<_, AntdError>>()?;

            tokio::spawn(async move {
                let result = client
                    .finalize_upload(prepared, &tx_hash_map)
                    .await
                    .map_err(AntdError::from_core)?;

                let data_map_bytes = rmp_serde::to_vec(&result.data_map)
                    .map_err(|e| AntdError::Internal(format!("serialize data map: {e}")))?;
                let data_map_hex = hex::encode(data_map_bytes);

                let address = if store_on_network {
                    let addr = client
                        .data_map_store(&result.data_map)
                        .await
                        .map_err(AntdError::from_core)?;
                    Some(hex::encode(addr))
                } else {
                    None
                };

                Ok::<_, AntdError>((data_map_hex, address, result.chunks_stored))
            })
            .await
            .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??
        }

        ant_core::data::ExternalPaymentInfo::Merkle { .. } => {
            // Merkle: require winner_pool_hash
            let winner_hash_hex = req.winner_pool_hash.ok_or_else(|| {
                AntdError::BadRequest(
                    "winner_pool_hash required for merkle upload (this upload used merkle payment)"
                        .into(),
                )
            })?;

            if req.tx_hashes.is_some() {
                return Err(AntdError::BadRequest(
                    "tx_hashes not applicable for merkle upload".into(),
                ));
            }

            let winner_pool_hash: [u8; 32] =
                hex::decode(winner_hash_hex.trim_start_matches("0x"))
                    .map_err(|e| {
                        AntdError::BadRequest(format!("invalid winner_pool_hash: {e}"))
                    })?
                    .try_into()
                    .map_err(|_| {
                        AntdError::BadRequest("winner_pool_hash must be 32 bytes".into())
                    })?;

            tokio::spawn(async move {
                let result = client
                    .finalize_upload_merkle(prepared, winner_pool_hash)
                    .await
                    .map_err(AntdError::from_core)?;

                let data_map_bytes = rmp_serde::to_vec(&result.data_map)
                    .map_err(|e| AntdError::Internal(format!("serialize data map: {e}")))?;
                let data_map_hex = hex::encode(data_map_bytes);

                let address = if store_on_network {
                    let addr = client
                        .data_map_store(&result.data_map)
                        .await
                        .map_err(AntdError::from_core)?;
                    Some(hex::encode(addr))
                } else {
                    None
                };

                Ok::<_, AntdError>((data_map_hex, address, result.chunks_stored))
            })
            .await
            .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??
        }
    };

    Ok(Json(FinalizeUploadResponse {
        data_map: data_map_hex,
        address,
        chunks_stored: chunks_stored as u64,
    }))
}
