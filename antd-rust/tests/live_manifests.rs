//! Live manifest round trip against a running antd with a devnet behind it.
//! It makes no paid calls: it builds and decodes manifests of data that is
//! already uploaded.
//!
//! Skipped unless both of these are set:
//!
//! - `ANTD_TEST_URL`: the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
//! - `ANTD_TEST_MANIFEST_ADDRESSES`: two comma-separated addresses of public
//!   data uploads
//!
//! Optional:
//!
//! - `ANTD_TEST_MANIFEST_SIZES`: the two uploads' exact plaintext sizes,
//!   checked against a resolving decode
//! - `ANTD_TEST_MANIFEST_DATA_MAP` and `ANTD_TEST_MANIFEST_DATA_MAP_SIZE`: a
//!   private upload's hex DataMap and its size, added as an embedded entry
//! - `ANTD_TEST_MANIFEST_LINK`: an `ant://manifest/` link to decode
//! - `ANTD_TEST_GRPC`: the daemon's gRPC endpoint (`host:port` or a URL),
//!   to repeat the round trip over gRPC
//!
//! ```text
//! ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_MANIFEST_ADDRESSES=<hex>,<hex> \
//! cargo test --test live_manifests -- --nocapture
//! ```

use antd_client::{
    AntdError, BuildManifestOptions, BuiltManifest, Client, DecodedManifest, GrpcClient,
    ManifestEntryInfo, ManifestEntryInput,
};

struct Env {
    rest: String,
    grpc: Option<String>,
    addresses: [String; 2],
    sizes: Option<[u64; 2]>,
    data_map: Option<(String, Option<u64>)>,
    link: Option<String>,
}

fn var(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.trim().is_empty())
}

fn env() -> Option<Env> {
    let rest = var("ANTD_TEST_URL")?;
    let addresses = var("ANTD_TEST_MANIFEST_ADDRESSES")?;
    let (a, b) = addresses.split_once(',')?;
    let sizes = var("ANTD_TEST_MANIFEST_SIZES").map(|s| {
        let (x, y) = s
            .split_once(',')
            .expect("ANTD_TEST_MANIFEST_SIZES: two sizes");
        [x, y].map(|n| n.trim().parse().expect("ANTD_TEST_MANIFEST_SIZES: u64"))
    });
    let data_map = var("ANTD_TEST_MANIFEST_DATA_MAP").map(|dm| {
        let size = var("ANTD_TEST_MANIFEST_DATA_MAP_SIZE").map(|n| {
            n.trim()
                .parse()
                .expect("ANTD_TEST_MANIFEST_DATA_MAP_SIZE: u64")
        });
        (dm.trim().to_string(), size)
    });
    let grpc = var("ANTD_TEST_GRPC").map(|g| {
        if g.contains("://") {
            g
        } else {
            format!("http://{g}")
        }
    });
    Some(Env {
        rest,
        grpc,
        addresses: [a.trim().to_string(), b.trim().to_string()],
        sizes,
        data_map,
        link: var("ANTD_TEST_MANIFEST_LINK"),
    })
}

const ONE: &str = "public/one.txt";
const TWO: &str = "public/two.txt";
const THREE: &str = "private/three.txt";

fn entries(env: &Env) -> Vec<ManifestEntryInput> {
    let mut entries = vec![
        ManifestEntryInput::public(&env.addresses[0]).with_path(ONE),
        ManifestEntryInput::public(&env.addresses[1]).with_path(TWO),
    ];
    if let Some((dm, _)) = &env.data_map {
        entries.push(ManifestEntryInput::embedded(dm).with_path(THREE));
    }
    entries
}

fn entry<'a>(entries: &'a [ManifestEntryInfo], name: &str) -> &'a ManifestEntryInfo {
    entries
        .iter()
        .find(|e| e.effective_name == name)
        .unwrap_or_else(|| panic!("no entry {name:?} in {entries:#?}"))
}

fn options() -> BuildManifestOptions {
    BuildManifestOptions {
        name: Some("antd-rust-live".into()),
        ..Default::default()
    }
}

fn check_built(env: &Env, built: &BuiltManifest) {
    assert!(!built.manifest.is_empty());
    let link = built
        .link
        .as_deref()
        .expect("a three-entry manifest fits a link");
    assert!(link.starts_with("ant://manifest/"), "{link}");
    assert_eq!(built.entries.len(), entries(env).len());
    for (name, address) in [(ONE, &env.addresses[0]), (TWO, &env.addresses[1])] {
        let e = entry(&built.entries, name);
        assert_eq!(e.kind, "public");
        assert_eq!(e.path.as_deref(), Some(name));
        assert_eq!(&e.content_address, address);
        // Built without a size: none is recorded, and it reads as None.
        assert_eq!(e.size, None);
    }
    if env.data_map.is_some() {
        let e = entry(&built.entries, THREE);
        assert_eq!(e.kind, "embedded");
        assert_eq!(e.content_address.len(), 64);
    }
}

/// Checks a resolving decode of the manifest [`entries`] builds.
fn check_resolved(env: &Env, d: &DecodedManifest) {
    assert_eq!(d.source, "manifest");
    assert_eq!(d.name.as_deref(), Some("antd-rust-live"));
    assert_eq!(d.entries.len(), entries(env).len());
    for (i, name) in [ONE, TWO].into_iter().enumerate() {
        let e = entry(&d.entries, name);
        assert_eq!(e.kind, "public");
        assert_eq!(e.data_map, None, "a public entry carries no DataMap");
        assert_eq!(e.error, None, "{name}: resolve failed");
        assert_eq!(e.size, None);
        let exact = e.exact_size.expect("a resolving decode reports exact_size");
        if let Some(sizes) = env.sizes {
            assert_eq!(exact, sizes[i], "{name}: exact_size");
        }
    }
    if let Some((_, size)) = &env.data_map {
        let e = entry(&d.entries, THREE);
        assert_eq!(e.kind, "embedded");
        assert!(e.data_map.as_deref().is_some_and(|dm| !dm.is_empty()));
        assert_eq!(e.error, None);
        if let Some(size) = size {
            assert_eq!(e.exact_size, Some(*size), "embedded exact_size");
        }
    }
}

/// The fixture link: its entries' exact sizes match the fixtures, and an
/// embedded entry carries its DataMap.
fn check_fixture_link(env: &Env, d: &DecodedManifest) {
    assert_eq!(d.source, "manifest");
    assert!(!d.entries.is_empty());
    for e in &d.entries {
        assert_eq!(e.error, None, "{}: resolve failed", e.effective_name);
        assert!(
            e.exact_size.is_some(),
            "{}: no exact_size",
            e.effective_name
        );
        if let (Some(i), Some(sizes)) = (
            env.addresses.iter().position(|a| *a == e.content_address),
            env.sizes,
        ) {
            assert_eq!(e.exact_size, Some(sizes[i]), "{}", e.effective_name);
        }
        if e.kind == "embedded" {
            assert!(e.data_map.as_deref().is_some_and(|dm| !dm.is_empty()));
            if let Some((_, Some(size))) = &env.data_map {
                assert_eq!(e.exact_size, Some(*size), "{}", e.effective_name);
            }
        }
    }
}

fn bad_request_message<T: std::fmt::Debug>(r: Result<T, AntdError>) -> String {
    match r {
        Err(AntdError::BadRequest(msg)) => msg,
        other => panic!("expected BadRequest, got {other:?}"),
    }
}

fn assert_bad_request<T: std::fmt::Debug>(r: Result<T, AntdError>, needle: &str) {
    match r {
        Err(AntdError::BadRequest(msg)) => assert!(msg.contains(needle), "{msg}"),
        other => panic!("expected BadRequest naming {needle:?}, got {other:?}"),
    }
}

#[tokio::test]
async fn live_manifest_round_trip() {
    let Some(env) = env() else {
        eprintln!("live_manifests: set ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES to run");
        return;
    };
    let rest = Client::new(&env.rest);
    let entries = entries(&env);

    // ── build, then decode the bytes and the link ──
    let built = rest
        .build_manifest_with_options(&entries, &options())
        .await
        .unwrap();
    check_built(&env, &built);
    let link = built.link.clone().unwrap();
    println!(
        "REST build: {} bytes, link {} chars",
        built.manifest.len(),
        link.len()
    );

    let from_bytes = rest.decode_manifest(&built.manifest, true).await.unwrap();
    check_resolved(&env, &from_bytes);
    let from_link = rest.decode_manifest_link(&link, true).await.unwrap();
    check_resolved(&env, &from_link);
    assert_eq!(from_bytes, from_link);

    // A file link (bare address) is one public entry with no path.
    let file = rest
        .decode_manifest_link(&env.addresses[0], true)
        .await
        .unwrap();
    assert_eq!(file.source, "file_link");
    assert_eq!(file.entries.len(), 1);
    assert_eq!(file.entries[0].path, None);
    assert_eq!(file.entries[0].content_address, env.addresses[0]);
    if let Some(sizes) = env.sizes {
        assert_eq!(file.entries[0].exact_size, Some(sizes[0]));
    }

    // ── the fixture link ──
    let fixture = match &env.link {
        Some(l) => {
            let d = rest.decode_manifest_link(l, true).await.unwrap();
            check_fixture_link(&env, &d);
            println!(
                "fixture link: {} entries, name {:?}",
                d.entries.len(),
                d.name
            );
            Some(d)
        }
        None => None,
    };

    // ── bad entries ──
    // The daemon's check: an invalid path, named by index.
    let bad_path = [
        ManifestEntryInput::public(&env.addresses[0]),
        ManifestEntryInput::public(&env.addresses[1]).with_path("../x"),
    ];
    assert_bad_request(rest.build_manifest(&bad_path).await, "entries[1]");
    // The client's own check: both sources, refused before sending.
    let both = ManifestEntryInput {
        data_map: Some("00".into()),
        ..ManifestEntryInput::public(&env.addresses[0])
    };
    let client_msg = bad_request_message(rest.build_manifest(std::slice::from_ref(&both)).await);
    assert_eq!(
        client_msg,
        "1 invalid entries: entries[0]: give data_map or address, not both"
    );
    // The daemon refuses the same request, sent past the client's check, with
    // the same text: a client-side refusal is indistinguishable from it.
    let raw: serde_json::Value = {
        let resp = reqwest::Client::new()
            .post(format!(
                "{}/v1/manifests/build",
                env.rest.trim_end_matches('/')
            ))
            .json(&serde_json::json!({"entries": [
                {"data_map": "00", "address": env.addresses[0]}
            ]}))
            .send()
            .await
            .unwrap();
        assert_eq!(resp.status().as_u16(), 400);
        resp.json().await.unwrap()
    };
    let daemon_msg = raw["error"].as_str().unwrap();
    // REST's error text opens with "Bad request: " (the daemon's Display);
    // gRPC sends the bare text, as the client does.
    assert_eq!(
        daemon_msg
            .strip_prefix("Bad request: ")
            .unwrap_or(daemon_msg),
        client_msg
    );
    assert_eq!(
        bad_request_message(rest.decode_manifest(&[], false).await),
        "needs a manifest (base64 .ant bytes) or a link"
    );
    assert_bad_request(
        rest.decode_manifest(b"not a manifest", false).await,
        "manifest",
    );

    // ── gRPC ──
    let Some(endpoint) = &env.grpc else {
        eprintln!("live_manifests: ANTD_TEST_GRPC unset, skipping the gRPC half");
        return;
    };
    let grpc = GrpcClient::connect(endpoint).await.expect("grpc connect");
    let g_built = grpc
        .build_manifest_with_options(&entries, &options())
        .await
        .unwrap();
    check_built(&env, &g_built);
    // Both transports build through the same ant-core encoder.
    assert_eq!(
        g_built.manifest, built.manifest,
        "REST and gRPC bytes differ"
    );
    assert_eq!(g_built, built);

    let g_bytes = grpc.decode_manifest(&built.manifest, true).await.unwrap();
    check_resolved(&env, &g_bytes);
    assert_eq!(g_bytes, from_bytes);
    let g_link = grpc.decode_manifest_link(&link, true).await.unwrap();
    assert_eq!(g_link, from_link);
    if let (Some(l), Some(rest_fixture)) = (&env.link, &fixture) {
        let d = grpc.decode_manifest_link(l, true).await.unwrap();
        check_fixture_link(&env, &d);
        assert_eq!(&d, rest_fixture);
    }

    assert_bad_request(grpc.build_manifest(&bad_path).await, "entries[1]");
    assert_eq!(
        bad_request_message(grpc.build_manifest(&[both]).await),
        client_msg
    );
    assert_bad_request(
        grpc.decode_manifest(b"not a manifest", false).await,
        "manifest",
    );
    println!("live_manifests: REST and gRPC round trips OK");
}
