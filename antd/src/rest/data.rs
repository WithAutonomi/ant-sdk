use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::Json;
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

// TODO: Implement data operations on top of ant-node chunk protocol.
// Data operations require multi-chunk handling (chunking, self-encryption)
// which is not yet available in the ant-node client.

pub async fn data_get_public(
    State(_state): State<Arc<AppState>>,
    Path(_addr): Path<String>,
) -> Result<Json<DataGetResponse>, AntdError> {
    Err(AntdError::NotImplemented("data operations not yet implemented yet".into()))
}

pub async fn data_put_public(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<DataPutRequest>,
) -> Result<Json<DataPutPublicResponse>, AntdError> {
    Err(AntdError::NotImplemented("data operations not yet implemented yet".into()))
}

pub async fn data_get_private(
    State(_state): State<Arc<AppState>>,
    Query(_query): Query<DataGetPrivateQuery>,
) -> Result<Json<DataGetResponse>, AntdError> {
    Err(AntdError::NotImplemented("private data operations not yet implemented yet".into()))
}

pub async fn data_put_private(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<DataPutRequest>,
) -> Result<Json<DataPutPrivateResponse>, AntdError> {
    Err(AntdError::NotImplemented("private data operations not yet implemented yet".into()))
}

pub async fn data_cost(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<DataCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    Err(AntdError::NotImplemented("data cost not yet implemented yet".into()))
}

pub async fn data_stream_public(
    State(_state): State<Arc<AppState>>,
    Path(_addr): Path<String>,
) -> Result<Sse<impl tokio_stream::Stream<Item = Result<Event, std::convert::Infallible>>>, AntdError> {
    // Return an empty stream for now
    let stream = futures::stream::empty();
    Ok(Sse::new(stream).keep_alive(KeepAlive::default()))
}
