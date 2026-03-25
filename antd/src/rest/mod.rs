use std::sync::Arc;

use axum::extract::State;
use axum::http::{HeaderValue, Method};
use axum::routing::{get, head, post};
use axum::{Json, Router};
use tower_http::cors::CorsLayer;

use crate::state::AppState;
use crate::types::HealthResponse;

pub mod chunks;
pub mod data;
pub mod events;
pub mod files;
pub mod graph;
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
        // Graph
        .route("/v1/graph/{addr}", get(graph::graph_entry_get))
        .route("/v1/graph/{addr}", head(graph::graph_entry_check_existence))
        .route("/v1/graph", post(graph::graph_entry_put))
        .route("/v1/graph/cost", post(graph::graph_entry_cost))
        // Files
        .route("/v1/files/upload/public", post(files::file_upload_public))
        .route("/v1/files/download/public", post(files::file_download_public))
        .route("/v1/dirs/upload/public", post(files::dir_upload_public))
        .route("/v1/dirs/download/public", post(files::dir_download_public))
        .route("/v1/archives/public/{addr}", get(files::archive_get_public))
        .route("/v1/archives/public", post(files::archive_put_public))
        // Cost
        .route("/v1/cost/file", post(files::file_cost))
        // Wallet
        .route("/v1/wallet/address", get(wallet::wallet_address))
        .route("/v1/wallet/balance", get(wallet::wallet_balance))
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
