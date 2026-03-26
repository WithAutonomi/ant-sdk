use std::sync::Arc;

use axum::extract::{Path, State};
use axum::Json;
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use bytes::Bytes;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn chunk_get(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<ChunkGetResponse>, AntdError> {
    let address_bytes = hex::decode(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex address: {e}")))?;
    let address: [u8; 32] = address_bytes
        .try_into()
        .map_err(|_| AntdError::BadRequest("address must be 32 bytes".into()))?;

    let chunk = state.client.chunk_get(&address).await
        .map_err(|e| AntdError::from_core(e))?
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
        return Err(AntdError::Payment(
            "no EVM wallet configured — set AUTONOMI_WALLET_KEY".into(),
        ));
    }

    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let content = Bytes::from(data);
    let address = state.client.chunk_put(content).await
        .map_err(|e| AntdError::from_core(e))?;

    Ok(Json(ChunkPutResponse {
        cost: String::new(), // TODO: Client.chunk_put doesn't return cost yet
        address: hex::encode(address),
    }))
}
