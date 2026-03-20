use std::sync::Arc;

use axum::extract::State;
use axum::Json;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

// TODO: Implement file operations on top of saorsa chunk protocol.
// File operations require chunking, FEC encoding, and archive manifests
// which need to be built on top of the raw chunk layer.

pub async fn file_upload_public(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<FileUploadRequest>,
) -> Result<Json<FileUploadPublicResponse>, AntdError> {
    Err(AntdError::Internal("file operations not yet implemented for saorsa".into()))
}

pub async fn file_download_public(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<FileDownloadRequest>,
) -> Result<axum::http::StatusCode, AntdError> {
    Err(AntdError::Internal("file operations not yet implemented for saorsa".into()))
}

pub async fn dir_upload_public(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<FileUploadRequest>,
) -> Result<Json<DirUploadPublicResponse>, AntdError> {
    Err(AntdError::Internal("directory operations not yet implemented for saorsa".into()))
}

pub async fn dir_download_public(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<FileDownloadRequest>,
) -> Result<axum::http::StatusCode, AntdError> {
    Err(AntdError::Internal("directory operations not yet implemented for saorsa".into()))
}

pub async fn archive_get_public(
    State(_state): State<Arc<AppState>>,
    axum::extract::Path(_addr): axum::extract::Path<String>,
) -> Result<Json<ArchiveDto>, AntdError> {
    Err(AntdError::Internal("archive operations not yet implemented for saorsa".into()))
}

pub async fn archive_put_public(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<ArchiveDto>,
) -> Result<Json<ArchivePutResponse>, AntdError> {
    Err(AntdError::Internal("archive operations not yet implemented for saorsa".into()))
}

pub async fn file_cost(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<FileCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    Err(AntdError::Internal("file cost not yet implemented for saorsa".into()))
}
