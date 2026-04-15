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

    Ok(Json(FileUploadPublicResponse {
        address: hex::encode(address),
        storage_cost_atto: result.storage_cost_atto,
        gas_cost_wei: result.gas_cost_wei.to_string(),
        chunks_stored: result.chunks_stored as u64,
        payment_mode_used: format_payment_mode(result.payment_mode_used),
    }))
}

pub async fn file_download_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileDownloadRequest>,
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

    let dest = PathBuf::from(&req.dest_path);
    // Validate the parent directory exists and prevent path traversal via symlinks
    let canonical_parent = dest
        .parent()
        .ok_or_else(|| AntdError::BadRequest("dest_path has no parent directory".into()))?
        .canonicalize()
        .map_err(|e| {
            tracing::warn!(dest_path = %req.dest_path, error = %e, "invalid dest_path");
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

pub async fn dir_upload_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileUploadRequest>,
) -> Result<Json<DirUploadPublicResponse>, AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::ServiceUnavailable(
            "wallet not configured — set AUTONOMI_WALLET_KEY".into(),
        ));
    }

    let path = PathBuf::from(&req.path).canonicalize().map_err(|e| {
        tracing::warn!(path = %req.path, error = %e, "invalid directory upload path");
        AntdError::BadRequest("invalid path".into())
    })?;
    if !path.is_dir() {
        return Err(AntdError::BadRequest("path is not a directory".into()));
    }

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

    Ok(Json(DirUploadPublicResponse {
        address: hex::encode(address),
        storage_cost_atto: result.storage_cost_atto,
        gas_cost_wei: result.gas_cost_wei.to_string(),
        chunks_stored: result.chunks_stored as u64,
        payment_mode_used: format_payment_mode(result.payment_mode_used),
    }))
}

pub async fn dir_download_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileDownloadRequest>,
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

    let dest = PathBuf::from(&req.dest_path);
    // Validate the parent directory exists and prevent path traversal via symlinks
    let canonical_parent = dest
        .parent()
        .ok_or_else(|| AntdError::BadRequest("dest_path has no parent directory".into()))?
        .canonicalize()
        .map_err(|e| {
            tracing::warn!(dest_path = %req.dest_path, error = %e, "invalid dest_path");
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

pub async fn file_cost(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FileCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    let path = PathBuf::from(&req.path).canonicalize().map_err(|e| {
        tracing::warn!(path = %req.path, error = %e, "invalid file cost path");
        AntdError::BadRequest("invalid path".into())
    })?;

    // Read file, encrypt to get chunks, then quote each
    //
    // TODO: This reads the entire file into memory because self_encryption::encrypt()
    // requires Bytes. For large files this is problematic. When/if self_encryption
    // gains a streaming API (or ant-core exposes a file_cost method that handles
    // chunking internally), replace this with a streaming approach using
    // tokio::fs::File + tokio_util::io::ReaderStream.
    let client = state.client.clone();
    let total_cost = tokio::spawn(async move {
        use self_encryption::encrypt;
        let file_data = tokio::fs::read(&path)
            .await
            .map_err(|e| AntdError::Internal(format!("failed to read file: {e}")))?;

        let (_data_map, encrypted_chunks) = encrypt(bytes::Bytes::from(file_data))
            .map_err(|e| AntdError::Internal(format!("encryption failed: {e}")))?;

        let mut total = ant_core::data::U256::ZERO;
        for chunk in &encrypted_chunks {
            let address = ant_core::data::compute_address(&chunk.content);
            let data_size = chunk.content.len() as u64;
            match client.get_store_quotes(&address, data_size, 0).await {
                Ok(quotes) => {
                    for (_, _, _, price) in &quotes {
                        total = total.saturating_add(*price);
                    }
                }
                Err(e) => {
                    // AlreadyStored means no cost for this chunk
                    if !matches!(e, ant_core::data::Error::AlreadyStored) {
                        return Err(AntdError::from_core(e));
                    }
                }
            }
        }
        Ok::<_, AntdError>(total)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(CostResponse {
        cost: total_cost.to_string(),
    }))
}
