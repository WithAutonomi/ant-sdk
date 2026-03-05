use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;

use autonomi::{GraphEntryAddress, PublicKey, SecretKey};
use autonomi::graph::{GraphContent, GraphEntry};
use autonomi::client::payment::PaymentOption;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn graph_entry_get(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<GraphEntryGetResponse>, AntdError> {
    let address = GraphEntryAddress::from_hex(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let entry = state.client.graph_entry_get(&address).await?;
    Ok(Json(GraphEntryGetResponse {
        owner: entry.owner.to_hex(),
        parents: entry.parents.iter().map(|p| p.to_hex()).collect(),
        content: hex::encode(entry.content),
        descendants: entry
            .descendants
            .iter()
            .map(|(pk, c)| GraphDescendantDto {
                public_key: pk.to_hex(),
                content: hex::encode(c),
            })
            .collect(),
    }))
}

pub async fn graph_entry_check_existence(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<StatusCode, AntdError> {
    let address = GraphEntryAddress::from_hex(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid address: {e}")))?;
    let exists = state.client.graph_entry_check_existence(&address).await?;
    Ok(if exists {
        StatusCode::OK
    } else {
        StatusCode::NOT_FOUND
    })
}

pub async fn graph_entry_put(
    State(state): State<Arc<AppState>>,
    Json(req): Json<GraphEntryPutRequest>,
) -> Result<Json<GraphEntryPutResponse>, AntdError> {
    let owner = parse_secret_key(&req.owner_secret_key)?;
    let parents = req
        .parents
        .iter()
        .map(|p| {
            PublicKey::from_hex(p).map_err(|e| AntdError::BadRequest(format!("invalid parent key: {e}")))
        })
        .collect::<Result<Vec<_>, _>>()?;
    let content = parse_graph_content(&req.content)?;
    let descendants = req
        .descendants
        .iter()
        .map(|d| {
            let pk = PublicKey::from_hex(&d.public_key)
                .map_err(|e| AntdError::BadRequest(format!("invalid descendant key: {e}")))?;
            let c = parse_graph_content(&d.content)?;
            Ok((pk, c))
        })
        .collect::<Result<Vec<_>, AntdError>>()?;

    let entry = GraphEntry::new(&owner, parents, content, descendants);
    let (cost, address) = state
        .client
        .graph_entry_put(entry, PaymentOption::Wallet(state.wallet.clone()))
        .await?;
    Ok(Json(GraphEntryPutResponse {
        cost: cost.to_string(),
        address: address.to_hex(),
    }))
}

pub async fn graph_entry_cost(
    State(state): State<Arc<AppState>>,
    Json(req): Json<GraphEntryCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    let pk = PublicKey::from_hex(&req.public_key)
        .map_err(|e| AntdError::BadRequest(format!("invalid public key: {e}")))?;
    let cost = state.client.graph_entry_cost(&pk).await?;
    Ok(Json(CostResponse {
        cost: cost.to_string(),
    }))
}

fn parse_secret_key(hex_str: &str) -> Result<SecretKey, AntdError> {
    let bytes = hex::decode(hex_str).map_err(|e| AntdError::BadRequest(format!("invalid hex: {e}")))?;
    let arr: [u8; 32] = bytes
        .try_into()
        .map_err(|_| AntdError::BadRequest("secret key must be 32 bytes".into()))?;
    SecretKey::from_bytes(arr).map_err(|e| AntdError::BadRequest(format!("invalid secret key: {e}")))
}

fn parse_graph_content(hex_str: &str) -> Result<GraphContent, AntdError> {
    let bytes = hex::decode(hex_str).map_err(|e| AntdError::BadRequest(format!("invalid hex: {e}")))?;
    if bytes.len() != 32 {
        return Err(AntdError::BadRequest(format!(
            "graph content must be 32 bytes, got {}",
            bytes.len()
        )));
    }
    let mut content = [0u8; 32];
    content.copy_from_slice(&bytes);
    Ok(content)
}
