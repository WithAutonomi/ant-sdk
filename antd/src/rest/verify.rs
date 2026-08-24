//! `POST /v1/verify/quotes` — stateless offline verification of signed
//! payment quotes (hosted payments, V2-854 work item 1b).
//!
//! Pure function of the request: no network, no wallet, no session state.
//! Run by "the party about to pay" — in hosted mode, the payment gateway
//! calls it on its own antd instance (never the customer's) before paying a
//! `/pay` batch. Malformed inputs yield per-entry `valid: false` verdicts,
//! not transport errors; only an unparseable request body is a 400.

use std::sync::Arc;

use axum::extract::State;
use axum::Json;

use crate::error::AntdError;
use crate::signed_quotes;
use crate::state::AppState;
use crate::types::{VerifyQuotesRequest, VerifyQuotesResponse};

pub async fn verify_quotes(
    State(_state): State<Arc<AppState>>,
    Json(req): Json<VerifyQuotesRequest>,
) -> Result<Json<VerifyQuotesResponse>, AntdError> {
    if req.entries.len() > signed_quotes::MAX_VERIFY_ENTRIES {
        return Err(AntdError::BadRequest(format!(
            "too many entries: {} (max {})",
            req.entries.len(),
            signed_quotes::MAX_VERIFY_ENTRIES
        )));
    }

    // CPU-bound (ML-DSA-65 verifications) — keep it off the async reactor.
    let verdicts = tokio::task::spawn_blocking(move || {
        req.entries
            .iter()
            .map(signed_quotes::verify_entry)
            .collect::<Vec<_>>()
    })
    .await
    .map_err(|e| AntdError::Internal(format!("verify task failed: {e}")))?;

    Ok(Json(VerifyQuotesResponse {
        valid: !verdicts.is_empty() && verdicts.iter().all(|v| v.valid),
        entries: verdicts,
    }))
}
