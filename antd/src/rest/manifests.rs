//! `POST /v1/manifests/build` and `POST /v1/manifests/decode`: ADR-0006
//! file manifests for daemon callers (V2-1570). Stateless; the work is in
//! [`crate::manifests`], shared with gRPC.

use std::sync::Arc;

use axum::extract::State;
use axum::Json;
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;

use crate::error::AntdError;
use crate::manifests::{self, BuildInput, DecodeInput, EntryInfo};
use crate::state::AppState;
use crate::types::{
    ManifestBuildRequest, ManifestBuildResponse, ManifestDecodeRequest, ManifestDecodeResponse,
    ManifestEntryInfo,
};

pub async fn manifest_build(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ManifestBuildRequest>,
) -> Result<Json<ManifestBuildResponse>, AntdError> {
    let torrent = manifests::parse_torrent_hashes(&req.torrent_info_hashes)?;
    let entries = manifests::parse_entries(req.entries.into_iter().map(|e| manifests::RawEntry {
        path: e.path,
        size: e.size,
        sha256: e.sha256,
        data_map: e.data_map,
        address: e.address,
    }))?;
    let out = manifests::build(
        &*state.client,
        BuildInput {
            name: req.name.filter(|n| !n.is_empty()),
            torrent,
            entries,
            embed_roots: req.embed_roots,
        },
    )
    .await?;
    Ok(Json(ManifestBuildResponse {
        manifest: BASE64.encode(&out.bytes),
        link: out.link,
        entries: out
            .entries
            .into_iter()
            .map(|info| entry_json(info, None, None))
            .collect::<Result<_, _>>()?,
    }))
}

pub async fn manifest_decode(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ManifestDecodeRequest>,
) -> Result<Json<ManifestDecodeResponse>, AntdError> {
    let input = match (
        req.manifest.filter(|m| !m.is_empty()),
        req.link.filter(|l| !l.is_empty()),
    ) {
        (Some(b64), None) => DecodeInput::Bytes(
            BASE64
                .decode(b64.trim())
                .map_err(|e| AntdError::BadRequest(format!("invalid base64 manifest: {e}")))?,
        ),
        (None, Some(link)) => DecodeInput::Link(link),
        (Some(_), Some(_)) => {
            return Err(AntdError::BadRequest(
                "give manifest or link, not both".into(),
            ))
        }
        (None, None) => {
            return Err(AntdError::BadRequest(
                "needs a manifest (base64 .ant bytes) or a link".into(),
            ))
        }
    };
    let out = manifests::decode(&*state.client, input, req.resolve).await?;
    let (v1, v2) = match &out.torrent {
        Some(t) => (
            t.info_hash_v1.map(hex::encode),
            t.info_hash_v2.map(hex::encode),
        ),
        None => (None, None),
    };
    Ok(Json(ManifestDecodeResponse {
        source: out.from.as_str().to_string(),
        name: out.name,
        torrent_info_hash_v1: v1,
        torrent_info_hash_v2: v2,
        entries: out
            .entries
            .into_iter()
            .map(|e| entry_json(e.info, e.exact_size, e.error))
            .collect::<Result<_, _>>()?,
    }))
}

fn entry_json(
    info: EntryInfo,
    exact_size: Option<u64>,
    error: Option<String>,
) -> Result<ManifestEntryInfo, AntdError> {
    Ok(ManifestEntryInfo {
        effective_name: info.effective_name,
        path: info.path,
        size: info.size,
        sha256: info.sha256.map(hex::encode),
        kind: info.kind.to_string(),
        content_address: hex::encode(info.content_address),
        data_map: info
            .data_map
            .as_ref()
            .map(manifests::data_map_hex)
            .transpose()?,
        exact_size: exact_size.or(info.known_size),
        error,
    })
}
