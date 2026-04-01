use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::Json;
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use bytes::Bytes;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn data_put_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataPutRequest>,
) -> Result<Json<DataPutPublicResponse>, AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::ServiceUnavailable("wallet not configured — set AUTONOMI_WALLET_KEY".into()));
    }

    let data = BASE64.decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let mode = parse_payment_mode(req.payment_mode.as_deref())
        .map_err(AntdError::BadRequest)?;

    let client = state.client.clone();
    let (address, chunks_stored, payment_mode_used) = tokio::spawn(async move {
        let result = client.data_upload_with_mode(Bytes::from(data), mode).await
            .map_err(AntdError::from_core)?;
        let address = client.data_map_store(&result.data_map).await
            .map_err(AntdError::from_core)?;
        Ok::<_, AntdError>((address, result.chunks_stored, result.payment_mode_used))
    }).await.map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

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
        return Err(AntdError::BadRequest("address must be exactly 64 hex characters".into()));
    }
    let address_bytes = hex::decode(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex address: {e}")))?;
    let address: [u8; 32] = address_bytes
        .try_into()
        .map_err(|_| AntdError::BadRequest("address must be 32 bytes".into()))?;

    let client = state.client.clone();
    let content = tokio::spawn(async move {
        let data_map = client.data_map_fetch(&address).await
            .map_err(AntdError::from_core)?;
        client.data_download(&data_map).await
            .map_err(AntdError::from_core)
    }).await.map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(DataGetResponse {
        data: BASE64.encode(&content),
    }))
}

pub async fn data_put_private(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataPutRequest>,
) -> Result<Json<DataPutPrivateResponse>, AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::ServiceUnavailable("wallet not configured — set AUTONOMI_WALLET_KEY".into()));
    }

    let data = BASE64.decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let mode = parse_payment_mode(req.payment_mode.as_deref())
        .map_err(AntdError::BadRequest)?;

    let client = state.client.clone();
    let (data_map_hex, chunks_stored, payment_mode_used) = tokio::spawn(async move {
        let result = client.data_upload_with_mode(Bytes::from(data), mode).await
            .map_err(AntdError::from_core)?;
        let data_map_bytes = rmp_serde::to_vec(&result.data_map)
            .map_err(|e| AntdError::Internal(format!("failed to serialize data map: {e}")))?;
        Ok::<_, AntdError>((hex::encode(data_map_bytes), result.chunks_stored, result.payment_mode_used))
    }).await.map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

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
        client.data_download(&data_map).await
            .map_err(AntdError::from_core)
    }).await.map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(DataGetResponse {
        data: BASE64.encode(&content),
    }))
}

pub async fn data_cost(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    let data = BASE64.decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    // Encrypt to determine chunk count and addresses, then quote each
    let client = state.client.clone();
    let total_cost = tokio::spawn(async move {
        use self_encryption::encrypt;
        let (_data_map, encrypted_chunks) = encrypt(Bytes::from(data))
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
    }).await.map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(CostResponse {
        cost: total_cost.to_string(),
    }))
}

pub async fn data_stream_public(
    State(_state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Sse<impl tokio_stream::Stream<Item = Result<Event, std::convert::Infallible>>>, AntdError> {
    if addr.len() != 64 {
        return Err(AntdError::BadRequest("address must be exactly 64 hex characters".into()));
    }
    let stream = futures::stream::empty();
    Ok(Sse::new(stream).keep_alive(KeepAlive::default()))
}
