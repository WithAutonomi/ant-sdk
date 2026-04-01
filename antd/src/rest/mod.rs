use std::sync::Arc;

use axum::extract::State;
use axum::http::{HeaderValue, Method};
use axum::routing::{get, post};
use axum::{Json, Router};
use tower_http::cors::CorsLayer;

use crate::state::AppState;
use crate::types::HealthResponse;

pub mod chunks;
pub mod data;
pub mod events;
pub mod files;
pub mod upload;
pub mod wallet;

pub fn router(state: Arc<AppState>, enable_cors: bool, rest_port: u16) -> Router {
    let app = Router::new()
        // Health
        .route("/health", get(health))
        // Data
        .route("/v1/data/public/{addr}", get(data::data_get_public))
        .route("/v1/data/public/{addr}/stream", get(data::data_stream_public))
        .route("/v1/data/public", post(data::data_put_public))
        .route("/v1/data/private", get(data::data_get_private))
        .route("/v1/data/private", post(data::data_put_private))
        .route("/v1/data/cost", post(data::data_cost))
        // Chunks
        .route("/v1/chunks/{addr}", get(chunks::chunk_get))
        .route("/v1/chunks", post(chunks::chunk_put))
        // Files
        .route("/v1/files/upload/public", post(files::file_upload_public))
        .route("/v1/files/download/public", post(files::file_download_public))
        .route("/v1/dirs/upload/public", post(files::dir_upload_public))
        .route("/v1/dirs/download/public", post(files::dir_download_public))
        // Cost
        .route("/v1/cost/file", post(files::file_cost))
        // External signer (two-phase upload)
        .route("/v1/upload/prepare", post(upload::prepare_upload))
        .route("/v1/data/prepare", post(upload::prepare_data_upload))
        .route("/v1/upload/finalize", post(upload::finalize_upload))
        // Wallet
        .route("/v1/wallet/address", get(wallet::wallet_address))
        .route("/v1/wallet/balance", get(wallet::wallet_balance))
        .route("/v1/wallet/approve", post(wallet::wallet_approve))
        .with_state(state);

    if enable_cors {
        // Restrict CORS to the daemon's own localhost origin to prevent
        // cross-origin CSRF from malicious webpages. Non-browser clients
        // (SDKs, CLI, AI agents) don't send Origin headers so are unaffected.
        let origin: HeaderValue = format!("http://127.0.0.1:{rest_port}")
            .parse()
            .expect("valid origin header");
        let cors = CorsLayer::new()
            .allow_origin(origin)
            .allow_methods([Method::GET, Method::POST, Method::HEAD, Method::OPTIONS])
            .allow_headers(tower_http::cors::Any);
        app.layer(cors)
    } else {
        app
    }
}

async fn health(State(state): State<Arc<AppState>>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok".into(),
        network: state.network.clone(),
    })
}
