use std::sync::Arc;

use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::Response;
use axum::Json;
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use bytes::Bytes;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

pub async fn data_put_public(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataPutRequest>,
) -> Result<Json<DataPutPublicResponse>, AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::ServiceUnavailable(
            "wallet not configured — set AUTONOMI_WALLET_KEY".into(),
        ));
    }

    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let mode = parse_payment_mode(req.payment_mode.as_deref()).map_err(AntdError::BadRequest)?;

    let client = state.client.clone();
    let (address, chunks_stored, payment_mode_used) = tokio::spawn(async move {
        let result = client
            .data_upload_with_mode(Bytes::from(data), mode)
            .await
            .map_err(AntdError::from_core)?;
        let address = client
            .data_map_store(&result.data_map)
            .await
            .map_err(AntdError::from_core)?;
        Ok::<_, AntdError>((address, result.chunks_stored, result.payment_mode_used))
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(DataPutPublicResponse {
        address: hex::encode(address),
        chunks_stored,
        payment_mode_used: format_payment_mode(payment_mode_used),
    }))
}

pub async fn data_get_public(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<DataGetResponse>, AntdError> {
    if addr.len() != 64 {
        return Err(AntdError::BadRequest(
            "address must be exactly 64 hex characters".into(),
        ));
    }
    let address_bytes = hex::decode(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex address: {e}")))?;
    let address: [u8; 32] = address_bytes
        .try_into()
        .map_err(|_| AntdError::BadRequest("address must be 32 bytes".into()))?;

    let client = state.client.clone();
    let content = tokio::spawn(async move {
        let data_map = client
            .data_map_fetch(&address)
            .await
            .map_err(AntdError::from_core)?;
        client
            .data_download(&data_map)
            .await
            .map_err(AntdError::from_core)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(DataGetResponse {
        data: BASE64.encode(&content),
    }))
}

pub async fn data_put(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataPutRequest>,
) -> Result<Json<DataPutResponse>, AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::ServiceUnavailable(
            "wallet not configured — set AUTONOMI_WALLET_KEY".into(),
        ));
    }

    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let mode = parse_payment_mode(req.payment_mode.as_deref()).map_err(AntdError::BadRequest)?;

    let client = state.client.clone();
    let (data_map_hex, chunks_stored, payment_mode_used) = tokio::spawn(async move {
        let result = client
            .data_upload_with_mode(Bytes::from(data), mode)
            .await
            .map_err(AntdError::from_core)?;
        let data_map_bytes = rmp_serde::to_vec(&result.data_map)
            .map_err(|e| AntdError::Internal(format!("failed to serialize data map: {e}")))?;
        Ok::<_, AntdError>((
            hex::encode(data_map_bytes),
            result.chunks_stored,
            result.payment_mode_used,
        ))
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(DataPutResponse {
        data_map: data_map_hex,
        chunks_stored,
        payment_mode_used: format_payment_mode(payment_mode_used),
    }))
}

pub async fn data_get(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataGetRequest>,
) -> Result<Json<DataGetResponse>, AntdError> {
    let data_map_bytes = hex::decode(&req.data_map)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex data_map: {e}")))?;

    // Reject oversized data maps before deserialization (10 MB limit)
    const MAX_DATA_MAP_SIZE: usize = 10 * 1024 * 1024;
    if data_map_bytes.len() > MAX_DATA_MAP_SIZE {
        return Err(AntdError::BadRequest(format!(
            "data map too large: {} bytes exceeds {} byte limit",
            data_map_bytes.len(),
            MAX_DATA_MAP_SIZE,
        )));
    }

    let data_map: ant_core::data::DataMap = rmp_serde::from_slice(&data_map_bytes)
        .map_err(|e| AntdError::BadRequest(format!("invalid data map: {e}")))?;

    let client = state.client.clone();
    let content = tokio::spawn(async move {
        client
            .data_download(&data_map)
            .await
            .map_err(AntdError::from_core)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(DataGetResponse {
        data: BASE64.encode(&content),
    }))
}

pub async fn data_cost(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DataCostRequest>,
) -> Result<Json<CostResponse>, AntdError> {
    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let mode = parse_payment_mode(req.payment_mode.as_deref()).map_err(AntdError::BadRequest)?;

    // estimate_upload_cost takes a path; stage the bytes in a temp file.
    // Samples up to 5 chunk addresses instead of quoting every chunk — see
    // ant-client PR #44.
    let tmp = std::env::temp_dir().join(format!(
        "antd_cost_{}_{}.bin",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    ));
    tokio::fs::write(&tmp, &data)
        .await
        .map_err(|e| AntdError::Internal(format!("failed to stage tempfile: {e}")))?;

    let client = state.client.clone();
    let tmp_for_task = tmp.clone();
    let estimate =
        tokio::spawn(async move { client.estimate_upload_cost(&tmp_for_task, mode, None).await })
            .await
            .map_err(|e| AntdError::Internal(format!("task failed: {e}")))?;

    let _ = tokio::fs::remove_file(&tmp).await;
    let estimate = estimate.map_err(AntdError::from_core)?;

    Ok(Json(CostResponse {
        cost: estimate.storage_cost_atto,
        file_size: estimate.file_size,
        chunk_count: estimate.chunk_count,
        estimated_gas_cost_wei: estimate.estimated_gas_cost_wei,
        payment_mode: format_payment_mode(estimate.payment_mode),
    }))
}

/// The NDJSON progress media type. A request `Accept`ing this opts into the
/// interleaved progress+data framing (see [`stream_response_ndjson`]); any other
/// Accept value gets the default raw octet-stream body.
const NDJSON_CONTENT_TYPE: &str = "application/x-ndjson";

/// Whether the caller opted into NDJSON progress framing via the `Accept`
/// header. We do a substring match rather than a strict media-type parse: the
/// header is frequently a comma list (`application/x-ndjson, */*`) and we only
/// need to know the caller will accept our frames.
fn wants_ndjson(headers: &HeaderMap) -> bool {
    headers
        .get(header::ACCEPT)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|accept| accept.contains(NDJSON_CONTENT_TYPE))
}

/// Render an ant-core `DownloadEvent` as the NDJSON `progress` frame body.
/// Mirrors the gRPC `DownloadProgress` mapping (`grpc/service.rs`): chunk
/// counts, `total` 0 when not yet known, `phase` distinguishing resolution
/// from the main fetch.
fn download_event_to_json(ev: ant_core::data::DownloadEvent) -> serde_json::Value {
    use ant_core::data::DownloadEvent::*;
    let (phase, fetched, total) = match ev {
        ResolvingDataMap { total_map_chunks } => ("resolving_map", 0u64, total_map_chunks as u64),
        MapChunkFetched { fetched } => ("resolving_map", fetched as u64, 0),
        DataMapResolved { total_chunks } => ("resolved", 0, total_chunks as u64),
        ChunksFetched { fetched, total } => ("fetching", fetched as u64, total as u64),
    };
    serde_json::json!({ "type": "progress", "phase": phase, "fetched": fetched, "total": total })
}

/// One NDJSON record: a compact JSON line terminated by `\n`.
fn ndjson_line(value: serde_json::Value) -> Bytes {
    let mut s = value.to_string();
    s.push('\n');
    Bytes::from(s)
}

/// Build the default raw streaming response: decrypt `data_map` one batch at a
/// time and forward the plaintext bytes. `Content-Length` is set from the
/// DataMap's known original size, so a client detects a failed download as a
/// short read (chunked transfer can't signal an error after the `200` headers
/// are sent). Shared by the private (`data_stream`) and public
/// (`data_stream_public`) handlers — `data_stream` is the primitive,
/// `data_stream_public` wraps it.
fn stream_response(
    client: Arc<ant_core::data::Client>,
    data_map: ant_core::data::DataMap,
) -> Response {
    let content_length = data_map.original_file_size();
    let (tx, rx) =
        tokio::sync::mpsc::channel::<std::result::Result<Bytes, ant_core::data::Error>>(16);

    // file_download_to_sender returns a terminal error rather than sending it
    // into the sink, so push it via a cloned handle after the chunks it already
    // sent. The body then ends short of Content-Length — the failure signal.
    let err_tx = tx.clone();
    tokio::spawn(async move {
        if let Err(e) = client.file_download_to_sender(&data_map, tx, None).await {
            let _ = err_tx.send(Err(e)).await;
        }
    });

    // ant_core::data::Error is a std::error::Error, so the byte channel feeds
    // Body::from_stream directly — no per-chunk re-wrapping needed.
    let body = Body::from_stream(tokio_stream::wrappers::ReceiverStream::new(rx));
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/octet-stream")
        .header(header::CONTENT_LENGTH, content_length.to_string())
        .body(body)
        .expect("static content-type + numeric content-length are always valid")
}

/// Build the opt-in NDJSON streaming response: interleave fetch-progress frames
/// with the data frames so a consumer can drive a *determinate* progress bar
/// (the raw path's byte delivery is lumpy — often the whole file in one batch —
/// so received-bytes alone jumps 0→100%; the per-chunk progress frames are what
/// actually advance). Frame shapes, one JSON object per line:
///   `{"type":"meta","total_size":N}`            — emitted first; byte denominator
///   `{"type":"progress","phase":..,"fetched":N,"total":M}` — chunk numerator
///   `{"type":"data","chunk":"<base64>"}`         — a decrypted plaintext batch
///   `{"type":"error","message":".."}`            — terminal failure (then end)
/// Unlike the raw path, NDJSON *can* signal a mid-stream error explicitly rather
/// than relying on a short read, so there is no `Content-Length` here.
fn stream_response_ndjson(
    client: Arc<ant_core::data::Client>,
    data_map: ant_core::data::DataMap,
) -> Response {
    let total_size = data_map.original_file_size();

    let (byte_tx, mut byte_rx) =
        tokio::sync::mpsc::channel::<std::result::Result<Bytes, ant_core::data::Error>>(16);
    let (prog_tx, mut prog_rx) = tokio::sync::mpsc::channel::<ant_core::data::DownloadEvent>(64);
    // The merged line stream feeding the body. Items are always Ok — a download
    // error is encoded as an `{"type":"error"}` line, not a stream error.
    let (line_tx, line_rx) =
        tokio::sync::mpsc::channel::<std::result::Result<Bytes, std::convert::Infallible>>(16);

    // Emit the meta line first (buffer is empty, so this never blocks/fails)
    // before any forwarder can race a progress frame ahead of it.
    let _ = line_tx.try_send(Ok(ndjson_line(
        serde_json::json!({ "type": "meta", "total_size": total_size }),
    )));

    // Producer: drive the download with a progress sender attached.
    let err_tx = byte_tx.clone();
    tokio::spawn(async move {
        if let Err(e) = client
            .file_download_to_sender(&data_map, byte_tx, Some(prog_tx))
            .await
        {
            let _ = err_tx.send(Err(e)).await;
        }
    });

    // Data forwarder: plaintext batch -> base64 `data` line; terminal error ->
    // `error` line.
    let data_lines = line_tx.clone();
    tokio::spawn(async move {
        while let Some(item) = byte_rx.recv().await {
            let line = match item {
                Ok(bytes) => {
                    serde_json::json!({ "type": "data", "chunk": BASE64.encode(&bytes) })
                }
                Err(e) => serde_json::json!({ "type": "error", "message": e.to_string() }),
            };
            if data_lines.send(Ok(ndjson_line(line))).await.is_err() {
                break;
            }
        }
    });

    // Progress forwarder: DownloadEvent -> `progress` line, interleaved with
    // data lines by arrival order.
    let prog_lines = line_tx.clone();
    tokio::spawn(async move {
        while let Some(ev) = prog_rx.recv().await {
            if prog_lines
                .send(Ok(ndjson_line(download_event_to_json(ev))))
                .await
                .is_err()
            {
                break;
            }
        }
    });
    // Drop the original so the body ends once both forwarders finish.
    drop(line_tx);

    let body = Body::from_stream(tokio_stream::wrappers::ReceiverStream::new(line_rx));
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, NDJSON_CONTENT_TYPE)
        .body(body)
        .expect("static content-type is always valid")
}

/// `POST /v1/data/stream` — private streaming download from a caller-held
/// DataMap (the primitive). Mirrors `data_get` but streams the plaintext
/// instead of buffering it into a base64 JSON body. POST (not GET) because the
/// hex DataMap can be many KB.
pub async fn data_stream(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(req): Json<DataGetRequest>,
) -> Result<Response, AntdError> {
    let data_map_bytes = hex::decode(&req.data_map)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex data_map: {e}")))?;

    // Reject oversized data maps before deserialization (10 MB limit) — mirrors
    // the gRPC `stream` / `get` handlers.
    const MAX_DATA_MAP_SIZE: usize = 10 * 1024 * 1024;
    if data_map_bytes.len() > MAX_DATA_MAP_SIZE {
        return Err(AntdError::BadRequest(format!(
            "data map too large: {} bytes exceeds {} byte limit",
            data_map_bytes.len(),
            MAX_DATA_MAP_SIZE,
        )));
    }

    let data_map: ant_core::data::DataMap = rmp_serde::from_slice(&data_map_bytes)
        .map_err(|e| AntdError::BadRequest(format!("invalid data map: {e}")))?;

    Ok(if wants_ndjson(&headers) {
        stream_response_ndjson(state.client.clone(), data_map)
    } else {
        stream_response(state.client.clone(), data_map)
    })
}

/// `GET /v1/data/public/{addr}/stream` — public streaming download. Resolves
/// the address to a DataMap, then streams from it (wraps the private
/// primitive). A fetch failure surfaces as a normal error response before the
/// stream opens.
pub async fn data_stream_public(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(addr): Path<String>,
) -> Result<Response, AntdError> {
    if addr.len() != 64 {
        return Err(AntdError::BadRequest(
            "address must be exactly 64 hex characters".into(),
        ));
    }
    let address_bytes = hex::decode(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex address: {e}")))?;
    let address: [u8; 32] = address_bytes
        .try_into()
        .map_err(|_| AntdError::BadRequest("address must be 32 bytes".into()))?;

    let data_map = state
        .client
        .data_map_fetch(&address)
        .await
        .map_err(AntdError::from_core)?;

    Ok(if wants_ndjson(&headers) {
        stream_response_ndjson(state.client.clone(), data_map)
    } else {
        stream_response(state.client.clone(), data_map)
    })
}
