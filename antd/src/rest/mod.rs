use std::sync::Arc;

use axum::extract::State;
use axum::routing::{get, head, post, put};
use axum::{Json, Router};
use tower_http::cors::CorsLayer;

use crate::state::AppState;
use crate::types::HealthResponse;

pub mod chunks;
pub mod data;
pub mod events;
pub mod files;
pub mod graph;
pub mod pointers;
pub mod registers;
pub mod scratchpads;
pub mod vaults;

pub fn router(state: Arc<AppState>, enable_cors: bool) -> Router {
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
        // Pointers
        .route("/v1/pointers/{addr}", get(pointers::pointer_get))
        .route("/v1/pointers/{addr}", head(pointers::pointer_check_existence))
        .route("/v1/pointers", post(pointers::pointer_create))
        .route("/v1/pointers/{addr}", put(pointers::pointer_update))
        .route("/v1/pointers/cost", post(pointers::pointer_cost))
        // Scratchpads
        .route("/v1/scratchpads/{addr}", get(scratchpads::scratchpad_get))
        .route("/v1/scratchpads/{addr}", head(scratchpads::scratchpad_check_existence))
        .route("/v1/scratchpads", post(scratchpads::scratchpad_create))
        .route("/v1/scratchpads/{addr}", put(scratchpads::scratchpad_update))
        .route("/v1/scratchpads/cost", post(scratchpads::scratchpad_cost))
        // Graph
        .route("/v1/graph/{addr}", get(graph::graph_entry_get))
        .route("/v1/graph/{addr}", head(graph::graph_entry_check_existence))
        .route("/v1/graph", post(graph::graph_entry_put))
        .route("/v1/graph/cost", post(graph::graph_entry_cost))
        // Registers
        .route("/v1/registers/{addr}", get(registers::register_get))
        .route("/v1/registers", post(registers::register_create))
        .route("/v1/registers/{addr}", put(registers::register_update))
        .route("/v1/registers/cost", post(registers::register_cost))
        // Vaults
        .route("/v1/vaults", get(vaults::vault_get))
        .route("/v1/vaults", post(vaults::vault_put))
        .route("/v1/vaults/cost", post(vaults::vault_cost))
        // Files
        .route("/v1/files/upload/public", post(files::file_upload_public))
        .route("/v1/files/download/public", post(files::file_download_public))
        .route("/v1/dirs/upload/public", post(files::dir_upload_public))
        .route("/v1/dirs/download/public", post(files::dir_download_public))
        .route("/v1/archives/public/{addr}", get(files::archive_get_public))
        .route("/v1/archives/public", post(files::archive_put_public))
        // Cost
        .route("/v1/cost/file", post(files::file_cost))
        .with_state(state);

    if enable_cors {
        app.layer(CorsLayer::permissive())
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
