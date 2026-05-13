use std::collections::HashMap;
use std::sync::Arc;

use axum::extract::{Path, State};
use axum::Json;
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use bytes::Bytes;

use crate::error::AntdError;
use crate::evm_defaults;
use crate::state::{AppState, TimestampedChunk};
use crate::types::*;

pub async fn chunk_get(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<ChunkGetResponse>, AntdError> {
    if addr.len() != 64 {
        return Err(AntdError::BadRequest(
            "address must be exactly 64 hex characters".into(),
        ));
    }
    let address_bytes = hex::decode(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex address: {e}")))?;
    let address: [u8; 32] = address_bytes
        .try_into()
        .map_err(|_| AntdError::BadRequest("address must be 32 bytes".into()))?;

    let chunk = state
        .client
        .chunk_get(&address)
        .await
        .map_err(AntdError::from_core)?
        .ok_or_else(|| AntdError::NotFound("chunk not found".into()))?;

    Ok(Json(ChunkGetResponse {
        data: BASE64.encode(&chunk.content),
    }))
}

pub async fn chunk_put(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ChunkPutRequest>,
) -> Result<Json<ChunkPutResponse>, AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::ServiceUnavailable(
            "wallet not configured — set AUTONOMI_WALLET_KEY".into(),
        ));
    }

    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let content = Bytes::from(data);
    let address = state
        .client
        .chunk_put(content)
        .await
        .map_err(AntdError::from_core)?;

    Ok(Json(ChunkPutResponse {
        // ant-core chunk_put returns only the address; cost is pre-paid via
        // the wallet and not reported back per-chunk.
        cost: String::new(),
        address: hex::encode(address),
    }))
}

/// `POST /v1/chunks/prepare` — single-chunk external-signer prepare.
///
/// Quotes the close group for storing the supplied bytes as one chunk, stashes
/// the prepared state under a fresh `upload_id`, and returns the wave-batch
/// payment shape. After the external signer pays, the caller hits
/// [`chunk_finalize`] with the resulting `tx_hashes`.
///
/// When the chunk is already on-network, returns `already_stored: true` with
/// the existing address and no `upload_id` — payment is unnecessary.
///
/// Unlike `chunk_put`, this handler does NOT require the daemon to have a
/// wallet; all funds flow through the external signer.
pub async fn chunk_prepare(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PrepareChunkRequest>,
) -> Result<Json<PrepareChunkResponse>, AntdError> {
    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;
    let content = Bytes::from(data);

    // Compute the content address up-front so the "already stored" response
    // can still return it without re-quoting. ant-core's prepare path also
    // computes this internally, but it doesn't surface the address on the
    // Ok(None) path.
    let address_hex = hex::encode(ant_core::data::compute_address(&content));

    let client = state.client.clone();
    let prepared = tokio::spawn(async move {
        client
            .prepare_chunk_payment(content)
            .await
            .map_err(AntdError::from_core)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    let Some(prepared) = prepared else {
        // Already on-network — no payment needed, no finalize call needed.
        return Ok(Json(PrepareChunkResponse {
            address: address_hex,
            already_stored: true,
            upload_id: None,
            payment_type: None,
            payments: Vec::new(),
            total_amount: None,
            payment_vault_address: None,
            payment_token_address: None,
            rpc_url: None,
        }));
    };

    let evm_cfg = evm_defaults::resolve(&state.network);

    // Filter out zero-amount quotes — they go into peer_quotes for ProofOfPayment
    // but the external signer doesn't need a `payForQuotes` entry for them
    // (and including them would charge for nothing).
    let payments: Vec<PaymentEntry> = prepared
        .payment
        .quotes
        .iter()
        .filter(|q| !q.amount.is_zero())
        .map(|q| PaymentEntry {
            quote_hash: format!("{:#x}", q.quote_hash),
            rewards_address: format!("{:#x}", q.rewards_address),
            amount: q.amount.to_string(),
        })
        .collect();
    let total_amount = prepared.payment.total_amount().to_string();

    let upload_id = hex::encode(rand::random::<[u8; 16]>());
    state.pending_chunks.lock().await.insert(
        upload_id.clone(),
        TimestampedChunk {
            prepared,
            created_at: std::time::Instant::now(),
        },
    );

    Ok(Json(PrepareChunkResponse {
        address: address_hex,
        already_stored: false,
        upload_id: Some(upload_id),
        payment_type: Some("wave_batch".into()),
        payments,
        total_amount: Some(total_amount),
        payment_vault_address: Some(evm_cfg.vault_addr),
        payment_token_address: Some(evm_cfg.token_addr),
        rpc_url: Some(evm_cfg.rpc_url),
    }))
}

/// `POST /v1/chunks/finalize` — submit the chunk to the network after
/// external payment.
///
/// Looks up the prepared chunk by `upload_id`, builds the [`PaymentProof`]
/// from the supplied `tx_hashes`, and stores the chunk on `CLOSE_GROUP_MAJORITY`
/// peers via [`ant_core::data::Client::finalize_chunk`].
pub async fn chunk_finalize(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FinalizeChunkRequest>,
) -> Result<Json<FinalizeChunkResponse>, AntdError> {
    use evmlib::common::{QuoteHash, TxHash};

    let timestamped = state
        .pending_chunks
        .lock()
        .await
        .remove(&req.upload_id)
        .ok_or_else(|| {
            AntdError::NotFound(format!(
                "upload_id {} not found — it may have expired or already been finalized",
                req.upload_id
            ))
        })?;

    let tx_hash_map: HashMap<QuoteHash, TxHash> = req
        .tx_hashes
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

    let client = state.client.clone();
    let prepared = timestamped.prepared;
    let address = tokio::spawn(async move {
        client
            .finalize_chunk(prepared, &tx_hash_map)
            .await
            .map_err(AntdError::from_core)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(FinalizeChunkResponse {
        address: hex::encode(address),
    }))
}
