use std::sync::Arc;

use axum::extract::{DefaultBodyLimit, State};
use axum::http::{HeaderValue, Method, Request};
use axum::middleware::{self, Next};
use axum::response::Response;
use axum::routing::{get, post};
use axum::{Json, Router};
use tower_http::cors::{AllowOrigin, CorsLayer};

use crate::config::CorsMode;
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

/// Browser-extension origin prefixes allowed in every enabled CORS mode
/// (see [`CorsMode`] for the rationale).
const EXTENSION_ORIGIN_PREFIXES: [&str; 3] = [
    "chrome-extension://",
    "moz-extension://",
    "safari-web-extension://",
];

fn is_extension_origin(origin: &HeaderValue) -> bool {
    let Ok(origin) = origin.to_str() else {
        return false;
    };
    EXTENSION_ORIGIN_PREFIXES
        .iter()
        .any(|prefix| origin.starts_with(prefix))
}

fn cors_layer(mode: &CorsMode) -> Option<CorsLayer> {
    let allow_origin = match mode {
        CorsMode::Disabled => return None,
        CorsMode::AllowAny => AllowOrigin::any(),
        CorsMode::Extensions => AllowOrigin::predicate(|origin, _| is_extension_origin(origin)),
        CorsMode::AllowList(list) => {
            let list = list.clone();
            AllowOrigin::predicate(move |origin, _| {
                is_extension_origin(origin)
                    || list
                        .iter()
                        .any(|allowed| allowed.as_bytes() == origin.as_bytes())
            })
        }
    };
    Some(
        CorsLayer::new()
            .allow_origin(allow_origin)
            .allow_methods([Method::GET, Method::POST, Method::HEAD, Method::OPTIONS])
            .allow_headers(tower_http::cors::Any),
    )
}

pub fn router(state: Arc<AppState>, cors: &CorsMode) -> Router {
    let app = Router::new()
        // Health
        .route("/health", get(health))
        // Data — convention: unqualified verb = private, `_public` suffix = public.
        .route("/v1/data", post(data::data_put))
        .route("/v1/data/get", post(data::data_get))
        .route("/v1/data/stream", post(data::data_stream))
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

    match cors_layer(cors) {
        Some(layer) => app.layer(layer),
        None => app,
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

#[cfg(test)]
mod tests {
    use axum::body::Body;
    use axum::http::{header, Request, StatusCode};
    use tower::ServiceExt;

    use super::*;

    /// A stateless router with the same CORS layer the real router gets,
    /// so origin handling is testable without an `AppState` (which needs
    /// a live network client).
    fn test_app(mode: &CorsMode) -> Router {
        let app = Router::new().route("/probe", get(|| async { "ok" }));
        match cors_layer(mode) {
            Some(layer) => app.layer(layer),
            None => app,
        }
    }

    async fn allow_origin_for(mode: &CorsMode, origin: &str) -> Option<String> {
        let preflight = Request::builder()
            .method(Method::OPTIONS)
            .uri("/probe")
            .header(header::ORIGIN, origin)
            .header(header::ACCESS_CONTROL_REQUEST_METHOD, "GET")
            .body(Body::empty())
            .unwrap();
        let resp = test_app(mode).oneshot(preflight).await.unwrap();
        resp.headers()
            .get(header::ACCESS_CONTROL_ALLOW_ORIGIN)
            .map(|v| v.to_str().unwrap().to_owned())
    }

    const WEB: &str = "http://127.0.0.1:8000";
    const EXT: &str = "moz-extension://c0ffee00-1234-5678-9abc-def012345678";

    #[tokio::test]
    async fn disabled_sets_no_cors_headers() {
        assert_eq!(allow_origin_for(&CorsMode::Disabled, WEB).await, None);
    }

    #[tokio::test]
    async fn extensions_mode_allows_extension_origins_only() {
        let mode = CorsMode::Extensions;
        assert_eq!(allow_origin_for(&mode, EXT).await.as_deref(), Some(EXT));
        assert_eq!(
            allow_origin_for(&mode, "chrome-extension://abcdefghijklmnop")
                .await
                .as_deref(),
            Some("chrome-extension://abcdefghijklmnop"),
        );
        assert_eq!(allow_origin_for(&mode, WEB).await, None);
    }

    #[tokio::test]
    async fn allowlist_echoes_listed_origin_and_keeps_extensions() {
        let mode = CorsMode::AllowList(vec![WEB.to_owned()]);
        assert_eq!(allow_origin_for(&mode, WEB).await.as_deref(), Some(WEB));
        assert_eq!(allow_origin_for(&mode, EXT).await.as_deref(), Some(EXT));
        assert_eq!(allow_origin_for(&mode, "http://evil.example").await, None);
        // Not the daemon's own origin (the old bug), and exact match only.
        assert_eq!(allow_origin_for(&mode, "http://127.0.0.1:8082").await, None);
    }

    #[tokio::test]
    async fn allow_any_sends_wildcard() {
        assert_eq!(
            allow_origin_for(&CorsMode::AllowAny, WEB).await.as_deref(),
            Some("*"),
        );
    }

    #[tokio::test]
    async fn actual_request_carries_cors_header_too() {
        let req = Request::builder()
            .uri("/probe")
            .header(header::ORIGIN, WEB)
            .body(Body::empty())
            .unwrap();
        let resp = test_app(&CorsMode::AllowList(vec![WEB.to_owned()]))
            .oneshot(req)
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(
            resp.headers()
                .get(header::ACCESS_CONTROL_ALLOW_ORIGIN)
                .map(|v| v.to_str().unwrap()),
            Some(WEB),
        );
    }
}
