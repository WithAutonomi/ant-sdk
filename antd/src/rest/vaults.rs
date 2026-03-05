use std::sync::Arc;

use axum::extract::{Query, State};
use axum::Json;
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use bytes::Bytes;

use autonomi::SecretKey;
use autonomi::client::payment::PaymentOption;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn vault_get(
    State(state): State<Arc<AppState>>,
    Query(query): Query<VaultGetQuery>,
) -> Result<Json<VaultGetResponse>, AntdError> {
    let sk = parse_secret_key(&query.secret_key)?;
    let (data, content_type) = state.client.vault_get(&sk).await?;
    Ok(Json(VaultGetResponse {
        data: BASE64.encode(&data),
        content_type,
    }))
}

pub async fn vault_put(
    State(state): State<Arc<AppState>>,
    Json(req): Json<VaultPutRequest>,
) -> Result<Json<VaultPutResponse>, AntdError> {
    let sk = parse_secret_key(&req.secret_key)?;
    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;
    let cost = state
        .client
        .vault_put(
            Bytes::from(data),
            PaymentOption::Wallet(state.wallet.clone()),
            &sk,
            req.content_type,
        )
        .await?;
    Ok(Json(VaultPutResponse {
        cost: cost.to_string(),
    }))
}

pub async fn vault_cost(
    State(state): State<Arc<AppState>>,
    Json(req): Json<VaultCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    let sk = parse_secret_key(&req.secret_key)?;
    let cost = state.client.vault_cost(&sk, req.max_size).await?;
    Ok(Json(CostResponse {
        cost: cost.to_string(),
    }))
}

fn parse_secret_key(hex_str: &str) -> Result<SecretKey, AntdError> {
    let bytes = hex::decode(hex_str).map_err(|e| AntdError::BadRequest(format!("invalid hex: {e}")))?;
    let arr: [u8; 32] = bytes
        .try_into()
        .map_err(|_| AntdError::BadRequest("secret key must be 32 bytes".into()))?;
    SecretKey::from_bytes(arr).map_err(|e| AntdError::BadRequest(format!("invalid secret key: {e}")))
}
