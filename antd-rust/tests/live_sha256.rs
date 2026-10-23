//! Live check of the plaintext SHA-256 that antd 0.17.0 reports, against a
//! running antd with a devnet behind it.
//!
//! Skipped unless both of these are set:
//!
//! - `ANTD_TEST_URL`: the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
//! - `ANTD_TEST_SHA_LINK`: an `ant://manifest/` link with the entries
//!   `public.txt` and `private.txt` (each with a `sha256`) and `nohash.txt`
//!   (none)
//!
//! Also read:
//!
//! - `ANTD_TEST_SHA_PUBLIC_SHA256` and `ANTD_TEST_SHA_DATA_MAP_SHA256`: the
//!   hashes `public.txt` and `private.txt` must carry
//! - `ANTD_TEST_SHA_PUBLIC_ADDRESS`: the public upload's address, to build a
//!   manifest from
//! - `ANTD_TEST_GRPC`: the daemon's gRPC endpoint (`host:port` or a URL), to
//!   repeat everything over gRPC
//!
//! It makes ONE PAID call per transport: a public data upload of a few bytes,
//! whose reported `sha256` must equal the hash computed here.

use antd_client::{AntdError, Client, GrpcClient, ManifestEntryInput, PaymentMode};
use sha2::{Digest, Sha256};

fn var(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.trim().is_empty())
}

fn need(name: &str) -> String {
    var(name).unwrap_or_else(|| panic!("{name} must be set"))
}

fn hex_sha256(data: &[u8]) -> String {
    Sha256::digest(data)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

#[tokio::test]
async fn live_sha256() {
    let (Some(rest_url), Some(link)) = (var("ANTD_TEST_URL"), var("ANTD_TEST_SHA_LINK")) else {
        eprintln!("live_sha256: set ANTD_TEST_URL and ANTD_TEST_SHA_LINK to run");
        return;
    };
    let public_sha = need("ANTD_TEST_SHA_PUBLIC_SHA256");
    let data_map_sha = need("ANTD_TEST_SHA_DATA_MAP_SHA256");
    let public_address = need("ANTD_TEST_SHA_PUBLIC_ADDRESS");
    let unix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let rest = Client::new(&rest_url);
    let grpc = match var("ANTD_TEST_GRPC") {
        Some(g) => {
            let g = if g.contains("://") {
                g
            } else {
                format!("http://{g}")
            };
            Some(GrpcClient::connect(&g).await.expect("grpc connect"))
        }
        None => {
            eprintln!("live_sha256: ANTD_TEST_GRPC unset, skipping the gRPC half");
            None
        }
    };

    // The same checks over each transport. The macro keeps one body for the
    // two client types, which share method names but no trait.
    macro_rules! check {
        ($c:expr, $name:literal) => {{
            let c = $c;

            // 1. Decode the fixture link without resolving.
            let d = c.decode_manifest_link(&link, false).await.unwrap();
            let sha = |name: &str| {
                d.entries
                    .iter()
                    .find(|e| e.effective_name == name)
                    .unwrap_or_else(|| panic!("no entry {name:?} in {:#?}", d.entries))
                    .sha256
                    .clone()
            };
            assert_eq!(sha("public.txt").as_deref(), Some(public_sha.as_str()));
            assert_eq!(sha("private.txt").as_deref(), Some(data_map_sha.as_str()));
            assert_eq!(sha("nohash.txt"), None);

            // 2. Build a manifest whose entry carries the hash.
            let built = c
                .build_manifest(&[ManifestEntryInput::public(&public_address)
                    .with_path("a.txt")
                    .with_sha256(&public_sha)])
                .await
                .unwrap();
            assert_eq!(built.entries.len(), 1);
            assert_eq!(
                built.entries[0].sha256.as_deref(),
                Some(public_sha.as_str())
            );

            // 3. A malformed hash is the daemon's 400.
            match c
                .build_manifest(&[ManifestEntryInput::public(&public_address)
                    .with_path("a.txt")
                    .with_sha256("zz")])
                .await
            {
                Err(AntdError::BadRequest(msg)) => {
                    assert!(msg.contains("sha256"), "{msg}");
                    println!("{}: bad sha256 -> BadRequest({msg:?})", $name);
                }
                other => panic!("{}: expected BadRequest, got {other:?}", $name),
            }

            // 4. One paid call: a public upload reports the plaintext's hash.
            let payload = format!("sha-fanout rust {unix} {}", $name).into_bytes();
            let local = hex_sha256(&payload);
            let put = c
                .data_put_public(&payload, PaymentMode::Auto)
                .await
                .unwrap();
            println!(
                "{}: uploaded {:?} to {}; local sha256 {local}, reported {:?}",
                $name,
                String::from_utf8_lossy(&payload),
                put.address,
                put.sha256
            );
            assert_eq!(put.sha256.as_deref(), Some(local.as_str()));
        }};
    }

    check!(&rest, "REST");
    if let Some(g) = &grpc {
        check!(g, "gRPC");
    }
    println!("live_sha256: OK");
}
