use std::sync::Arc;

use axum::extract::State;
use axum::Json;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn wallet_address(
    State(state): State<Arc<AppState>>,
) -> Result<Json<WalletAddressResponse>, AntdError> {
    let wallet = state.client.wallet()
        .ok_or_else(|| AntdError::BadRequest("no EVM wallet configured".into()))?;

    Ok(Json(WalletAddressResponse {
        address: format!("{:#x}", wallet.address()),
    }))
}

pub async fn wallet_balance(
    State(state): State<Arc<AppState>>,
) -> Result<Json<WalletBalanceResponse>, AntdError> {
    let wallet = state.client.wallet()
        .ok_or_else(|| AntdError::BadRequest("no EVM wallet configured".into()))?;

    let balance = wallet.balance_of_tokens().await
        .map_err(|e| AntdError::Internal(format!("failed to get token balance: {e}")))?;

    let gas_balance = wallet.balance_of_gas_tokens().await
        .map_err(|e| AntdError::Internal(format!("failed to get gas balance: {e}")))?;

    Ok(Json(WalletBalanceResponse {
        balance: balance.to_string(),
        gas_balance: gas_balance.to_string(),
    }))
}
