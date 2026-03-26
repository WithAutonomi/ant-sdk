use std::path::PathBuf;
use std::sync::Arc;

use axum::extract::State;
use axum::Json;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn file_upload_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileUploadRequest>,
) -> Result<Json<FileUploadPublicResponse>, AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::Payment("no EVM wallet configured — set AUTONOMI_WALLET_KEY".into()));
    }

    let path = PathBuf::from(&req.path);
    if !path.exists() {
        return Err(AntdError::BadRequest(format!("file not found: {}", req.path)));
    }

    let mode = parse_payment_mode(req.payment_mode.as_deref())
        .map_err(AntdError::BadRequest)?;

    let client = state.client.clone();
    let address = tokio::spawn(async move {
        let result = client.file_upload_with_mode(&path, mode).await
            .map_err(AntdError::from_core)?;
        let address = client.data_map_store(&result.data_map).await
            .map_err(AntdError::from_core)?;
        Ok::<_, AntdError>(address)
    }).await.map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(FileUploadPublicResponse {
        cost: String::new(),
        address: hex::encode(address),
    }))
}

pub async fn file_download_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileDownloadRequest>,
) -> Result<axum::http::StatusCode, AntdError> {
    let address_bytes = hex::decode(&req.address)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex address: {e}")))?;
    let address: [u8; 32] = address_bytes
        .try_into()
        .map_err(|_| AntdError::BadRequest("address must be 32 bytes".into()))?;

    let dest = PathBuf::from(&req.dest_path);
    let client = state.client.clone();
    tokio::spawn(async move {
        let data_map = client.data_map_fetch(&address).await
            .map_err(AntdError::from_core)?;
        client.file_download(&data_map, &dest).await
            .map_err(AntdError::from_core)?;
        Ok::<_, AntdError>(())
    }).await.map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(axum::http::StatusCode::OK)
}

pub async fn dir_upload_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileUploadRequest>,
) -> Result<Json<DirUploadPublicResponse>, AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::Payment("no EVM wallet configured — set AUTONOMI_WALLET_KEY".into()));
    }

    let path = PathBuf::from(&req.path);
    if !path.is_dir() {
        return Err(AntdError::BadRequest(format!("not a directory: {}", req.path)));
    }

    let mode = parse_payment_mode(req.payment_mode.as_deref())
        .map_err(AntdError::BadRequest)?;

    let client = state.client.clone();
    let address = tokio::spawn(async move {
        let result = client.file_upload_with_mode(&path, mode).await
            .map_err(AntdError::from_core)?;
        let address = client.data_map_store(&result.data_map).await
            .map_err(AntdError::from_core)?;
        Ok::<_, AntdError>(address)
    }).await.map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(DirUploadPublicResponse {
        cost: String::new(),
        address: hex::encode(address),
    }))
}

pub async fn dir_download_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileDownloadRequest>,
) -> Result<axum::http::StatusCode, AntdError> {
    let address_bytes = hex::decode(&req.address)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex address: {e}")))?;
    let address: [u8; 32] = address_bytes
        .try_into()
        .map_err(|_| AntdError::BadRequest("address must be 32 bytes".into()))?;

    let dest = PathBuf::from(&req.dest_path);
    let client = state.client.clone();
    tokio::spawn(async move {
        let data_map = client.data_map_fetch(&address).await
            .map_err(AntdError::from_core)?;
        client.file_download(&data_map, &dest).await
            .map_err(AntdError::from_core)?;
        Ok::<_, AntdError>(())
    }).await.map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(axum::http::StatusCode::OK)
}

pub async fn archive_get_public(
    State(_state): State<Arc<AppState>>,
    axum::extract::Path(_addr): axum::extract::Path<String>,
) -> Result<Json<ArchiveDto>, AntdError> {
    Err(AntdError::NotImplemented("archive operations not yet available".into()))
}

pub async fn archive_put_public(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<ArchiveDto>,
) -> Result<Json<ArchivePutResponse>, AntdError> {
    Err(AntdError::NotImplemented("archive operations not yet available".into()))
}

pub async fn file_cost(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<FileCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    Err(AntdError::NotImplemented("file cost estimation not yet available".into()))
}
