use std::sync::Arc;

use axum::extract::{Path, State};
use axum::Json;

use autonomi::{PublicKey, SecretKey};
use autonomi::register::RegisterAddress;
use autonomi::client::payment::PaymentOption;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn register_get(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<RegisterGetResponse>, AntdError> {
    let address = RegisterAddress::from_hex(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let value = state.client.register_get(&address).await?;
    Ok(Json(RegisterGetResponse {
        value: hex::encode(value),
    }))
}

pub async fn register_create(
    State(state): State<Arc<AppState>>,
    Json(req): Json<RegisterCreateRequest>,
) -> Result<Json<RegisterCreateResponse>, AntdError> {
    let owner = parse_secret_key(&req.owner_secret_key)?;
    let value = parse_register_value(&req.initial_value)?;
    let (cost, address) = state
        .client
        .register_create(&owner, value, PaymentOption::Wallet(state.wallet.clone()))
        .await?;
    Ok(Json(RegisterCreateResponse {
        cost: cost.to_string(),
        address: address.to_hex(),
    }))
}

pub async fn register_update(
    State(state): State<Arc<AppState>>,
    Path(_addr): Path<String>,
    Json(req): Json<RegisterUpdateRequest>,
) -> Result<Json<RegisterUpdateResponse>, AntdError> {
    let owner = parse_secret_key(&req.owner_secret_key)?;
    let value = parse_register_value(&req.new_value)?;
    let cost = state
        .client
        .register_update(&owner, value, PaymentOption::Wallet(state.wallet.clone()))
        .await?;
    Ok(Json(RegisterUpdateResponse {
        cost: cost.to_string(),
    }))
}

pub async fn register_cost(
    State(state): State<Arc<AppState>>,
    Json(req): Json<RegisterCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    let pk = PublicKey::from_hex(&req.public_key)
        .map_err(|e| AntdError::BadRequest(format!("invalid public key: {e}")))?;
    let cost = state.client.register_cost(&pk).await?;
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

fn parse_register_value(hex_str: &str) -> Result<[u8; 32], AntdError> {
    let bytes = hex::decode(hex_str).map_err(|e| AntdError::BadRequest(format!("invalid hex: {e}")))?;
    if bytes.len() != 32 {
        return Err(AntdError::BadRequest(format!(
            "register value must be 32 bytes, got {}",
            bytes.len()
        )));
    }
    let mut value = [0u8; 32];
    value.copy_from_slice(&bytes);
    Ok(value)
}
