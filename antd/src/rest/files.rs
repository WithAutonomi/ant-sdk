use std::path::PathBuf;
use std::sync::Arc;

use axum::extract::State;
use axum::Json;

use autonomi::data::DataAddress;
use autonomi::files::{Metadata, PublicArchive};
use autonomi::client::payment::PaymentOption;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn file_upload_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileUploadRequest>,
) -> Result<Json<FileUploadPublicResponse>, AntdError> {
    let path = PathBuf::from(&req.path);
    let (cost, address) = state
        .client
        .file_content_upload_public(path, PaymentOption::Wallet(state.wallet.clone()).into())
        .await?;
    Ok(Json(FileUploadPublicResponse {
        cost: cost.to_string(),
        address: address.to_hex(),
    }))
}

pub async fn file_download_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileDownloadRequest>,
) -> Result<axum::http::StatusCode, AntdError> {
    let address = DataAddress::from_hex(&req.address)
        .map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let dest = PathBuf::from(&req.dest_path);
    state
        .client
        .file_download_public(&address, dest)
        .await?;
    Ok(axum::http::StatusCode::OK)
}

pub async fn dir_upload_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileUploadRequest>,
) -> Result<Json<DirUploadPublicResponse>, AntdError> {
    let path = PathBuf::from(&req.path);
    let (cost, address) = state
        .client
        .dir_upload_public(path, &state.wallet)
        .await?;
    Ok(Json(DirUploadPublicResponse {
        cost: cost.to_string(),
        address: address.to_hex(),
    }))
}

pub async fn dir_download_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileDownloadRequest>,
) -> Result<axum::http::StatusCode, AntdError> {
    let address = DataAddress::from_hex(&req.address)
        .map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let dest = PathBuf::from(&req.dest_path);
    state
        .client
        .dir_download_public(&address, dest)
        .await?;
    Ok(axum::http::StatusCode::OK)
}

pub async fn archive_get_public(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(addr): axum::extract::Path<String>,
) -> Result<Json<ArchiveDto>, AntdError> {
    let address = DataAddress::from_hex(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let archive = state.client.archive_get_public(&address).await?;
    let entries = archive
        .iter()
        .map(|(path, addr, meta)| ArchiveEntryDto {
            path: path.display().to_string(),
            address: addr.to_hex(),
            created: meta.created,
            modified: meta.modified,
            size: meta.size,
        })
        .collect();
    Ok(Json(ArchiveDto { entries }))
}

pub async fn archive_put_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ArchiveDto>,
) -> Result<Json<ArchivePutResponse>, AntdError> {
    let mut archive = PublicArchive::new();
    for entry in &req.entries {
        let addr = DataAddress::from_hex(&entry.address)
            .map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
        let meta = Metadata {
            created: entry.created,
            modified: entry.modified,
            size: entry.size,
            extra: None,
        };
        archive.add_file(PathBuf::from(&entry.path), addr, meta);
    }
    let (cost, address) = state
        .client
        .archive_put_public(&archive, PaymentOption::Wallet(state.wallet.clone()))
        .await?;
    Ok(Json(ArchivePutResponse {
        cost: cost.to_string(),
        address: address.to_hex(),
    }))
}

pub async fn file_cost(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    let path = PathBuf::from(&req.path);
    let cost = state
        .client
        .file_cost(&path, req.is_public, req.include_archive)
        .await
        .map_err(|e| AntdError::Internal(format!("file cost error: {e}")))?;
    Ok(Json(CostResponse {
        cost: cost.to_string(),
    }))
}
