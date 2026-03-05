use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::Json;
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use bytes::Bytes;
use futures::stream;
use tokio_stream::StreamExt;

use autonomi::client::payment::PaymentOption;
use autonomi::data::DataAddress;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn data_get_public(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<DataGetResponse>, AntdError> {
    let address = DataAddress::from_hex(&addr).map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let data = state.client.data_get_public(&address).await?;
    Ok(Json(DataGetResponse {
        data: BASE64.encode(&data),
    }))
}

pub async fn data_put_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataPutRequest>,
) -> Result<Json<DataPutPublicResponse>, AntdError> {
    let data = BASE64.decode(&req.data).map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;
    let (cost, address) = state
        .client
        .data_put_public(Bytes::from(data), PaymentOption::Wallet(state.wallet.clone()))
        .await?;
    Ok(Json(DataPutPublicResponse {
        cost: cost.to_string(),
        address: address.to_hex(),
    }))
}

pub async fn data_get_private(
    State(state): State<Arc<AppState>>,
    Query(query): Query<DataGetPrivateQuery>,
) -> Result<Json<DataGetResponse>, AntdError> {
    let chunk_bytes = hex::decode(&query.data_map).map_err(|e| AntdError::BadRequest(format!("invalid hex: {e}")))?;
    let data_map: autonomi::chunk::DataMapChunk =
        rmp_serde::from_slice(&chunk_bytes).map_err(|e| AntdError::BadRequest(format!("invalid data map: {e}")))?;
    let data = state.client.data_get(&data_map).await?;
    Ok(Json(DataGetResponse {
        data: BASE64.encode(&data),
    }))
}

pub async fn data_put_private(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataPutRequest>,
) -> Result<Json<DataPutPrivateResponse>, AntdError> {
    let data = BASE64.decode(&req.data).map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;
    let (cost, data_map) = state
        .client
        .data_put(Bytes::from(data), PaymentOption::Wallet(state.wallet.clone()))
        .await?;
    let dm_bytes = rmp_serde::to_vec(&data_map).map_err(|e| AntdError::Internal(format!("serialize data map: {e}")))?;
    Ok(Json(DataPutPrivateResponse {
        cost: cost.to_string(),
        data_map: hex::encode(&dm_bytes),
    }))
}

pub async fn data_cost(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    let data = BASE64.decode(&req.data).map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;
    let cost = state.client.data_cost(Bytes::from(data)).await?;
    Ok(Json(CostResponse {
        cost: cost.to_string(),
    }))
}

pub async fn data_stream_public(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Sse<impl tokio_stream::Stream<Item = Result<Event, std::convert::Infallible>>>, AntdError> {
    let address = DataAddress::from_hex(&addr).map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let data_stream = state.client.data_stream_public(&address).await?;

    let sse_stream = stream::iter(data_stream).map(|chunk_result: Result<bytes::Bytes, _>| {
        Ok::<_, std::convert::Infallible>(match chunk_result {
            Ok(chunk) => Event::default().data(BASE64.encode(&chunk)),
            Err(e) => Event::default().event("error").data(e.to_string()),
        })
    });

    Ok(Sse::new(sse_stream).keep_alive(KeepAlive::default()))
}
