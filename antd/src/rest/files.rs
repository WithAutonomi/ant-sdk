use std::path::PathBuf;
use std::sync::Arc;

use axum::extract::State;
use axum::Json;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

/// `POST /v1/files` — private file upload.
///
/// Uploads chunks and returns the `DataMap` to the caller as hex. The DataMap
/// is NOT stored on the network; the caller is responsible for persisting it.
pub async fn file_put(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FilePutRequest>,
) -> Result<Json<FilePutResponse>, AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::ServiceUnavailable(
            "wallet not configured — set AUTONOMI_WALLET_KEY".into(),
        ));
    }

    let path = PathBuf::from(&req.path).canonicalize().map_err(|e| {
        tracing::warn!(path = %req.path, error = %e, "invalid upload path");
        AntdError::BadRequest("invalid path".into())
    })?;

    let mode = parse_payment_mode(req.payment_mode.as_deref()).map_err(AntdError::BadRequest)?;

    let client = state.client.clone();
    let result = tokio::spawn(async move {
        client
            .file_upload_with_mode(&path, mode)
            .await
            .map_err(AntdError::from_core)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    let data_map_bytes = rmp_serde::to_vec(&result.data_map)
        .map_err(|e| AntdError::Internal(format!("failed to serialize data map: {e}")))?;

    Ok(Json(FilePutResponse {
        data_map: hex::encode(data_map_bytes),
        storage_cost_atto: result.storage_cost_atto,
        gas_cost_wei: result.gas_cost_wei.to_string(),
        chunks_stored: result.chunks_stored as u64,
        payment_mode_used: format_payment_mode(result.payment_mode_used),
    }))
}

/// `POST /v1/files/public` — public file upload.
///
/// Uploads chunks, then stores the `DataMap` on-network as an additional
/// chunk (extra payment). Returns the chunk address of the stored DataMap.
pub async fn file_put_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FilePutRequest>,
) -> Result<Json<FilePutPublicResponse>, AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::ServiceUnavailable(
            "wallet not configured — set AUTONOMI_WALLET_KEY".into(),
        ));
    }

    let path = PathBuf::from(&req.path).canonicalize().map_err(|e| {
        tracing::warn!(path = %req.path, error = %e, "invalid upload path");
        AntdError::BadRequest("invalid path".into())
    })?;

    let mode = parse_payment_mode(req.payment_mode.as_deref()).map_err(AntdError::BadRequest)?;

    let client = state.client.clone();
    let (result, address) = tokio::spawn(async move {
        let result = client
            .file_upload_with_mode(&path, mode)
            .await
            .map_err(AntdError::from_core)?;
        let address = client
            .data_map_store(&result.data_map)
            .await
            .map_err(AntdError::from_core)?;
        Ok::<_, AntdError>((result, address))
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(FilePutPublicResponse {
        address: hex::encode(address),
        storage_cost_atto: result.storage_cost_atto,
        gas_cost_wei: result.gas_cost_wei.to_string(),
        chunks_stored: result.chunks_stored as u64,
        payment_mode_used: format_payment_mode(result.payment_mode_used),
    }))
}

/// `POST /v1/files/get` — private file download from a caller-held DataMap.
pub async fn file_get(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileGetRequest>,
) -> Result<axum::http::StatusCode, AntdError> {
    let data_map_bytes = hex::decode(&req.data_map)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex data_map: {e}")))?;

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

    let dest = canonical_dest(&req.dest_path)?;

    let client = state.client.clone();
    tokio::spawn(async move {
        client
            .file_download(&data_map, &dest)
            .await
            .map_err(AntdError::from_core)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(axum::http::StatusCode::OK)
}

/// `POST /v1/files/public/get` — public file download by on-network DataMap address.
pub async fn file_get_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileGetPublicRequest>,
) -> Result<axum::http::StatusCode, AntdError> {
    if req.address.len() != 64 {
        return Err(AntdError::BadRequest(
            "address must be exactly 64 hex characters".into(),
        ));
    }
    let address_bytes = hex::decode(&req.address)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex address: {e}")))?;
    let address: [u8; 32] = address_bytes
        .try_into()
        .map_err(|_| AntdError::BadRequest("address must be 32 bytes".into()))?;

    let dest = canonical_dest(&req.dest_path)?;

    let client = state.client.clone();
    tokio::spawn(async move {
        let data_map = client
            .data_map_fetch(&address)
            .await
            .map_err(AntdError::from_core)?;
        client
            .file_download(&data_map, &dest)
            .await
            .map_err(AntdError::from_core)?;
        Ok::<_, AntdError>(())
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(axum::http::StatusCode::OK)
}

/// `POST /v1/files/cost` — pre-upload cost estimate. Unchanged from before
/// the rename apart from the function name (was already `file_cost`).
pub async fn file_cost(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    let path = PathBuf::from(&req.path).canonicalize().map_err(|e| {
        tracing::warn!(path = %req.path, error = %e, "invalid file cost path");
        AntdError::BadRequest("invalid path".into())
    })?;

    let mode = parse_payment_mode(req.payment_mode.as_deref()).map_err(AntdError::BadRequest)?;

    let client = state.client.clone();
    let estimate =
        tokio::spawn(async move { client.estimate_upload_cost(&path, mode, None).await })
            .await
            .map_err(|e| AntdError::Internal(format!("task failed: {e}")))?
            .map_err(AntdError::from_core)?;

    let (chunk_count, cost) = if req.is_public {
        adjust_for_public_upload(estimate.chunk_count, &estimate.storage_cost_atto)
    } else {
        (estimate.chunk_count, estimate.storage_cost_atto)
    };

    Ok(Json(CostResponse {
        cost,
        file_size: estimate.file_size,
        chunk_count,
        estimated_gas_cost_wei: estimate.estimated_gas_cost_wei,
        payment_mode: format_payment_mode(estimate.payment_mode),
    }))
}

/// Validate `dest_path`: parent must exist (canonicalize), and the resolved
/// destination must stay inside that canonical parent (no symlink escape).
fn canonical_dest(dest_path: &str) -> Result<PathBuf, AntdError> {
    let dest = PathBuf::from(dest_path);
    let canonical_parent = dest
        .parent()
        .ok_or_else(|| AntdError::BadRequest("dest_path has no parent directory".into()))?
        .canonicalize()
        .map_err(|e| {
            tracing::warn!(dest_path = %dest_path, error = %e, "invalid dest_path");
            AntdError::BadRequest("invalid destination path".into())
        })?;
    let dest = canonical_parent.join(
        dest.file_name()
            .ok_or_else(|| AntdError::BadRequest("dest_path has no filename".into()))?,
    );
    if !dest.starts_with(&canonical_parent) {
        return Err(AntdError::BadRequest(
            "destination path escapes allowed directory".into(),
        ));
    }
    Ok(dest)
}
