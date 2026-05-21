use std::sync::Arc;

use axum::extract::{DefaultBodyLimit, State};
use axum::http::{HeaderValue, Method, Request};
use axum::middleware::{self, Next};
use axum::response::Response;
use axum::routing::{get, post};
use axum::{Json, Router};
use tower_http::cors::CorsLayer;

use crate::state::AppState;
use crate::types::HealthResponse;

/// 100 MB body limit for all requests.
const MAX_BODY_SIZE: usize = 100 * 1024 * 1024;

pub mod chunks;
pub mod data;
pub mod events;
pub mod files;
pub mod upload;
pub mod wallet;

/// Generates a short random hex request ID (8 bytes = 16 hex chars).
fn generate_request_id() -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let bytes: [u8; 8] = rng.gen();
    hex::encode(bytes)
}

/// Middleware that assigns a unique request ID to each incoming request.
/// The ID is added to a tracing span (so all logs for that request are correlated)
/// and included in the response as the `x-request-id` header.
async fn request_id_middleware(request: Request<axum::body::Body>, next: Next) -> Response {
    let request_id = generate_request_id();
    let method = request.method().clone();
    let uri = request.uri().path().to_string();

    let span = tracing::info_span!(
        "request",
        request_id = %request_id,
        method = %method,
        path = %uri,
    );

    let response = {
        let _guard = span.enter();
        tracing::info!("started");
        next.run(request).await
    };

    let mut response = response;
    if let Ok(val) = HeaderValue::from_str(&request_id) {
        response.headers_mut().insert("x-request-id", val);
    }

    let _guard = span.enter();
    tracing::info!(status = %response.status(), "completed");

    response
}

pub fn router(state: Arc<AppState>, enable_cors: bool, rest_port: u16) -> Router {
    let app = Router::new()
        // Health
        .route("/health", get(health))
        // Data — convention: unqualified verb = private, `_public` suffix = public.
        .route("/v1/data", post(data::data_put))
        .route("/v1/data/get", post(data::data_get))
        .route("/v1/data/public", post(data::data_put_public))
        .route("/v1/data/public/{addr}", get(data::data_get_public))
        .route(
            "/v1/data/public/{addr}/stream",
            get(data::data_stream_public),
        )
        .route("/v1/data/cost", post(data::data_cost))
        // Chunks
        .route("/v1/chunks/{addr}", get(chunks::chunk_get))
        .route("/v1/chunks", post(chunks::chunk_put))
        .route("/v1/chunks/prepare", post(chunks::chunk_prepare))
        .route("/v1/chunks/finalize", post(chunks::chunk_finalize))
        // Files — same convention.
        .route("/v1/files", post(files::file_put))
        .route("/v1/files/get", post(files::file_get))
        .route("/v1/files/public", post(files::file_put_public))
        .route("/v1/files/public/get", post(files::file_get_public))
        .route("/v1/files/cost", post(files::file_cost))
        // External signer (two-phase upload)
        .route("/v1/upload/prepare", post(upload::prepare_upload))
        .route("/v1/data/prepare", post(upload::prepare_data_upload))
        .route("/v1/upload/finalize", post(upload::finalize_upload))
        // Wallet
        .route("/v1/wallet/address", get(wallet::wallet_address))
        .route("/v1/wallet/balance", get(wallet::wallet_balance))
        .route("/v1/wallet/approve", post(wallet::wallet_approve))
        // Layers (innermost first)
        .layer(DefaultBodyLimit::max(MAX_BODY_SIZE))
        // Request ID middleware — generates ID, adds tracing span + response header
        .layer(middleware::from_fn(request_id_middleware))
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
        version: state.version.clone(),
        evm_network: state.evm_preset.clone(),
        uptime_seconds: state.started_at.elapsed().as_secs(),
        build_commit: state.build_commit.clone(),
        payment_token_address: state.evm_token_addr.clone(),
        payment_vault_address: state.evm_vault_addr.clone(),
    })
}
