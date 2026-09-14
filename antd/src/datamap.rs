//! DataMap resolution shared by the REST and gRPC streaming download handlers.
//!
//! Large uploads produce a *shrunk* (child) `DataMap`: self-encryption
//! recursively encrypts the serialized map into wrapper chunks until at most 3
//! infos remain, so any file over 3 × `MAX_CHUNK_SIZE` (~12.5 MB) arrives
//! here as a child map. On such a map `DataMap::original_file_size()`
//! describes the serialized parent map (a few hundred bytes), **not** the
//! plaintext file — sizing a streaming response from it truncates the download
//! at the bogus `Content-Length` (V2-1104). ant-core resolves child maps
//! internally for its buffered path but keeps that resolver private, so the
//! streaming handlers resolve here, via the public `chunk_get`, before sizing
//! the response.

use ant_core::data::{Client, DataMap, Error};
use bytes::Bytes;
use self_encryption::XorName;
use tokio::runtime::{Handle, RuntimeFlavor};

/// Resolve a possibly-shrunk `DataMap` to its root (flat) form.
///
/// A non-child map is returned unchanged without touching the network. For a
/// child map, the wrapper chunks are fetched with `Client::chunk_get` and the
/// map is unshrunk recursively until the root map — whose `infos()` reference
/// the actual content chunks and whose `original_file_size()` is the true
/// plaintext size — is obtained. Handing the resolved map to
/// `file_download_to_sender` also lets the download skip its own internal
/// resolution, so the wrapper chunks are fetched exactly once.
///
/// Self-encryption's chunk fetcher is synchronous, so resolution bridges onto
/// the async network via `block_in_place`. That requires the multi-threaded
/// Tokio runtime antd always runs; a current-thread runtime gets
/// [`Error::Config`] instead of a panic.
pub async fn resolve_root_data_map(
    client: &Client,
    data_map: DataMap,
) -> std::result::Result<DataMap, Error> {
    if !data_map.is_child() {
        return Ok(data_map);
    }

    let handle = Handle::current();
    if handle.runtime_flavor() != RuntimeFlavor::MultiThread {
        return Err(Error::Config(
            "resolving a shrunk DataMap requires a multi-threaded tokio runtime".into(),
        ));
    }

    // The self-encryption fetcher may only yield `self_encryption::Error`.
    // Stash the underlying ant-core error out-of-band so a missing wrapper
    // chunk surfaces as `Error::NotFound` and a network failure keeps its
    // `Timeout`/`Network` classification, instead of every resolution failure
    // flattening to `Error::Encryption`.
    let mut fetch_error: Option<Error> = None;
    let resolved = tokio::task::block_in_place(|| {
        let mut get_chunk = |name: XorName| -> std::result::Result<Bytes, self_encryption::Error> {
            handle.block_on(async {
                match client.chunk_get(&name.0).await {
                    Ok(Some(chunk)) => Ok(chunk.content),
                    Ok(None) => Err(stash_fetch_error(
                        &mut fetch_error,
                        Error::NotFound(format!(
                            "Missing wrapper chunk {} required to resolve root DataMap",
                            hex::encode(name.0),
                        )),
                    )),
                    Err(e) => Err(stash_fetch_error(&mut fetch_error, e)),
                }
            })
        };
        resolve_with_fetcher(data_map, &mut get_chunk)
    });

    resolved.map_err(|e| {
        fetch_error
            .take()
            .unwrap_or_else(|| Error::Encryption(format!("Failed to resolve root data map: {e}")))
    })
}

/// Fetcher-parameterized core of [`resolve_root_data_map`], unit-testable
/// without a network-backed client.
fn resolve_with_fetcher<F>(
    data_map: DataMap,
    get_chunk: &mut F,
) -> std::result::Result<DataMap, self_encryption::Error>
where
    F: FnMut(XorName) -> std::result::Result<Bytes, self_encryption::Error>,
{
    if !data_map.is_child() {
        return Ok(data_map);
    }
    self_encryption::get_root_data_map(data_map, get_chunk)
}

/// Record the real ant-core error behind a fetch failure and return the
/// `self_encryption::Error` the fetcher is required to yield, so the caller
/// can recover the descriptive error instead of a flattened generic one.
fn stash_fetch_error(slot: &mut Option<Error>, error: Error) -> self_encryption::Error {
    let message = error.to_string();
    *slot = Some(error);
    self_encryption::Error::Generic(message)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    /// Smallest plaintext that yields more than 3 chunks — and therefore a
    /// shrunk (child) DataMap on upload, the V2-1104 trigger.
    const MULTI_CHUNK_SIZE: usize = 3 * self_encryption::MAX_CHUNK_SIZE + 1;

    /// Encrypt `size` patterned bytes the way `data_upload` does. `encrypt`
    /// already shrinks the map, so for a multi-chunk plaintext the returned
    /// map is the child form; the chunk list holds content and wrapper chunks
    /// alike, stored here keyed by content hash (their network address).
    fn encrypted_fixture(size: usize) -> (DataMap, HashMap<XorName, Bytes>) {
        let data = Bytes::from((0..size).map(|i| (i % 251) as u8).collect::<Vec<u8>>());
        let (data_map, chunks) = self_encryption::encrypt(data).expect("encrypt");
        let store = chunks
            .into_iter()
            .map(|c| (self_encryption::hash::content_hash(&c.content), c.content))
            .collect();
        (data_map, store)
    }

    #[test]
    fn child_map_misreports_size_and_resolution_restores_it() {
        let (shrunk, store) = encrypted_fixture(MULTI_CHUNK_SIZE);
        assert!(shrunk.is_child());

        // The V2-1104 bug: sizing a response from the shrunk map yields the
        // serialized-parent-map size, orders of magnitude below the plaintext.
        assert_ne!(shrunk.original_file_size(), MULTI_CHUNK_SIZE);
        assert!(shrunk.original_file_size() < 100_000);

        let resolved = resolve_with_fetcher(shrunk, &mut |name| {
            store
                .get(&name)
                .cloned()
                .ok_or_else(|| self_encryption::Error::Generic(format!("missing chunk {name:?}")))
        })
        .expect("resolve");

        assert!(!resolved.is_child());
        assert_eq!(resolved.original_file_size(), MULTI_CHUNK_SIZE);
        assert_eq!(
            resolved.infos().len(),
            MULTI_CHUNK_SIZE.div_ceil(self_encryption::MAX_CHUNK_SIZE)
        );
    }

    #[test]
    fn flat_map_passes_through_without_fetching() {
        let size = 1024 * 1024; // ≤ 3 chunks — never shrunk
        let data = Bytes::from(vec![7u8; size]);
        let (map, _chunks) = self_encryption::encrypt(data).expect("encrypt");
        assert!(!map.is_child());

        let resolved = resolve_with_fetcher(map.clone(), &mut |_name| {
            panic!("flat map must not fetch wrapper chunks")
        })
        .expect("resolve");

        assert_eq!(resolved.original_file_size(), size);
        assert_eq!(resolved.infos().len(), map.infos().len());
    }
}
