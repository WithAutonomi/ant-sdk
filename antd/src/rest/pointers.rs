//! `/v1/pointers` — pointers (ADR-0016 / ADR-0018 in `ant-node`).
//!
//! Thin over [`crate::pointers`], which the gRPC `PointerService` shares.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::Json;

use crate::error::AntdError;
use crate::pointers::{self, parse_address, parse_prepared_write, parse_target};
use crate::state::AppState;
use crate::types::*;

/// `GET /v1/pointers/keys` — the pointers this daemon can write.
pub async fn pointer_keys(State(state): State<Arc<AppState>>) -> Json<PointerKeysResponse> {
    Json(pointers::keys(&state))
}

/// `POST /v1/pointers` — create a pointer, paid by the daemon wallet.
pub async fn pointer_create(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PointerWriteRequest>,
) -> Result<Json<PointerWriteResponse>, AntdError> {
    let owner = parse_address("owner", &req.owner)?;
    let target = parse_target(&req.target, req.kind.as_deref())?;
    Ok(Json(pointers::create(&state, owner, target).await?))
}

/// `POST /v1/pointers/update` — point a pointer at a new target, paid by the
/// daemon wallet. Creates the pointer if it does not exist.
pub async fn pointer_update(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PointerWriteRequest>,
) -> Result<Json<PointerWriteResponse>, AntdError> {
    let owner = parse_address("owner", &req.owner)?;
    let target = parse_target(&req.target, req.kind.as_deref())?;
    Ok(Json(pointers::update(&state, owner, target).await?))
}

/// `POST /v1/pointers/transfer` — hand a pointer over for good, paid by the
/// daemon wallet.
pub async fn pointer_transfer(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PointerTransferRequest>,
) -> Result<Json<PointerTransferResponse>, AntdError> {
    let owner = parse_address("owner", &req.owner)?;
    let recipient = parse_address("recipient", &req.recipient)?;
    Ok(Json(pointers::transfer(&state, owner, recipient).await?))
}

/// `GET /v1/pointers/{addr}`
pub async fn pointer_get(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<PointerRecordResponse>, AntdError> {
    let address = parse_address("address", &addr)?;
    Ok(Json(pointers::get(&state, address).await?))
}

/// `GET /v1/pointers/{addr}/resolve`
pub async fn pointer_resolve(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<PointerResolveResponse>, AntdError> {
    let address = parse_address("address", &addr)?;
    Ok(Json(pointers::resolve(&state, address).await?))
}

/// `GET /v1/pointers/{addr}/finality`
pub async fn pointer_finality(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<PointerFinalityResponse>, AntdError> {
    let address = parse_address("address", &addr)?;
    Ok(Json(pointers::finality(&state, address).await?))
}

/// `GET /v1/pointers/{addr}/controller`
pub async fn pointer_controller(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<PointerControllerResponse>, AntdError> {
    let address = parse_address("address", &addr)?;
    Ok(Json(pointers::controller(&state, address).await?))
}

/// `POST /v1/pointers/prepare` — sign a write and quote it for an external
/// signer. Needs no daemon wallet.
pub async fn pointer_prepare(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PointerPrepareRequest>,
) -> Result<Json<PointerPrepareResponse>, AntdError> {
    let owner = parse_address("owner", &req.owner)?;
    let prepared = parse_prepared_write(
        &req.op,
        req.target.as_deref(),
        req.kind.as_deref(),
        req.recipient.as_deref(),
    )?;
    Ok(Json(
        pointers::prepare(&state, owner, prepared, req.include_signed_quotes).await?,
    ))
}

/// `POST /v1/pointers/finalize` — store a prepared write once it is paid.
pub async fn pointer_finalize(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PointerFinalizeRequest>,
) -> Result<Json<PointerFinalizeResponse>, AntdError> {
    Ok(Json(
        pointers::finalize(&state, &req.upload_id, &req.tx_hashes).await?,
    ))
}
