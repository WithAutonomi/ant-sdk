use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

// TODO: Implement graph operations on top of ant-node chunk protocol.
// Graph entry types exist in ant-node but the client API for graph
// operations is not yet available.

pub async fn graph_entry_get(
    State(_state): State<Arc<AppState>>,
    Path(_addr): Path<String>,
) -> Result<Json<GraphEntryGetResponse>, AntdError> {
    Err(AntdError::Internal("graph operations not yet implemented yet".into()))
}

pub async fn graph_entry_check_existence(
    State(_state): State<Arc<AppState>>,
    Path(_addr): Path<String>,
) -> Result<StatusCode, AntdError> {
    Err(AntdError::Internal("graph operations not yet implemented yet".into()))
}

pub async fn graph_entry_put(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<GraphEntryPutRequest>,
) -> Result<Json<GraphEntryPutResponse>, AntdError> {
    Err(AntdError::Internal("graph operations not yet implemented yet".into()))
}

pub async fn graph_entry_cost(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<GraphEntryCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    Err(AntdError::Internal("graph cost not yet implemented yet".into()))
}
