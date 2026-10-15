//! ADR-0006 file manifests (`.ant` files and `ant://` links) for daemon
//! callers (V2-1570), shared by the REST and gRPC handlers.
//!
//! antd keeps no state here. The format, content addresses, link encoding
//! and portable path rules all come from ant-core's `manifest` module, so
//! nothing below re-implements them; antd only converts between its wire
//! forms (hex DataMaps and addresses) and ant-core's types. The network is
//! touched only to resolve DataMaps: the embedding policy on build, and
//! `resolve` on decode.

use std::future::Future;

use ant_core::data::manifest::path::validate_path;
use ant_core::data::manifest::{
    embedded_len, parse_link, ContentRef, Link, Manifest, ManifestEntry, ManifestError,
    TorrentReference, ADDRESS_LEN, MANIFEST_LINK_RECOMMENDED_MAX_BYTES,
    MAX_EMBEDDED_ROOT_MAP_BYTES, MAX_MANIFEST_ENTRIES, SHA256_LEN,
};
use ant_core::data::{Client, DataMap};
use futures::stream::{self, StreamExt};

use crate::error::AntdError;

/// Largest hex-decoded DataMap accepted per entry, as on the data routes.
const MAX_DATA_MAP_BYTES: usize = 10 * 1024 * 1024;

/// DataMap resolutions in flight at once, on build and on decode.
const RESOLVE_CONCURRENCY: usize = 8;

/// Invalid entries listed in one error message before it is cut short.
const MAX_REPORTED_ENTRY_ERRORS: usize = 20;

/// Entries above which a manifest link cannot fit the recommended length.
/// Every encoded entry costs more than 50 bytes (the smallest, a `Public`
/// entry with no path, is ~59), so past this count the link form is not
/// computed at all: that would shrink every embedded DataMap only to discard
/// the result.
const MAX_LINK_ENTRIES: usize = MANIFEST_LINK_RECOMMENDED_MAX_BYTES / 50;

/// Where one entry's bytes come from, as the caller gave it.
pub enum EntrySource {
    DataMap(DataMap),
    Address([u8; ADDRESS_LEN]),
}

/// One entry of a build request.
pub struct EntryInput {
    pub path: Option<String>,
    pub size: Option<u64>,
    /// SHA-256 of the plaintext to record, as given (the creator's claim).
    pub sha256: Option<[u8; SHA256_LEN]>,
    pub source: EntrySource,
}

/// One build entry as it arrived on the wire, before parsing. Empty strings
/// count as absent: proto3 strings have no presence.
#[derive(Default)]
pub struct RawEntry {
    pub path: Option<String>,
    pub size: Option<u64>,
    /// Hex.
    pub sha256: Option<String>,
    /// Hex, in antd's usual DataMap form.
    pub data_map: Option<String>,
    /// Hex.
    pub address: Option<String>,
}

/// A build request, transport-neutral.
pub struct BuildInput {
    pub name: Option<String>,
    pub torrent: Option<TorrentReference>,
    pub entries: Vec<EntryInput>,
    /// Apply ADR-0006's embedding policy to shrunk DataMaps: resolve the
    /// root and embed it when it is at most `MAX_EMBEDDED_ROOT_MAP_BYTES`
    /// as written. Fetches wrapper records.
    pub embed_roots: bool,
}

/// What a manifest says about one entry, in canonical (encoded) order.
pub struct EntryInfo {
    pub effective_name: String,
    pub path: Option<String>,
    /// The size recorded in the manifest: the creator's claim.
    pub size: Option<u64>,
    /// The SHA-256 recorded in the manifest: the creator's claim.
    pub sha256: Option<[u8; SHA256_LEN]>,
    pub kind: &'static str,
    pub content_address: [u8; ADDRESS_LEN],
    /// Exact plaintext size, known only from an embedded root DataMap.
    pub known_size: Option<u64>,
    /// The embedded DataMap, as embedded (root or shrunk). `None` for
    /// `Public` entries.
    pub data_map: Option<DataMap>,
}

pub struct BuildOutput {
    /// The `.ant` bytes.
    pub bytes: Vec<u8>,
    /// The `ant://manifest/` link, present only when it fits the
    /// recommended `MANIFEST_LINK_RECOMMENDED_MAX_BYTES`.
    pub link: Option<String>,
    pub entries: Vec<EntryInfo>,
}

/// What a decode request was given.
pub enum DecodeInput {
    /// `.ant` bytes.
    Bytes(Vec<u8>),
    /// An `ant://` manifest link, file link, or bare hex address.
    Link(String),
}

/// What the decoded input turned out to be.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DecodedFrom {
    Manifest,
    /// A file link or bare address, reported as a one-entry manifest with a
    /// single `Public` entry and no path.
    FileLink,
}

impl DecodedFrom {
    pub fn as_str(self) -> &'static str {
        match self {
            DecodedFrom::Manifest => "manifest",
            DecodedFrom::FileLink => "file_link",
        }
    }
}

pub struct DecodedEntry {
    pub info: EntryInfo,
    /// Exact plaintext size from the resolved root DataMap (`resolve` only).
    pub exact_size: Option<u64>,
    /// Why resolution failed for this entry (`resolve` only). One entry's
    /// failure never fails the request.
    pub error: Option<String>,
}

pub struct DecodeOutput {
    pub from: DecodedFrom,
    pub name: Option<String>,
    pub torrent: Option<TorrentReference>,
    pub entries: Vec<DecodedEntry>,
}

/// The network operations manifests need, so the build and decode logic can
/// be tested without a live client.
pub trait DataMapResolver: Sync {
    /// Resolve a possibly shrunk DataMap to its root. A root map is returned
    /// unchanged.
    fn resolve_root(
        &self,
        data_map: DataMap,
    ) -> impl Future<Output = Result<DataMap, ant_core::data::Error>> + Send;

    /// Fetch a public file's DataMap by its address.
    fn fetch_public(
        &self,
        address: [u8; ADDRESS_LEN],
    ) -> impl Future<Output = Result<DataMap, ant_core::data::Error>> + Send;
}

impl DataMapResolver for Client {
    async fn resolve_root(&self, data_map: DataMap) -> Result<DataMap, ant_core::data::Error> {
        crate::datamap::resolve_root_data_map(self, data_map).await
    }

    async fn fetch_public(
        &self,
        address: [u8; ADDRESS_LEN],
    ) -> Result<DataMap, ant_core::data::Error> {
        self.data_map_fetch(&address).await
    }
}

/// Parse a hex DataMap in antd's usual wire form (rmp_serde, as the upload
/// routes return it).
pub fn parse_data_map_hex(hex_str: &str) -> Result<DataMap, String> {
    let bytes = hex::decode(hex_str.trim()).map_err(|e| format!("invalid hex data_map: {e}"))?;
    if bytes.len() > MAX_DATA_MAP_BYTES {
        return Err(format!(
            "data map too large: {} bytes exceeds {MAX_DATA_MAP_BYTES} byte limit",
            bytes.len()
        ));
    }
    rmp_serde::from_slice(&bytes).map_err(|e| format!("invalid data_map: {e}"))
}

/// The hex wire form of a DataMap, as the upload routes return it.
pub fn data_map_hex(data_map: &DataMap) -> Result<String, AntdError> {
    rmp_serde::to_vec(data_map)
        .map(hex::encode)
        .map_err(|e| AntdError::Internal(format!("DataMap did not serialize: {e}")))
}

/// Parse a 64-character hex address.
pub fn parse_address_hex(hex_str: &str) -> Result<[u8; ADDRESS_LEN], String> {
    let hex_str = hex_str.trim();
    if hex_str.len() != ADDRESS_LEN * 2 {
        return Err(format!(
            "address must be exactly {} hex characters",
            ADDRESS_LEN * 2
        ));
    }
    let bytes = hex::decode(hex_str).map_err(|e| format!("invalid hex address: {e}"))?;
    bytes
        .try_into()
        .map_err(|_| format!("address must be {ADDRESS_LEN} bytes"))
}

/// Parse a 64-character hex SHA-256.
pub fn parse_sha256_hex(hex_str: &str) -> Result<[u8; SHA256_LEN], String> {
    let bytes = hex::decode(hex_str.trim()).map_err(|e| format!("invalid hex sha256: {e}"))?;
    bytes
        .try_into()
        .map_err(|b: Vec<u8>| format!("sha256 must be {SHA256_LEN} bytes, got {}", b.len()))
}

/// Parse up to two torrent info hashes (v1 and/or v2) into one reference.
pub fn parse_torrent_hashes(hashes: &[String]) -> Result<Option<TorrentReference>, AntdError> {
    if hashes.len() > 2 {
        return Err(AntdError::BadRequest(format!(
            "at most two torrent info hashes (v1 and v2), got {}",
            hashes.len()
        )));
    }
    let mut reference: Option<TorrentReference> = None;
    for hash in hashes {
        let parsed = TorrentReference::parse_hex(hash).map_err(manifest_error)?;
        reference = Some(match reference {
            Some(existing) => existing.merge(parsed).map_err(manifest_error)?,
            None => parsed,
        });
    }
    Ok(reference)
}

/// Turn raw `(path, size, data_map hex, address hex)` entries into
/// [`EntryInput`]s, checking each one's source and path. Every invalid
/// entry is reported, not just the first.
pub fn parse_entries<I>(entries: I) -> Result<Vec<EntryInput>, AntdError>
where
    I: IntoIterator<Item = RawEntry>,
{
    let mut parsed = Vec::new();
    let mut errors = Vec::new();
    for (i, raw) in entries.into_iter().enumerate() {
        let RawEntry {
            path,
            size,
            sha256,
            data_map,
            address,
        } = raw;
        if parsed.len() + errors.len() >= MAX_MANIFEST_ENTRIES {
            return Err(AntdError::BadRequest(format!(
                "more than {MAX_MANIFEST_ENTRIES} entries"
            )));
        }
        // An empty string is "not given": proto3 strings have no presence.
        let path = path.filter(|p| !p.is_empty());
        let data_map = data_map.filter(|d| !d.is_empty());
        let address = address.filter(|a| !a.is_empty());
        let source = match (data_map, address) {
            (Some(dm), None) => parse_data_map_hex(&dm).map(EntrySource::DataMap),
            (None, Some(addr)) => parse_address_hex(&addr).map(EntrySource::Address),
            (Some(_), Some(_)) => Err("give data_map or address, not both".to_string()),
            (None, None) => Err("needs a data_map or an address".to_string()),
        };
        let path_ok = match &path {
            Some(p) => validate_path(p).map_err(|reason| format!("invalid path {p:?}: {reason}")),
            None => Ok(()),
        };
        let sha256 = sha256
            .filter(|h| !h.is_empty())
            .map(|h| parse_sha256_hex(&h))
            .transpose();
        match (source, path_ok, sha256) {
            (Ok(source), Ok(()), Ok(sha256)) => parsed.push(EntryInput {
                path,
                size,
                sha256,
                source,
            }),
            (Err(e), _, _) | (_, Err(e), _) | (_, _, Err(e)) => {
                errors.push(format!("entries[{i}]: {e}"))
            }
        }
    }
    if errors.is_empty() {
        Ok(parsed)
    } else {
        Err(AntdError::BadRequest(entry_errors_message(&errors)))
    }
}

fn entry_errors_message(errors: &[String]) -> String {
    let shown = errors
        .iter()
        .take(MAX_REPORTED_ENTRY_ERRORS)
        .cloned()
        .collect::<Vec<_>>()
        .join("; ");
    if errors.len() > MAX_REPORTED_ENTRY_ERRORS {
        format!(
            "{} invalid entries: {shown}; and {} more",
            errors.len(),
            errors.len() - MAX_REPORTED_ENTRY_ERRORS
        )
    } else {
        format!("{} invalid entries: {shown}", errors.len())
    }
}

/// Build a manifest: apply the embedding policy, then validate, sort and
/// encode it through ant-core.
pub async fn build<R: DataMapResolver>(
    resolver: &R,
    input: BuildInput,
) -> Result<BuildOutput, AntdError> {
    let BuildInput {
        name,
        torrent,
        entries,
        embed_roots,
    } = input;

    let resolved: Vec<Result<ManifestEntry, AntdError>> =
        stream::iter(entries.into_iter().enumerate())
            .map(|(i, entry)| embed_entry(resolver, i, entry, embed_roots))
            .buffered(RESOLVE_CONCURRENCY)
            .collect()
            .await;

    let manifest = Manifest {
        name,
        torrent,
        entries: resolved.into_iter().collect::<Result<Vec<_>, _>>()?,
    };
    finish_build(manifest)
}

/// One build entry as it will be written. `size` is recorded exactly as
/// given, as ant-core's builder does, so the same inputs give the CLI's
/// bytes; a reader takes the exact size from an embedded root DataMap. For a
/// shrunk map with `embed_roots`, resolve the root and embed it when it is
/// small enough, exactly as ant-core's `embeddable_data_map` decides.
async fn embed_entry<R: DataMapResolver>(
    resolver: &R,
    index: usize,
    entry: EntryInput,
    embed_roots: bool,
) -> Result<ManifestEntry, AntdError> {
    let EntryInput {
        path,
        size,
        sha256,
        source,
    } = entry;
    let given = match source {
        EntrySource::Address(address) => {
            return Ok(ManifestEntry {
                path,
                size,
                sha256,
                source: ContentRef::Public { address },
            })
        }
        EntrySource::DataMap(data_map) => data_map,
    };
    let data_map = if given.is_child() && embed_roots {
        let root = resolver
            .resolve_root(given.clone())
            .await
            .map_err(|e| with_entry(index, AntdError::from_core(e)))?;
        let fits = embedded_len(&root).map_err(manifest_error)? <= MAX_EMBEDDED_ROOT_MAP_BYTES;
        if fits {
            root
        } else {
            given
        }
    } else {
        given
    };
    Ok(ManifestEntry {
        path,
        size,
        sha256,
        source: ContentRef::Embedded { data_map },
    })
}

/// Encode a manifest whose entries are final, and describe it. CPU only.
fn finish_build(mut manifest: Manifest) -> Result<BuildOutput, AntdError> {
    // `encode` validates and sorts a copy; sort ours the same way so the
    // reported entries are in encoded order.
    manifest.canonicalize().map_err(manifest_error)?;
    let bytes = manifest.encode().map_err(manifest_error)?;
    let link = if manifest.entries.len() <= MAX_LINK_ENTRIES {
        let link_bytes =
            ant_core::data::manifest::manifest_link_bytes(&manifest).map_err(manifest_error)?;
        (link_bytes.len() <= MANIFEST_LINK_RECOMMENDED_MAX_BYTES)
            .then(|| ant_core::data::manifest::manifest_link_from_bytes(&link_bytes))
    } else {
        None
    };
    let entries = manifest
        .entries
        .into_iter()
        .map(|entry| entry_info(entry, false))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(BuildOutput {
        bytes,
        link,
        entries,
    })
}

/// Decode `.ant` bytes or a link, optionally resolving every entry's
/// DataMap to report exact sizes and confirm the DataMap is on the network.
pub async fn decode<R: DataMapResolver>(
    resolver: &R,
    input: DecodeInput,
    resolve: bool,
) -> Result<DecodeOutput, AntdError> {
    let (from, manifest) = match input {
        DecodeInput::Bytes(bytes) => (
            DecodedFrom::Manifest,
            Manifest::decode(&bytes).map_err(manifest_error)?,
        ),
        DecodeInput::Link(link) => match parse_link(&link).map_err(manifest_error)? {
            Link::Manifest(manifest) => (DecodedFrom::Manifest, manifest),
            Link::File(address) => (
                DecodedFrom::FileLink,
                Manifest {
                    name: None,
                    torrent: None,
                    entries: vec![ManifestEntry {
                        path: None,
                        size: None,
                        sha256: None,
                        source: ContentRef::Public { address },
                    }],
                },
            ),
        },
    };

    let Manifest {
        name,
        torrent,
        entries,
    } = manifest;
    let infos = entries
        .into_iter()
        .map(|entry| entry_info(entry, true))
        .collect::<Result<Vec<_>, _>>()?;

    let entries = if resolve {
        stream::iter(infos)
            .map(|info| resolve_entry(resolver, info))
            .buffered(RESOLVE_CONCURRENCY)
            .collect()
            .await
    } else {
        infos
            .into_iter()
            .map(|info| DecodedEntry {
                exact_size: info.known_size,
                info,
                error: None,
            })
            .collect()
    };

    Ok(DecodeOutput {
        from,
        name,
        torrent,
        entries,
    })
}

/// Resolve one decoded entry: fetch a `Public` entry's DataMap, then resolve
/// a shrunk map to its root. Content chunks are not fetched.
async fn resolve_entry<R: DataMapResolver>(resolver: &R, info: EntryInfo) -> DecodedEntry {
    if let Some(size) = info.known_size {
        return DecodedEntry {
            info,
            exact_size: Some(size),
            error: None,
        };
    }
    let data_map = match &info.data_map {
        Some(data_map) => Ok(data_map.clone()),
        None => resolver.fetch_public(info.content_address).await,
    };
    let root = match data_map {
        Ok(data_map) => resolver.resolve_root(data_map).await,
        Err(e) => Err(e),
    };
    match root {
        Ok(root) => DecodedEntry {
            info,
            exact_size: u64::try_from(root.original_file_size()).ok(),
            error: None,
        },
        Err(e) => DecodedEntry {
            info,
            exact_size: None,
            error: Some(AntdError::from_core(e).to_string()),
        },
    }
}

fn entry_info(entry: ManifestEntry, keep_data_map: bool) -> Result<EntryInfo, AntdError> {
    let effective_name = entry.effective_name().map_err(manifest_error)?;
    let content_address = entry.source.content_address().map_err(manifest_error)?;
    let known_size = entry.known_size();
    let kind = entry.source.kind();
    let data_map = match entry.source {
        ContentRef::Embedded { data_map } if keep_data_map => Some(data_map),
        _ => None,
    };
    Ok(EntryInfo {
        effective_name,
        path: entry.path,
        size: entry.size,
        sha256: entry.sha256,
        kind,
        content_address,
        known_size,
        data_map,
    })
}

/// Map a manifest error onto the daemon's error kinds. Everything the format
/// rejects is the caller's input; network failures keep their own kind.
pub fn manifest_error(e: ManifestError) -> AntdError {
    match e {
        ManifestError::Data(core) => AntdError::from_core(core),
        ManifestError::Io(io) => AntdError::Internal(io.to_string()),
        other => AntdError::BadRequest(other.to_string()),
    }
}

/// Name the entry an error came from, keeping its kind.
fn with_entry(i: usize, e: AntdError) -> AntdError {
    let tag = |msg: String| format!("entries[{i}]: {msg}");
    match e {
        AntdError::NotFound(m) => AntdError::NotFound(tag(m)),
        AntdError::BadRequest(m) => AntdError::BadRequest(tag(m)),
        AntdError::Network(m) => AntdError::Network(tag(m)),
        AntdError::Timeout(m) => AntdError::Timeout(tag(m)),
        AntdError::ServiceUnavailable(m) => AntdError::ServiceUnavailable(tag(m)),
        AntdError::Internal(m) => AntdError::Internal(tag(m)),
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ant_core::data::manifest::{data_map_address, MAX_MANIFEST_BYTES};
    use bytes::Bytes;
    use self_encryption::XorName;
    use std::collections::HashMap;

    /// An in-memory network: wrapper chunks by content hash, plus public
    /// DataMaps by address.
    #[derive(Default)]
    struct FakeNetwork {
        chunks: HashMap<XorName, Bytes>,
        public: HashMap<[u8; ADDRESS_LEN], DataMap>,
    }

    impl DataMapResolver for FakeNetwork {
        async fn resolve_root(&self, data_map: DataMap) -> Result<DataMap, ant_core::data::Error> {
            if !data_map.is_child() {
                return Ok(data_map);
            }
            self_encryption::get_root_data_map(data_map, &mut |name: XorName| {
                self.chunks
                    .get(&name)
                    .cloned()
                    .ok_or_else(|| self_encryption::Error::Generic("missing wrapper".into()))
            })
            .map_err(|e| ant_core::data::Error::NotFound(e.to_string()))
        }

        async fn fetch_public(
            &self,
            address: [u8; ADDRESS_LEN],
        ) -> Result<DataMap, ant_core::data::Error> {
            self.public.get(&address).cloned().ok_or_else(|| {
                ant_core::data::Error::NotFound(format!(
                    "DataMap chunk not found at {}",
                    hex::encode(address)
                ))
            })
        }
    }

    /// Encrypt `size` patterned bytes; store the wrapper (and content)
    /// chunks in `net`. Returns the DataMap an upload hands back: shrunk
    /// when the file is over three chunks.
    fn upload(net: &mut FakeNetwork, size: usize, seed: u8) -> DataMap {
        let data = Bytes::from(
            (0..size)
                .map(|i| ((i % 251) as u8).wrapping_add(seed))
                .collect::<Vec<u8>>(),
        );
        let (data_map, chunks) = self_encryption::encrypt(data).expect("encrypt");
        for c in chunks {
            net.chunks
                .insert(self_encryption::hash::content_hash(&c.content), c.content);
        }
        data_map
    }

    fn embedded(path: &str, data_map: DataMap) -> EntryInput {
        EntryInput {
            path: Some(path.into()),
            size: None,
            sha256: None,
            source: EntrySource::DataMap(data_map),
        }
    }

    fn build_input(entries: Vec<EntryInput>) -> BuildInput {
        BuildInput {
            name: Some("album".into()),
            torrent: None,
            entries,
            embed_roots: true,
        }
    }

    const BIG: usize = 3 * self_encryption::MAX_CHUNK_SIZE + 1;

    #[tokio::test]
    async fn build_embeds_roots_records_exact_sizes_and_sorts() {
        let mut net = FakeNetwork::default();
        let small = upload(&mut net, 1024, 1);
        let big = upload(&mut net, BIG, 2);
        assert!(big.is_child());

        let out = build(
            &net,
            build_input(vec![
                embedded("z/big.bin", big.clone()),
                embedded("a.txt", small.clone()),
                EntryInput {
                    path: Some("m.txt".into()),
                    size: Some(5),
                    sha256: None,
                    source: EntrySource::Address([9; ADDRESS_LEN]),
                },
            ]),
        )
        .await
        .expect("build");

        let names: Vec<_> = out
            .entries
            .iter()
            .map(|e| e.effective_name.as_str())
            .collect();
        assert_eq!(names, ["a.txt", "m.txt", "z/big.bin"]);

        // The shrunk map was resolved and its (small) root embedded, so the
        // exact size is known. No size is recorded unless one is given, as
        // in ant-core's builder.
        let big_info = &out.entries[2];
        assert_eq!(big_info.kind, "embedded");
        assert_eq!(big_info.known_size, Some(BIG as u64));
        assert_eq!(big_info.size, None);
        assert_eq!(big_info.content_address, data_map_address(&big).unwrap());
        // The public entry keeps the caller's claim and has no known size.
        assert_eq!(out.entries[1].kind, "public");
        assert_eq!(out.entries[1].size, Some(5));
        assert_eq!(out.entries[1].known_size, None);

        // The bytes round-trip through ant-core and match what we reported.
        let decoded = Manifest::decode(&out.bytes).expect("decode");
        assert_eq!(decoded.name.as_deref(), Some("album"));
        assert_eq!(decoded.entries.len(), 3);
        assert!(matches!(
            &decoded.entries[2].source,
            ContentRef::Embedded { data_map } if !data_map.is_child()
        ));
    }

    #[tokio::test]
    async fn build_is_deterministic_and_matches_ant_core_encoding() {
        let mut net = FakeNetwork::default();
        let a = upload(&mut net, 2048, 3);
        let b = upload(&mut net, 4096, 4);
        let one = build(
            &net,
            build_input(vec![embedded("b", b.clone()), embedded("a", a.clone())]),
        )
        .await
        .unwrap();
        let two = build(
            &net,
            build_input(vec![embedded("a", a.clone()), embedded("b", b.clone())]),
        )
        .await
        .unwrap();
        assert_eq!(one.bytes, two.bytes);

        // Same bytes as building the manifest directly in ant-core, as the
        // CLI does for DataMaps already in hand.
        let direct = Manifest {
            name: Some("album".into()),
            torrent: None,
            entries: vec![
                ManifestEntry {
                    path: Some("a".into()),
                    size: None,
                    sha256: None,
                    source: ContentRef::Embedded { data_map: a },
                },
                ManifestEntry {
                    path: Some("b".into()),
                    size: None,
                    sha256: None,
                    source: ContentRef::Embedded { data_map: b },
                },
            ],
        };
        assert_eq!(one.bytes, direct.encode().unwrap());
    }

    #[tokio::test]
    async fn build_without_embed_roots_keeps_the_shrunk_map_and_skips_the_network() {
        let mut net = FakeNetwork::default();
        let big = upload(&mut net, BIG, 5);
        let empty = FakeNetwork::default(); // any fetch would fail
        let mut input = build_input(vec![embedded("big", big.clone())]);
        input.embed_roots = false;
        let out = build(&empty, input).await.expect("build");
        assert_eq!(out.entries[0].known_size, None);
        assert_eq!(out.entries[0].size, None);
        let decoded = Manifest::decode(&out.bytes).unwrap();
        assert!(matches!(
            &decoded.entries[0].source,
            ContentRef::Embedded { data_map } if data_map.is_child()
        ));
    }

    #[tokio::test]
    async fn build_names_the_entry_whose_wrapper_records_are_missing() {
        let mut net = FakeNetwork::default();
        let big = upload(&mut net, BIG, 6);
        let empty = FakeNetwork::default();
        let err = build(
            &empty,
            build_input(vec![
                embedded("ok", upload(&mut net, 10, 1)),
                embedded("big", big),
            ]),
        )
        .await
        .err()
        .expect("must fail");
        assert!(
            matches!(err, AntdError::NotFound(ref m) if m.starts_with("entries[1]:")),
            "{err}"
        );
    }

    #[tokio::test]
    async fn build_rejects_colliding_names() {
        let net = FakeNetwork::default();
        let input = build_input(vec![
            EntryInput {
                path: Some("Readme.md".into()),
                size: None,
                sha256: None,
                source: EntrySource::Address([1; ADDRESS_LEN]),
            },
            EntryInput {
                path: Some("README.md".into()),
                size: None,
                sha256: None,
                source: EntrySource::Address([2; ADDRESS_LEN]),
            },
        ]);
        let err = build(&net, input).await.err().expect("collision");
        assert!(matches!(err, AntdError::BadRequest(_)), "{err}");
    }

    fn raw(
        path: Option<&str>,
        sha256: Option<&str>,
        data_map: Option<&str>,
        address: Option<&str>,
    ) -> RawEntry {
        RawEntry {
            path: path.map(str::to_string),
            size: None,
            sha256: sha256.map(str::to_string),
            data_map: data_map.map(str::to_string),
            address: address.map(str::to_string),
        }
    }

    #[test]
    fn parse_entries_reports_every_invalid_entry() {
        let good = hex::encode([7u8; ADDRESS_LEN]);
        let good = Some(good.as_str());
        let err = parse_entries(vec![
            raw(Some("ok.txt"), None, None, good),
            raw(Some("../escape"), None, None, good),
            raw(None, None, None, None),
            raw(None, None, Some("zz"), None),
            raw(None, None, Some("00"), good),
            raw(None, None, None, Some("abcd")),
            raw(Some("short-hash"), Some("abcd"), None, good),
            raw(Some("bad-hash"), Some("zz"), None, good),
        ])
        .err()
        .expect("invalid");
        let AntdError::BadRequest(msg) = err else {
            panic!("expected BadRequest, got {err}");
        };
        assert!(msg.starts_with("7 invalid entries"), "{msg}");
        for i in 1..=7 {
            assert!(msg.contains(&format!("entries[{i}]")), "{msg}");
        }
        assert!(!msg.contains("entries[0]"), "{msg}");
    }

    #[test]
    fn parse_entries_treats_empty_strings_as_absent() {
        let addr = hex::encode([3u8; ADDRESS_LEN]);
        let parsed =
            parse_entries(vec![raw(Some(""), Some(""), Some(""), Some(&addr))]).expect("valid");
        assert!(parsed[0].path.is_none());
        assert!(parsed[0].sha256.is_none());
        assert!(matches!(parsed[0].source, EntrySource::Address(a) if a == [3; ADDRESS_LEN]));
    }

    #[tokio::test]
    async fn sha256_is_recorded_as_given_and_reported_on_decode() {
        let mut net = FakeNetwork::default();
        let data_map = upload(&mut net, 4096, 9);
        let hash = [0xcd; SHA256_LEN];
        let mut entry = embedded("hashed.bin", data_map.clone());
        entry.sha256 = Some(hash);
        let out = build(
            &net,
            build_input(vec![entry, embedded("plain.bin", data_map)]),
        )
        .await
        .unwrap();
        let by_name = |entries: &[EntryInfo], n: &str| {
            entries.iter().position(|e| e.effective_name == n).unwrap()
        };
        assert_eq!(
            out.entries[by_name(&out.entries, "hashed.bin")].sha256,
            Some(hash)
        );
        assert_eq!(out.entries[by_name(&out.entries, "plain.bin")].sha256, None);

        // Same bytes as ant-core writes for the same entry.
        let decoded = Manifest::decode(&out.bytes).unwrap();
        let hashed = decoded
            .entries
            .iter()
            .find(|e| e.path.as_deref() == Some("hashed.bin"))
            .unwrap();
        assert_eq!(hashed.sha256, Some(hash));

        let d = decode(&net, DecodeInput::Bytes(out.bytes), false)
            .await
            .unwrap();
        let infos: Vec<EntryInfo> = d.entries.into_iter().map(|e| e.info).collect();
        assert_eq!(infos[by_name(&infos, "hashed.bin")].sha256, Some(hash));
    }

    #[test]
    fn torrent_hashes_merge_v1_and_v2() {
        let v1 = "a".repeat(40);
        let v2 = "b".repeat(64);
        let t = parse_torrent_hashes(&[v1, v2]).unwrap().unwrap();
        assert!(t.info_hash_v1.is_some() && t.info_hash_v2.is_some());
        assert!(parse_torrent_hashes(&[]).unwrap().is_none());
        assert!(parse_torrent_hashes(&["c".repeat(30)]).is_err());
        assert!(parse_torrent_hashes(&["a".repeat(40), "b".repeat(40), "c".repeat(64)]).is_err());
    }

    #[tokio::test]
    async fn small_manifests_get_a_link_that_decodes_to_the_same_entries() {
        let mut net = FakeNetwork::default();
        let a = upload(&mut net, 100, 1);
        let out = build(&net, build_input(vec![embedded("a.txt", a.clone())]))
            .await
            .unwrap();
        let link = out.link.clone().expect("a one-entry manifest fits a link");
        assert!(link.starts_with("ant://manifest/"));

        let decoded = decode(&net, DecodeInput::Link(link), false).await.unwrap();
        assert_eq!(decoded.from, DecodedFrom::Manifest);
        assert_eq!(decoded.entries.len(), 1);
        assert_eq!(decoded.entries[0].info.effective_name, "a.txt");
        assert_eq!(
            decoded.entries[0].info.content_address,
            out.entries[0].content_address
        );
    }

    #[tokio::test]
    async fn large_manifests_get_no_link() {
        let net = FakeNetwork::default();
        let entries = (0..(MAX_LINK_ENTRIES as u8 + 1))
            .map(|i| EntryInput {
                path: Some(format!("f{i}")),
                size: None,
                sha256: None,
                source: EntrySource::Address([i; ADDRESS_LEN]),
            })
            .collect();
        let out = build(&net, build_input(entries)).await.unwrap();
        assert!(out.link.is_none());
    }

    #[tokio::test]
    async fn decode_reports_embedded_data_maps_and_resolves_public_entries() {
        let mut net = FakeNetwork::default();
        let private = upload(&mut net, 1000, 7);
        let public_big = upload(&mut net, BIG, 8);
        let public_addr = data_map_address(&public_big).unwrap();
        net.public.insert(public_addr, public_big.clone());

        let out = build(
            &net,
            build_input(vec![
                embedded("private.bin", private.clone()),
                EntryInput {
                    path: Some("public.bin".into()),
                    size: None,
                    sha256: None,
                    source: EntrySource::Address(public_addr),
                },
                EntryInput {
                    path: Some("gone.bin".into()),
                    size: None,
                    sha256: None,
                    source: EntrySource::Address([0xee; ADDRESS_LEN]),
                },
            ]),
        )
        .await
        .unwrap();

        // Without resolve: no network, embedded entries carry their DataMap.
        let plain = decode(
            &FakeNetwork::default(),
            DecodeInput::Bytes(out.bytes.clone()),
            false,
        )
        .await
        .unwrap();
        let by_name = |d: &DecodeOutput, n: &str| {
            d.entries
                .iter()
                .position(|e| e.info.effective_name == n)
                .unwrap()
        };
        let p = &plain.entries[by_name(&plain, "private.bin")];
        assert_eq!(p.info.data_map.as_ref(), Some(&private));
        assert_eq!(p.exact_size, Some(1000));
        assert!(plain.entries[by_name(&plain, "public.bin")]
            .info
            .data_map
            .is_none());
        assert_eq!(
            plain.entries[by_name(&plain, "public.bin")].exact_size,
            None
        );

        // With resolve: the public DataMap is fetched and its root resolved;
        // a missing one fails only its own entry.
        let resolved = decode(&net, DecodeInput::Bytes(out.bytes), true)
            .await
            .unwrap();
        let pubent = &resolved.entries[by_name(&resolved, "public.bin")];
        assert_eq!(pubent.exact_size, Some(BIG as u64));
        assert!(pubent.error.is_none());
        let gone = &resolved.entries[by_name(&resolved, "gone.bin")];
        assert_eq!(gone.exact_size, None);
        assert!(
            gone.error.as_deref().unwrap().contains("not found"),
            "{:?}",
            gone.error
        );
    }

    #[tokio::test]
    async fn decode_turns_a_file_link_into_one_public_entry() {
        let addr = [0x42; ADDRESS_LEN];
        let link = format!("ant://{}", hex::encode(addr));
        for input in [link.clone(), hex::encode(addr)] {
            let d = decode(&FakeNetwork::default(), DecodeInput::Link(input), false)
                .await
                .unwrap();
            assert_eq!(d.from, DecodedFrom::FileLink);
            assert_eq!(d.entries.len(), 1);
            assert_eq!(d.entries[0].info.kind, "public");
            assert_eq!(d.entries[0].info.content_address, addr);
            assert_eq!(d.entries[0].info.effective_name, hex::encode(addr));
        }
    }

    #[tokio::test]
    async fn decode_rejects_hostile_input_cleanly() {
        let net = FakeNetwork::default();
        for bytes in [
            Vec::new(),
            b"not a manifest".to_vec(),
            vec![0xC1, b'A', b'N', b'T', 9], // unknown version
            vec![0xC1, b'A', b'N', b'T', 1, 0x93, 1, 2, 3], // positional array body
            vec![0xC1, b'A', b'N', b'T', 1, 0xde, 0xff, 0xff], // truncated map
        ] {
            let err = decode(&net, DecodeInput::Bytes(bytes), false)
                .await
                .err()
                .expect("must reject");
            assert!(matches!(err, AntdError::BadRequest(_)), "{err}");
        }
        let too_big = vec![0u8; MAX_MANIFEST_BYTES + 1];
        assert!(matches!(
            decode(&net, DecodeInput::Bytes(too_big), false).await.err(),
            Some(AntdError::BadRequest(_))
        ));
        for link in [
            "ant://manifest/",
            "ant://manifest/!!!",
            "ant://abc",
            "ant://00/x",
        ] {
            let err = decode(&net, DecodeInput::Link(link.into()), false)
                .await
                .err()
                .expect("must reject");
            assert!(matches!(err, AntdError::BadRequest(_)), "{link}: {err}");
        }
    }
}
