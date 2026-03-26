use std::sync::Arc;

use axum::extract::State;
use axum::Json;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

// File operations are blocked on the same ant-core lifetime issue as data ops.
// The payment_mode parameter is in place on FileUploadRequest.

pub async fn file_upload_public(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<FileUploadRequest>,
) -> Result<Json<FileUploadPublicResponse>, AntdError> {
    Err(AntdError::NotImplemented("file upload pending ant-core fix".into()))
}

pub async fn file_download_public(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<FileDownloadRequest>,
) -> Result<axum::http::StatusCode, AntdError> {
    Err(AntdError::NotImplemented("file download pending ant-core fix".into()))
}

pub async fn dir_upload_public(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<FileUploadRequest>,
) -> Result<Json<DirUploadPublicResponse>, AntdError> {
    Err(AntdError::NotImplemented("directory upload pending ant-core fix".into()))
}

pub async fn dir_download_public(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<FileDownloadRequest>,
) -> Result<axum::http::StatusCode, AntdError> {
    Err(AntdError::NotImplemented("directory download pending ant-core fix".into()))
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
