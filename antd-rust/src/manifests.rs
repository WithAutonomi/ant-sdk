//! Manifests (ADR-0006): `.ant` files and `ant://` links that describe a set
//! of files, each with an optional path and size and either an embedded
//! DataMap or a public DataMap address.
//!
//! The daemon builds and decodes them through ant-core, so callers never
//! re-implement the format. Nothing is uploaded or paid for. The calls can
//! still read from the network (the embedding policy on a build, `resolve` on
//! a decode), so they can time out, and retrying them is safe.
//!
//! Both clients take and return the `.ant` bytes as raw bytes. REST carries
//! them as base64 in JSON and gRPC as `bytes`; neither form reaches the
//! caller.
//!
//! Requires the antd release after 0.15.0.

use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::client::Client;
use crate::errors::AntdError;
use crate::grpc_client::proto::antd::v1 as pb;
use crate::grpc_client::GrpcClient;

/// Response ceiling, in bytes, of the gRPC client's `ManifestService` stub
/// (256 MiB, as antd-go): a manifest can be 64 MiB, and a decode response
/// carries its embedded DataMaps in hex, about twice their size. The stub
/// takes the larger of this and the ceiling the client was connected with,
/// so [`GrpcClient::connect_with_max_message_size`] can raise it but never
/// lowers it below what a manifest needs.
pub(crate) const MANIFEST_MAX_RECV_MESSAGE_BYTES: usize = 256 * 1024 * 1024;

/// Request ceiling, in bytes, of the gRPC client's `ManifestService` stub:
/// the daemon's own limit on a manifest request (100 MiB, its REST body
/// limit), so an oversized decode fails before it is sent.
pub(crate) const MANIFEST_MAX_SEND_MESSAGE_BYTES: usize = 100 * 1024 * 1024;

/// One file for [`Client::build_manifest`]. Set exactly one of `data_map` or
/// `address`: [`ManifestEntryInput::embedded`] and
/// [`ManifestEntryInput::public`] build one that does. An empty string counts
/// as unset, as it does on the wire.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ManifestEntryInput {
    /// The relative path the entry extracts under, subject to the portable
    /// path rules. `None`: it extracts under its content address.
    pub path: Option<String>,
    /// The plaintext size to record, as given (the creator's claim). `None`:
    /// none is recorded; readers take the exact size from an embedded root
    /// DataMap.
    pub size: Option<u64>,
    /// A hex DataMap, as the upload methods return it. The entry embeds it:
    /// the manifest is the key to the file.
    pub data_map: Option<String>,
    /// A public file's DataMap address (hex, 32 bytes).
    pub address: Option<String>,
}

impl ManifestEntryInput {
    /// An entry that embeds `data_map` (hex, as the upload methods return it).
    pub fn embedded(data_map: impl Into<String>) -> Self {
        Self {
            data_map: Some(data_map.into()),
            ..Self::default()
        }
    }

    /// An entry for a public file, by its DataMap address (hex, 32 bytes).
    pub fn public(address: impl Into<String>) -> Self {
        Self {
            address: Some(address.into()),
            ..Self::default()
        }
    }

    /// Sets the relative path the entry extracts under.
    pub fn with_path(mut self, path: impl Into<String>) -> Self {
        self.path = Some(path.into());
        self
    }

    /// Sets the plaintext size to record.
    pub fn with_size(mut self, size: u64) -> Self {
        self.size = Some(size);
        self
    }
}

/// The optional parts of a build. The default embeds roots, as the daemon
/// does when the option is unset.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BuildManifestOptions {
    /// A suggested root directory name (one portable path component).
    pub name: Option<String>,
    /// BitTorrent info hashes of the same files: hex, 40 characters for v1
    /// and/or 64 for v2.
    pub torrent_info_hashes: Vec<String>,
    /// Embed shrunk DataMaps exactly as given (`embed_roots: false` on the
    /// wire). By default (`false`) the daemon resolves each one's root,
    /// fetching its wrapper records, and embeds the root when it is at most
    /// 64 KiB, so recipients skip that fetch (ADR-0006's policy).
    pub keep_shrunk_data_maps: bool,
}

/// What a manifest says about one entry.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ManifestEntryInfo {
    /// `path`, or the content address in hex when there is none.
    pub effective_name: String,
    pub path: Option<String>,
    /// The size recorded in the manifest: the creator's claim. `None` when
    /// none was recorded (never `Some(0)` for "unset").
    pub size: Option<u64>,
    /// `"embedded"` or `"public"`.
    pub kind: String,
    /// Hex. The file's public DataMap address, whether or not it was ever made
    /// public; the same for private and public uploads of one file.
    pub content_address: String,
    /// The embedded DataMap, in the hex form the download methods accept.
    /// Decode only; `None` for public entries.
    pub data_map: Option<String>,
    /// The exact plaintext size: from an embedded root DataMap, or after a
    /// resolving decode. `None` when neither gave one.
    pub exact_size: Option<u64>,
    /// Why a resolving decode failed for this entry. One entry's failure is
    /// reported here, not as a failed call.
    pub error: Option<String>,
}

/// The result of [`Client::build_manifest`].
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BuiltManifest {
    /// The `.ant` bytes.
    pub manifest: Vec<u8>,
    /// The `ant://manifest/` link, only when it fits the recommended 1,500
    /// bytes.
    pub link: Option<String>,
    /// In encoded order (sorted by effective name).
    pub entries: Vec<ManifestEntryInfo>,
}

/// The result of [`Client::decode_manifest`] and
/// [`Client::decode_manifest_link`].
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DecodedManifest {
    /// `"manifest"`, or `"file_link"` for a file link or bare address
    /// (reported as one public entry with no path).
    pub source: String,
    pub name: Option<String>,
    /// Hex.
    pub torrent_info_hash_v1: Option<String>,
    /// Hex.
    pub torrent_info_hash_v2: Option<String>,
    pub entries: Vec<ManifestEntryInfo>,
}

/// An optional string the wire may also leave empty: both read as unset.
fn given(s: &Option<String>) -> Option<&str> {
    s.as_deref().filter(|s| !s.is_empty())
}

fn non_empty(s: Option<String>) -> Option<String> {
    s.filter(|s| !s.is_empty())
}

/// Rejects, before anything is sent, an entry that sets both or neither of
/// `data_map` and `address`. The message names the entry as the daemon does.
fn check_entries(entries: &[ManifestEntryInput]) -> Result<(), AntdError> {
    for (i, e) in entries.iter().enumerate() {
        if given(&e.data_map).is_some() == given(&e.address).is_some() {
            return Err(AntdError::BadRequest(format!(
                "entries[{i}]: set exactly one of data_map or address"
            )));
        }
    }
    Ok(())
}

// --- REST wire forms ---

#[derive(Serialize)]
struct WireBuildRequest<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    name: Option<&'a str>,
    #[serde(skip_serializing_if = "<[String]>::is_empty")]
    torrent_info_hashes: &'a [String],
    embed_roots: bool,
    entries: Vec<WireEntryInput<'a>>,
}

#[derive(Serialize)]
struct WireEntryInput<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    path: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    size: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    data_map: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    address: Option<&'a str>,
}

#[derive(Deserialize)]
struct WireBuildResponse {
    /// The `.ant` bytes, base64.
    #[serde(default)]
    manifest: String,
    #[serde(default)]
    link: Option<String>,
    #[serde(default)]
    entries: Vec<WireEntryInfo>,
}

#[derive(Deserialize)]
struct WireDecodeResponse {
    #[serde(default)]
    source: String,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    torrent_info_hash_v1: Option<String>,
    #[serde(default)]
    torrent_info_hash_v2: Option<String>,
    #[serde(default)]
    entries: Vec<WireEntryInfo>,
}

/// Unset fields are omitted (or `null`) and read as `None`; a size that is
/// present but not a `u64` is a JSON error, not a zero.
#[derive(Deserialize)]
struct WireEntryInfo {
    #[serde(default)]
    effective_name: String,
    #[serde(default)]
    path: Option<String>,
    #[serde(default)]
    size: Option<u64>,
    #[serde(default)]
    kind: String,
    #[serde(default)]
    content_address: String,
    #[serde(default)]
    data_map: Option<String>,
    #[serde(default)]
    exact_size: Option<u64>,
    #[serde(default)]
    error: Option<String>,
}

impl From<WireEntryInfo> for ManifestEntryInfo {
    fn from(e: WireEntryInfo) -> Self {
        Self {
            effective_name: e.effective_name,
            path: non_empty(e.path),
            size: e.size,
            kind: e.kind,
            content_address: e.content_address,
            data_map: non_empty(e.data_map),
            exact_size: e.exact_size,
            error: non_empty(e.error),
        }
    }
}

fn response_body<T: serde::de::DeserializeOwned>(
    method: &str,
    body: Option<Value>,
) -> Result<T, AntdError> {
    let body = body.ok_or_else(|| AntdError::Internal(format!("{method}: empty response")))?;
    Ok(serde_json::from_value(body)?)
}

impl Client {
    // --- Manifests ---
    //
    // See the `manifests` module: nothing is uploaded or paid for, and the
    // calls are safe to retry.

    /// Builds a `.ant` manifest from DataMaps and public addresses already in
    /// hand (`POST /v1/manifests/build`), with the default
    /// [`BuildManifestOptions`]: roots are embedded.
    ///
    /// An entry that sets both or neither of `data_map` and `address` is
    /// [`AntdError::BadRequest`] before anything is sent. The daemon checks
    /// the rest (hex, paths, sizes) and reports every invalid entry, as
    /// `entries[i]: ...`, in one [`AntdError::BadRequest`].
    ///
    /// Requires the antd release after 0.15.0.
    pub async fn build_manifest(
        &self,
        entries: &[ManifestEntryInput],
    ) -> Result<BuiltManifest, AntdError> {
        self.build_manifest_with_options(entries, &BuildManifestOptions::default())
            .await
    }

    /// [`build_manifest`](Self::build_manifest) with explicit
    /// [`BuildManifestOptions`].
    pub async fn build_manifest_with_options(
        &self,
        entries: &[ManifestEntryInput],
        opts: &BuildManifestOptions,
    ) -> Result<BuiltManifest, AntdError> {
        check_entries(entries)?;
        let req = WireBuildRequest {
            name: given(&opts.name),
            torrent_info_hashes: &opts.torrent_info_hashes,
            embed_roots: !opts.keep_shrunk_data_maps,
            entries: entries
                .iter()
                .map(|e| WireEntryInput {
                    path: given(&e.path),
                    size: e.size,
                    data_map: given(&e.data_map),
                    address: given(&e.address),
                })
                .collect(),
        };
        let (j, _) = self
            .do_json(
                reqwest::Method::POST,
                "/v1/manifests/build",
                Some(serde_json::to_value(&req)?),
            )
            .await?;
        let resp: WireBuildResponse = response_body("build_manifest", j)?;
        let manifest = BASE64.decode(resp.manifest.trim()).map_err(|e| {
            AntdError::Internal(format!("build_manifest: manifest is not valid base64: {e}"))
        })?;
        Ok(BuiltManifest {
            manifest,
            link: non_empty(resp.link),
            entries: resp.entries.into_iter().map(Into::into).collect(),
        })
    }

    /// Decodes `.ant` bytes (`POST /v1/manifests/decode`).
    ///
    /// With `resolve`, the daemon fetches each entry's DataMap (and wrapper
    /// records) to report its `exact_size` and confirm the DataMap is on the
    /// network. Content chunks are not fetched, and one entry's failure is
    /// reported in its `error`, not as a failed call. Bytes that are not a
    /// manifest are [`AntdError::BadRequest`]; empty bytes are refused before
    /// anything is sent.
    ///
    /// Requires the antd release after 0.15.0.
    pub async fn decode_manifest(
        &self,
        manifest: &[u8],
        resolve: bool,
    ) -> Result<DecodedManifest, AntdError> {
        if manifest.is_empty() {
            return Err(AntdError::BadRequest(
                "decode_manifest: manifest is empty".into(),
            ));
        }
        self.decode_manifest_request(json!({
            "manifest": BASE64.encode(manifest),
            "resolve": resolve,
        }))
        .await
    }

    /// Decodes an `ant://` manifest link, a file link or a bare 64-hex
    /// address (`POST /v1/manifests/decode`). A file link or address reads as
    /// one public entry with no path, with `source` `"file_link"`. See
    /// [`decode_manifest`](Self::decode_manifest) for `resolve`.
    ///
    /// Requires the antd release after 0.15.0.
    pub async fn decode_manifest_link(
        &self,
        link: &str,
        resolve: bool,
    ) -> Result<DecodedManifest, AntdError> {
        if link.is_empty() {
            return Err(AntdError::BadRequest(
                "decode_manifest_link: link is empty".into(),
            ));
        }
        self.decode_manifest_request(json!({ "link": link, "resolve": resolve }))
            .await
    }

    async fn decode_manifest_request(&self, body: Value) -> Result<DecodedManifest, AntdError> {
        let (j, _) = self
            .do_json(reqwest::Method::POST, "/v1/manifests/decode", Some(body))
            .await?;
        let resp: WireDecodeResponse = response_body("decode_manifest", j)?;
        Ok(DecodedManifest {
            source: resp.source,
            name: non_empty(resp.name),
            torrent_info_hash_v1: non_empty(resp.torrent_info_hash_v1),
            torrent_info_hash_v2: non_empty(resp.torrent_info_hash_v2),
            entries: resp.entries.into_iter().map(Into::into).collect(),
        })
    }
}

// --- gRPC ---

/// A manifest call's status as an [`AntdError`]: `INVALID_ARGUMENT` (an
/// invalid entry, path or input, the REST 400) is [`AntdError::BadRequest`]
/// with the daemon's message, as over REST; anything else maps as on every
/// other call.
fn manifest_status_error(status: tonic::Status) -> AntdError {
    match status.code() {
        tonic::Code::InvalidArgument => AntdError::BadRequest(status.message().to_string()),
        _ => AntdError::from(status),
    }
}

fn entry_info_from_pb(e: pb::ManifestEntryInfo) -> ManifestEntryInfo {
    ManifestEntryInfo {
        effective_name: e.effective_name,
        path: non_empty(e.path),
        // proto3 `optional`: presence, not the zero value, says it is set.
        size: e.size,
        kind: e.kind,
        content_address: e.content_address,
        data_map: non_empty(Some(e.data_map)),
        exact_size: e.exact_size,
        error: non_empty(Some(e.error)),
    }
}

impl GrpcClient {
    // --- Manifests ---
    //
    // Mirror the REST methods on [`crate::Client`]; see there for the
    // contract. The ManifestService stub has its own message ceilings (see
    // `MANIFEST_MAX_RECV_MESSAGE_BYTES`), and `INVALID_ARGUMENT` maps to
    // `AntdError::BadRequest` as the REST 400 does.

    /// Builds a `.ant` manifest via `ManifestService.Build`. Mirrors
    /// [`crate::Client::build_manifest`].
    pub async fn build_manifest(
        &self,
        entries: &[ManifestEntryInput],
    ) -> Result<BuiltManifest, AntdError> {
        self.build_manifest_with_options(entries, &BuildManifestOptions::default())
            .await
    }

    /// [`build_manifest`](Self::build_manifest) with explicit
    /// [`BuildManifestOptions`]. Mirrors
    /// [`crate::Client::build_manifest_with_options`].
    pub async fn build_manifest_with_options(
        &self,
        entries: &[ManifestEntryInput],
        opts: &BuildManifestOptions,
    ) -> Result<BuiltManifest, AntdError> {
        use pb::manifest_entry_input::Source;

        check_entries(entries)?;
        let req = pb::BuildManifestRequest {
            name: given(&opts.name).map(str::to_string),
            torrent_info_hashes: opts.torrent_info_hashes.clone(),
            embed_roots: Some(!opts.keep_shrunk_data_maps),
            entries: entries
                .iter()
                .map(|e| pb::ManifestEntryInput {
                    path: given(&e.path).map(str::to_string),
                    size: e.size,
                    source: Some(match (given(&e.data_map), given(&e.address)) {
                        (Some(data_map), _) => Source::DataMap(data_map.to_string()),
                        (None, address) => Source::Address(address.unwrap_or_default().to_string()),
                    }),
                })
                .collect(),
        };
        let resp = self
            .manifests
            .clone()
            .build(req)
            .await
            .map_err(manifest_status_error)?
            .into_inner();
        Ok(BuiltManifest {
            manifest: resp.manifest,
            link: non_empty(Some(resp.link)),
            entries: resp.entries.into_iter().map(entry_info_from_pb).collect(),
        })
    }

    /// Decodes `.ant` bytes via `ManifestService.Decode`. Mirrors
    /// [`crate::Client::decode_manifest`].
    pub async fn decode_manifest(
        &self,
        manifest: &[u8],
        resolve: bool,
    ) -> Result<DecodedManifest, AntdError> {
        if manifest.is_empty() {
            return Err(AntdError::BadRequest(
                "decode_manifest: manifest is empty".into(),
            ));
        }
        self.decode_manifest_request(pb::DecodeManifestRequest {
            input: Some(pb::decode_manifest_request::Input::Manifest(
                manifest.to_vec(),
            )),
            resolve,
        })
        .await
    }

    /// Decodes a manifest link, file link or bare address via
    /// `ManifestService.Decode`. Mirrors
    /// [`crate::Client::decode_manifest_link`].
    pub async fn decode_manifest_link(
        &self,
        link: &str,
        resolve: bool,
    ) -> Result<DecodedManifest, AntdError> {
        if link.is_empty() {
            return Err(AntdError::BadRequest(
                "decode_manifest_link: link is empty".into(),
            ));
        }
        self.decode_manifest_request(pb::DecodeManifestRequest {
            input: Some(pb::decode_manifest_request::Input::Link(link.to_string())),
            resolve,
        })
        .await
    }

    async fn decode_manifest_request(
        &self,
        req: pb::DecodeManifestRequest,
    ) -> Result<DecodedManifest, AntdError> {
        let resp = self
            .manifests
            .clone()
            .decode(req)
            .await
            .map_err(manifest_status_error)?
            .into_inner();
        Ok(DecodedManifest {
            source: resp.source,
            name: non_empty(resp.name),
            torrent_info_hash_v1: non_empty(Some(resp.torrent_info_hash_v1)),
            torrent_info_hash_v2: non_empty(Some(resp.torrent_info_hash_v2)),
            entries: resp.entries.into_iter().map(entry_info_from_pb).collect(),
        })
    }
}
