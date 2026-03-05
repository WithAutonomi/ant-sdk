use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;

use autonomi::{PointerAddress, PublicKey, SecretKey};
use autonomi::pointer::PointerTarget;
use autonomi::client::payment::PaymentOption;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

fn parse_pointer_target(dto: &PointerTargetDto) -> Result<PointerTarget, AntdError> {
    match dto.kind.as_str() {
        "chunk" => {
            let addr = autonomi::ChunkAddress::from_hex(&dto.address)
                .map_err(|e| AntdError::BadRequest(format!("invalid chunk address: {e}")))?;
            Ok(PointerTarget::ChunkAddress(addr))
        }
        "graph_entry" => {
            let addr = autonomi::GraphEntryAddress::from_hex(&dto.address)
                .map_err(|e| AntdError::BadRequest(format!("invalid graph address: {e}")))?;
            Ok(PointerTarget::GraphEntryAddress(addr))
        }
        "pointer" => {
            let addr = PointerAddress::from_hex(&dto.address)
                .map_err(|e| AntdError::BadRequest(format!("invalid pointer address: {e}")))?;
            Ok(PointerTarget::PointerAddress(addr))
        }
        "scratchpad" => {
            let addr = autonomi::ScratchpadAddress::from_hex(&dto.address)
                .map_err(|e| AntdError::BadRequest(format!("invalid scratchpad address: {e}")))?;
            Ok(PointerTarget::ScratchpadAddress(addr))
        }
        other => Err(AntdError::BadRequest(format!(
            "unknown pointer target kind: {other}"
        ))),
    }
}

fn pointer_target_to_dto(target: &PointerTarget) -> PointerTargetDto {
    match target {
        PointerTarget::ChunkAddress(a) => PointerTargetDto {
            kind: "chunk".into(),
            address: a.to_hex(),
        },
        PointerTarget::GraphEntryAddress(a) => PointerTargetDto {
            kind: "graph_entry".into(),
            address: a.to_hex(),
        },
        PointerTarget::PointerAddress(a) => PointerTargetDto {
            kind: "pointer".into(),
            address: a.to_hex(),
        },
        PointerTarget::ScratchpadAddress(a) => PointerTargetDto {
            kind: "scratchpad".into(),
            address: a.to_hex(),
        },
    }
}

pub async fn pointer_get(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<PointerGetResponse>, AntdError> {
    let address = PointerAddress::from_hex(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let pointer = state.client.pointer_get(&address).await?;
    Ok(Json(PointerGetResponse {
        address: pointer.address().to_hex(),
        owner: pointer.owner().to_hex(),
        counter: pointer.counter(),
        target: pointer_target_to_dto(pointer.target()),
    }))
}

pub async fn pointer_check_existence(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<StatusCode, AntdError> {
    let address = PointerAddress::from_hex(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let exists = state.client.pointer_check_existence(&address).await?;
    Ok(if exists {
        StatusCode::OK
    } else {
        StatusCode::NOT_FOUND
    })
}

pub async fn pointer_create(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PointerCreateRequest>,
) -> Result<Json<PointerCreateResponse>, AntdError> {
    let owner = parse_secret_key(&req.owner_secret_key)?;
    let target = parse_pointer_target(&req.target)?;
    let (cost, address) = state
        .client
        .pointer_create(&owner, target, PaymentOption::Wallet(state.wallet.clone()))
        .await?;
    Ok(Json(PointerCreateResponse {
        cost: cost.to_string(),
        address: address.to_hex(),
    }))
}

pub async fn pointer_update(
    State(state): State<Arc<AppState>>,
    Path(_addr): Path<String>,
    Json(req): Json<PointerUpdateRequest>,
) -> Result<StatusCode, AntdError> {
    let owner = parse_secret_key(&req.owner_secret_key)?;
    let target = parse_pointer_target(&req.target)?;
    state.client.pointer_update(&owner, target).await?;
    Ok(StatusCode::OK)
}

pub async fn pointer_cost(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PointerCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    let pk = PublicKey::from_hex(&req.public_key)
        .map_err(|e| AntdError::BadRequest(format!("invalid public key: {e}")))?;
    let cost = state.client.pointer_cost(&pk).await?;
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
