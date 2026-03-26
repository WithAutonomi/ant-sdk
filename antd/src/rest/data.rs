use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::Json;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

// Data operations are blocked on an upstream lifetime issue in ant-core's
// stream closures (data_upload_with_mode, data_download). The types and
// payment_mode parameter are in place — implementations will land once
// ant-core is fixed.

pub async fn data_put_public(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<DataPutRequest>,
) -> Result<Json<DataPutPublicResponse>, AntdError> {
    Err(AntdError::NotImplemented("data put public pending ant-core fix".into()))
}

pub async fn data_get_public(
    State(_state): State<Arc<AppState>>,
    Path(_addr): Path<String>,
) -> Result<Json<DataGetResponse>, AntdError> {
    Err(AntdError::NotImplemented("data get public pending ant-core fix".into()))
}

pub async fn data_put_private(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<DataPutRequest>,
) -> Result<Json<DataPutPrivateResponse>, AntdError> {
    Err(AntdError::NotImplemented("data put private pending ant-core fix".into()))
}

pub async fn data_get_private(
    State(_state): State<Arc<AppState>>,
    Query(_query): Query<DataGetPrivateQuery>,
) -> Result<Json<DataGetResponse>, AntdError> {
    Err(AntdError::NotImplemented("data get private pending ant-core fix".into()))
}

pub async fn data_cost(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<DataCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    Err(AntdError::NotImplemented("data cost estimation not yet available".into()))
}

pub async fn data_stream_public(
    State(_state): State<Arc<AppState>>,
    Path(_addr): Path<String>,
) -> Result<Sse<impl tokio_stream::Stream<Item = Result<Event, std::convert::Infallible>>>, AntdError> {
    let stream = futures::stream::empty();
    Ok(Sse::new(stream).keep_alive(KeepAlive::default()))
}
