use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use bytes::Bytes;

use autonomi::{PublicKey, ScratchpadAddress, SecretKey};
use autonomi::client::payment::PaymentOption;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn scratchpad_get(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<ScratchpadGetResponse>, AntdError> {
    let address = ScratchpadAddress::from_hex(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let scratchpad = state.client.scratchpad_get(&address).await?;
    Ok(Json(ScratchpadGetResponse {
        address: scratchpad.address().to_hex(),
        data_encoding: scratchpad.data_encoding(),
        data: BASE64.encode(scratchpad.encrypted_data()),
        counter: scratchpad.counter(),
    }))
}

pub async fn scratchpad_check_existence(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<StatusCode, AntdError> {
    let address = ScratchpadAddress::from_hex(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let exists = state.client.scratchpad_check_existence(&address).await?;
    Ok(if exists {
        StatusCode::OK
    } else {
        StatusCode::NOT_FOUND
    })
}

pub async fn scratchpad_create(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ScratchpadCreateRequest>,
) -> Result<Json<ScratchpadCreateResponse>, AntdError> {
    let owner = parse_secret_key(&req.owner_secret_key)?;
    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;
    let (cost, address) = state
        .client
        .scratchpad_create(
            &owner,
            req.content_type,
            &Bytes::from(data),
            PaymentOption::Wallet(state.wallet.clone()),
        )
        .await?;
    Ok(Json(ScratchpadCreateResponse {
        cost: cost.to_string(),
        address: address.to_hex(),
    }))
}

pub async fn scratchpad_update(
    State(state): State<Arc<AppState>>,
    Path(_addr): Path<String>,
    Json(req): Json<ScratchpadUpdateRequest>,
) -> Result<StatusCode, AntdError> {
    let owner = parse_secret_key(&req.owner_secret_key)?;
    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;
    state
        .client
        .scratchpad_update(&owner, req.content_type, &Bytes::from(data))
        .await?;
    Ok(StatusCode::OK)
}

pub async fn scratchpad_cost(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ScratchpadCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    let pk = PublicKey::from_hex(&req.public_key)
        .map_err(|e| AntdError::BadRequest(format!("invalid public key: {e}")))?;
    let cost = state.client.scratchpad_cost(&pk).await?;
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
