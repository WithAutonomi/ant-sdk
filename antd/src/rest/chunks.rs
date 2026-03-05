use std::sync::Arc;

use axum::extract::{Path, State};
use axum::Json;
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use bytes::Bytes;

use autonomi::ChunkAddress;
use autonomi::Chunk;
use autonomi::client::payment::PaymentOption;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn chunk_get(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<ChunkGetResponse>, AntdError> {
    let address = ChunkAddress::from_hex(&addr).map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let chunk = state.client.chunk_get(&address).await?;
    Ok(Json(ChunkGetResponse {
        data: BASE64.encode(chunk.value()),
    }))
}

pub async fn chunk_put(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ChunkPutRequest>,
) -> Result<Json<ChunkPutResponse>, AntdError> {
    let data = BASE64.decode(&req.data).map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;
    let chunk = Chunk::new(Bytes::from(data));
    let (cost, address) = state
        .client
        .chunk_put(&chunk, PaymentOption::Wallet(state.wallet.clone()))
        .await?;
    Ok(Json(ChunkPutResponse {
        cost: cost.to_string(),
        address: address.to_hex(),
    }))
}
