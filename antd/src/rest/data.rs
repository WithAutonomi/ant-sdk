use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::Json;
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use bytes::Bytes;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn data_put_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataPutRequest>,
) -> Result<Json<DataPutPublicResponse>, AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::ServiceUnavailable(
            "wallet not configured — set AUTONOMI_WALLET_KEY".into(),
        ));
    }

    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let mode = parse_payment_mode(req.payment_mode.as_deref()).map_err(AntdError::BadRequest)?;

    let client = state.client.clone();
    let (address, chunks_stored, payment_mode_used) = tokio::spawn(async move {
        let result = client
            .data_upload_with_mode(Bytes::from(data), mode)
            .await
            .map_err(AntdError::from_core)?;
        let address = client
            .data_map_store(&result.data_map)
            .await
            .map_err(AntdError::from_core)?;
        Ok::<_, AntdError>((address, result.chunks_stored, result.payment_mode_used))
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(DataPutPublicResponse {
        address: hex::encode(address),
        chunks_stored,
        payment_mode_used: format_payment_mode(payment_mode_used),
    }))
}

pub async fn data_get_public(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<DataGetResponse>, AntdError> {
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

    let client = state.client.clone();
    let content = tokio::spawn(async move {
        let data_map = client
            .data_map_fetch(&address)
            .await
            .map_err(AntdError::from_core)?;
        client
            .data_download(&data_map)
            .await
            .map_err(AntdError::from_core)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(DataGetResponse {
        data: BASE64.encode(&content),
    }))
}

pub async fn data_put_private(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataPutRequest>,
) -> Result<Json<DataPutPrivateResponse>, AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::ServiceUnavailable(
            "wallet not configured — set AUTONOMI_WALLET_KEY".into(),
        ));
    }

    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let mode = parse_payment_mode(req.payment_mode.as_deref()).map_err(AntdError::BadRequest)?;

    let client = state.client.clone();
    let (data_map_hex, chunks_stored, payment_mode_used) = tokio::spawn(async move {
        let result = client
            .data_upload_with_mode(Bytes::from(data), mode)
            .await
            .map_err(AntdError::from_core)?;
        let data_map_bytes = rmp_serde::to_vec(&result.data_map)
            .map_err(|e| AntdError::Internal(format!("failed to serialize data map: {e}")))?;
        Ok::<_, AntdError>((
            hex::encode(data_map_bytes),
            result.chunks_stored,
            result.payment_mode_used,
        ))
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(DataPutPrivateResponse {
        data_map: data_map_hex,
        chunks_stored,
        payment_mode_used: format_payment_mode(payment_mode_used),
    }))
}

pub async fn data_get_private(
    State(state): State<Arc<AppState>>,
    Query(query): Query<DataGetPrivateQuery>,
) -> Result<Json<DataGetResponse>, AntdError> {
    let data_map_bytes = hex::decode(&query.data_map)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex data_map: {e}")))?;

    // Reject oversized data maps before deserialization (10 MB limit)
    const MAX_DATA_MAP_SIZE: usize = 10 * 1024 * 1024;
    if data_map_bytes.len() > MAX_DATA_MAP_SIZE {
        return Err(AntdError::BadRequest(format!(
            "data map too large: {} bytes exceeds {} byte limit",
            data_map_bytes.len(),
            MAX_DATA_MAP_SIZE,
        )));
    }

    let data_map: ant_core::data::DataMap = rmp_serde::from_slice(&data_map_bytes)
        .map_err(|e| AntdError::BadRequest(format!("invalid data map: {e}")))?;

    let client = state.client.clone();
    let content = tokio::spawn(async move {
        client
            .data_download(&data_map)
            .await
            .map_err(AntdError::from_core)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(DataGetResponse {
        data: BASE64.encode(&content),
    }))
}

pub async fn data_cost(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let mode = parse_payment_mode(req.payment_mode.as_deref()).map_err(AntdError::BadRequest)?;

    // estimate_upload_cost takes a path; stage the bytes in a temp file.
    // Samples up to 5 chunk addresses instead of quoting every chunk — see
    // ant-client PR #44.
    let tmp = std::env::temp_dir().join(format!(
        "antd_cost_{}_{}.bin",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    ));
    tokio::fs::write(&tmp, &data)
        .await
        .map_err(|e| AntdError::Internal(format!("failed to stage tempfile: {e}")))?;

    let client = state.client.clone();
    let tmp_for_task = tmp.clone();
    let estimate =
        tokio::spawn(async move { client.estimate_upload_cost(&tmp_for_task, mode, None).await })
            .await
            .map_err(|e| AntdError::Internal(format!("task failed: {e}")))?;

    let _ = tokio::fs::remove_file(&tmp).await;
    let estimate = estimate.map_err(AntdError::from_core)?;

    Ok(Json(CostResponse {
        cost: estimate.storage_cost_atto,
        file_size: estimate.file_size,
        chunk_count: estimate.chunk_count,
        estimated_gas_cost_wei: estimate.estimated_gas_cost_wei,
        payment_mode: format_payment_mode(estimate.payment_mode),
    }))
}

pub async fn data_stream_public(
    State(_state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Sse<impl tokio_stream::Stream<Item = Result<Event, std::convert::Infallible>>>, AntdError>
{
    if addr.len() != 64 {
        return Err(AntdError::BadRequest(
            "address must be exactly 64 hex characters".into(),
        ));
    }
    let stream = futures::stream::empty();
    Ok(Sse::new(stream).keep_alive(KeepAlive::default()))
}
