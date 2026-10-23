//! Manifest methods over a mock REST daemon (mockito) and a mock gRPC
//! `ManifestService`.

use std::sync::{Arc, Mutex};

use mockito::{Matcher, ServerGuard};
use serde_json::json;
use tonic::transport::Server;
use tonic::{Request, Response, Status};

use crate::errors::AntdError;
use crate::grpc_client::proto::antd::v1;
use crate::manifests::{
    BuildManifestOptions, ManifestEntryInput, MANIFEST_MAX_RECV_MESSAGE_BYTES,
    MANIFEST_MAX_SEND_MESSAGE_BYTES,
};
use crate::{Client, GrpcClient, DEFAULT_MAX_RECV_MESSAGE_BYTES};

/// The five-byte `.ant` header; "wUFOVAE=" is its base64.
const HEADER: &[u8] = &[0xC1, b'A', b'N', b'T', 0x01];
const HEADER_B64: &str = "wUFOVAE=";
const LINK: &str = "ant://manifest/wUFOVAE";
const ADDR: &str = "42424242424242424242424242424242424242424242424242424242424242aa";
/// SHA-256 of "hello\n".
const SHA: &str = "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03";

/// The daemon's 400 for a path that leaves the manifest root.
const BAD_PATH_MESSAGE: &str =
    "1 invalid entries: entries[0]: invalid path \"../x\": a component is \"..\"";

fn two_entries() -> Vec<ManifestEntryInput> {
    vec![
        ManifestEntryInput::embedded("abcd")
            .with_path("a.txt")
            .with_size(10)
            .with_sha256(SHA),
        ManifestEntryInput::public("11"),
    ]
}

async fn rest() -> (ServerGuard, Client) {
    let server = mockito::Server::new_async().await;
    let client = Client::new(&server.url());
    (server, client)
}

/// The call failed with `BadRequest` and exactly this message.
fn assert_bad_request<T: std::fmt::Debug>(r: Result<T, AntdError>, expected: &str) {
    match r {
        Err(AntdError::BadRequest(msg)) => assert_eq!(msg, expected),
        other => panic!("expected BadRequest({expected:?}), got {other:?}"),
    }
}

const EMPTY_DECODE: &str = "needs a manifest (base64 .ant bytes) or a link";

// --- REST ---

#[tokio::test]
async fn rest_build_manifest_sends_entries_and_options_and_returns_raw_bytes() {
    let (mut server, client) = rest().await;
    let m = server
        .mock("POST", "/v1/manifests/build")
        // Exact match: unset path, size and sha256 are omitted, not sent as
        // null, 0 or "".
        .match_body(Matcher::Json(json!({
            "name": "album",
            "torrent_info_hashes": ["aa"],
            "embed_roots": false,
            "entries": [
                {"path": "a.txt", "size": 10, "sha256": SHA, "data_map": "abcd"},
                {"address": "11"}
            ]
        })))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            json!({
                "manifest": HEADER_B64,
                "link": LINK,
                "entries": [
                    {"effective_name": "a.txt", "path": "a.txt", "size": 10, "sha256": SHA,
                     "kind": "embedded", "content_address": "cc", "exact_size": 10},
                    {"effective_name": "11", "kind": "public", "content_address": "11"}
                ]
            })
            .to_string(),
        )
        .create_async()
        .await;

    let opts = BuildManifestOptions {
        name: Some("album".into()),
        torrent_info_hashes: vec!["aa".into()],
        keep_shrunk_data_maps: true,
    };
    let built = client
        .build_manifest_with_options(&two_entries(), &opts)
        .await
        .unwrap();
    m.assert_async().await;

    assert_eq!(
        built.manifest, HEADER,
        "base64 must be decoded to raw bytes"
    );
    assert_eq!(built.link.as_deref(), Some(LINK));
    let (a, p) = (&built.entries[0], &built.entries[1]);
    assert_eq!(
        (a.kind.as_str(), a.size, a.exact_size, a.path.as_deref()),
        ("embedded", Some(10), Some(10), Some("a.txt"))
    );
    assert_eq!(a.content_address, "cc");
    assert_eq!(a.sha256.as_deref(), Some(SHA));
    assert_eq!(p.sha256, None);
    assert_eq!(
        (
            p.kind.as_str(),
            p.effective_name.as_str(),
            p.path.as_deref()
        ),
        ("public", "11", None)
    );
    // Absent sizes are None, never 0.
    assert_eq!((p.size, p.exact_size), (None, None));
    assert_eq!((p.data_map.as_deref(), p.error.as_deref()), (None, None));
}

#[tokio::test]
async fn rest_build_manifest_defaults_to_embedding_roots() {
    let (mut server, client) = rest().await;
    let m = server
        .mock("POST", "/v1/manifests/build")
        // No name, no torrent hashes, embed_roots sent as true; an empty path
        // or name counts as unset and is omitted.
        .match_body(Matcher::Json(json!({
            "embed_roots": true,
            "entries": [{"address": "11"}]
        })))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"manifest": "wUFOVAE=", "entries": []}"#)
        .expect(2)
        .create_async()
        .await;

    let built = client
        .build_manifest(&[ManifestEntryInput::public("11")])
        .await
        .unwrap();
    // A link that does not fit 1,500 bytes is omitted: None.
    assert_eq!(built.link, None);
    assert_eq!(built.manifest, HEADER);

    let empty = BuildManifestOptions {
        name: Some(String::new()),
        ..Default::default()
    };
    client
        .build_manifest_with_options(&[ManifestEntryInput::public("11").with_path("")], &empty)
        .await
        .unwrap();
    m.assert_async().await;
}

#[tokio::test]
async fn rest_build_manifest_rejects_both_or_neither_before_sending() {
    let (mut server, client) = rest().await;
    let never = server
        .mock("POST", Matcher::Any)
        .expect(0)
        .create_async()
        .await;
    let both = ManifestEntryInput {
        data_map: Some("aa".into()),
        address: Some("bb".into()),
        ..Default::default()
    };
    let neither = ManifestEntryInput::default().with_path("x");
    // Empty strings are unset, so this one is "neither" too.
    let empty = ManifestEntryInput {
        data_map: Some(String::new()),
        address: Some(String::new()),
        ..Default::default()
    };
    for (bad, why) in [
        (both.clone(), "give data_map or address, not both"),
        (neither.clone(), "needs a data_map or an address"),
        (empty, "needs a data_map or an address"),
    ] {
        let entries = [ManifestEntryInput::public("11"), bad];
        assert_bad_request(
            client.build_manifest(&entries).await,
            &format!("1 invalid entries: entries[1]: {why}"),
        );
    }
    // Every bad entry is named, in the daemon's wording.
    let entries = [both.clone(), ManifestEntryInput::public("11"), neither];
    assert_bad_request(
        client.build_manifest(&entries).await,
        "2 invalid entries: entries[0]: give data_map or address, not both; entries[2]: needs a data_map or an address",
    );
    // At most 20 are shown, then a count of the rest.
    let many = vec![both; 25];
    let shown = (0..20)
        .map(|i| format!("entries[{i}]: give data_map or address, not both"))
        .collect::<Vec<_>>()
        .join("; ");
    assert_bad_request(
        client.build_manifest(&many).await,
        &format!("25 invalid entries: {shown}; and 5 more"),
    );
    never.assert_async().await;
}

#[tokio::test]
async fn rest_build_manifest_bad_request_keeps_the_daemon_message() {
    let (mut server, client) = rest().await;
    server
        .mock("POST", "/v1/manifests/build")
        .with_status(400)
        .with_header("content-type", "application/json")
        .with_body(json!({"error": BAD_PATH_MESSAGE, "code": "BAD_REQUEST"}).to_string())
        .create_async()
        .await;
    match client
        .build_manifest(&[ManifestEntryInput::public(ADDR).with_path("../x")])
        .await
    {
        Err(AntdError::BadRequest(msg)) => assert_eq!(msg, BAD_PATH_MESSAGE),
        other => panic!("expected BadRequest, got {other:?}"),
    }
}

#[tokio::test]
async fn rest_build_manifest_rejects_a_response_that_is_not_base64() {
    let (mut server, client) = rest().await;
    server
        .mock("POST", "/v1/manifests/build")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"manifest": "not base64!", "entries": []}"#)
        .create_async()
        .await;
    assert!(matches!(
        client.build_manifest(&[ManifestEntryInput::public("11")]).await,
        Err(AntdError::Internal(m)) if m.contains("not valid base64")
    ));
}

#[tokio::test]
async fn rest_decode_manifest_sends_base64_and_reads_entries() {
    let (mut server, client) = rest().await;
    let m = server
        .mock("POST", "/v1/manifests/decode")
        .match_body(Matcher::Json(
            json!({"manifest": HEADER_B64, "resolve": true}),
        ))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            json!({
                "source": "manifest", "name": "album", "torrent_info_hash_v2": "bb",
                "entries": [
                    {"effective_name": "a.txt", "path": "a.txt", "kind": "embedded",
                     "content_address": "cc", "data_map": "abcd", "exact_size": 3},
                    {"effective_name": "b", "path": "b", "kind": "public",
                     "content_address": "dd", "error": "Record not found: gone"},
                    {"effective_name": "c", "path": "c", "size": 0, "kind": "public",
                     "content_address": "ee", "exact_size": 0}
                ]
            })
            .to_string(),
        )
        .create_async()
        .await;

    let d = client.decode_manifest(HEADER, true).await.unwrap();
    m.assert_async().await;
    assert_eq!(d.source, "manifest");
    assert_eq!(d.name.as_deref(), Some("album"));
    assert_eq!(d.torrent_info_hash_v1, None);
    assert_eq!(d.torrent_info_hash_v2.as_deref(), Some("bb"));

    let (a, b, c) = (&d.entries[0], &d.entries[1], &d.entries[2]);
    assert_eq!(a.data_map.as_deref(), Some("abcd"));
    assert_eq!((a.size, a.exact_size), (None, Some(3)));
    // A failed resolve is the entry's error, not a failed call; its sizes
    // stay unset.
    assert_eq!(b.error.as_deref(), Some("Record not found: gone"));
    assert_eq!(
        (b.size, b.exact_size, b.data_map.as_deref()),
        (None, None, None)
    );
    // A recorded 0 is a real size, distinct from unset.
    assert_eq!((c.size, c.exact_size), (Some(0), Some(0)));
}

#[tokio::test]
async fn rest_decode_manifest_link_sends_the_link_only() {
    let (mut server, client) = rest().await;
    let m = server
        .mock("POST", "/v1/manifests/decode")
        .match_body(Matcher::Json(json!({"link": ADDR, "resolve": false})))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            json!({
                "source": "file_link",
                "entries": [{"effective_name": ADDR, "kind": "public", "content_address": ADDR}]
            })
            .to_string(),
        )
        .create_async()
        .await;
    let d = client.decode_manifest_link(ADDR, false).await.unwrap();
    m.assert_async().await;
    assert_eq!(d.source, "file_link");
    assert_eq!(d.name, None);
    assert_eq!(d.entries.len(), 1);
    assert_eq!(d.entries[0].path, None);
    assert_eq!(d.entries[0].content_address, ADDR);
}

#[tokio::test]
async fn rest_decode_manifest_bad_request_and_empty_input() {
    let (mut server, client) = rest().await;
    let m = server
        .mock("POST", "/v1/manifests/decode")
        .with_status(400)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{"error": "Bad request: not a manifest: missing or invalid header", "code": "BAD_REQUEST"}"#,
        )
        .expect(1)
        .create_async()
        .await;
    match client.decode_manifest(b"nope", false).await {
        Err(AntdError::BadRequest(msg)) => assert!(msg.contains("not a manifest"), "{msg}"),
        other => panic!("expected BadRequest, got {other:?}"),
    }
    // Empty input is refused before sending.
    assert_bad_request(client.decode_manifest(&[], false).await, EMPTY_DECODE);
    assert_bad_request(client.decode_manifest_link("", false).await, EMPTY_DECODE);
    m.assert_async().await;
}

// --- gRPC ---

/// Records every request and answers like the daemon. A build named "big"
/// returns a manifest of [`BIG`] bytes; an entry with the path `../x` is
/// refused with `INVALID_ARGUMENT`.
#[derive(Clone, Default)]
struct MockManifests {
    builds: Arc<Mutex<Vec<v1::BuildManifestRequest>>>,
    decodes: Arc<Mutex<Vec<v1::DecodeManifestRequest>>>,
}

/// Over the SDK's 32 MiB default ceiling, so only a stub with its own,
/// larger ceiling can take it.
const BIG: usize = 40 * 1024 * 1024;

#[tonic::async_trait]
impl v1::manifest_service_server::ManifestService for MockManifests {
    async fn build(
        &self,
        request: Request<v1::BuildManifestRequest>,
    ) -> Result<Response<v1::BuildManifestResponse>, Status> {
        let req = request.into_inner();
        self.builds.lock().unwrap().push(req.clone());
        if req
            .entries
            .iter()
            .any(|e| e.path.as_deref() == Some("../x"))
        {
            return Err(Status::invalid_argument(BAD_PATH_MESSAGE));
        }
        if req.name.as_deref() == Some("big") {
            return Ok(Response::new(v1::BuildManifestResponse {
                manifest: vec![7; BIG],
                ..Default::default()
            }));
        }
        Ok(Response::new(v1::BuildManifestResponse {
            manifest: HEADER.to_vec(),
            link: LINK.into(),
            entries: vec![
                v1::ManifestEntryInfo {
                    effective_name: "a.txt".into(),
                    path: Some("a.txt".into()),
                    size: Some(10),
                    sha256: SHA.into(),
                    kind: "embedded".into(),
                    content_address: "cc".into(),
                    exact_size: Some(10),
                    ..Default::default()
                },
                v1::ManifestEntryInfo {
                    effective_name: "11".into(),
                    kind: "public".into(),
                    content_address: "11".into(),
                    ..Default::default()
                },
            ],
        }))
    }

    async fn decode(
        &self,
        request: Request<v1::DecodeManifestRequest>,
    ) -> Result<Response<v1::DecodeManifestResponse>, Status> {
        let req = request.into_inner();
        let resolve = req.resolve;
        let resp = match &req.input {
            Some(v1::decode_manifest_request::Input::Manifest(bytes)) => {
                if bytes.len() < BIG && bytes.as_slice() != HEADER {
                    return Err(Status::invalid_argument(
                        "not a manifest: missing or invalid header",
                    ));
                }
                v1::DecodeManifestResponse {
                    source: "manifest".into(),
                    name: Some("bytes".into()),
                    torrent_info_hash_v1: if resolve {
                        "resolved".into()
                    } else {
                        String::new()
                    },
                    entries: vec![
                        v1::ManifestEntryInfo {
                            effective_name: "a.txt".into(),
                            path: Some("a.txt".into()),
                            kind: "embedded".into(),
                            content_address: "cc".into(),
                            data_map: "abcd".into(),
                            exact_size: Some(3),
                            ..Default::default()
                        },
                        v1::ManifestEntryInfo {
                            effective_name: "b".into(),
                            path: Some("b".into()),
                            size: Some(0),
                            kind: "public".into(),
                            content_address: "dd".into(),
                            error: "Record not found: gone".into(),
                            ..Default::default()
                        },
                    ],
                    ..Default::default()
                }
            }
            Some(v1::decode_manifest_request::Input::Link(link)) => v1::DecodeManifestResponse {
                source: "file_link".into(),
                entries: vec![v1::ManifestEntryInfo {
                    effective_name: link.clone(),
                    kind: "public".into(),
                    content_address: link.clone(),
                    ..Default::default()
                }],
                ..Default::default()
            },
            None => return Err(Status::invalid_argument("needs a manifest or a link")),
        };
        // Keep the request, minus a large manifest's bytes.
        let mut kept = req;
        if let Some(v1::decode_manifest_request::Input::Manifest(bytes)) = &mut kept.input {
            if bytes.len() >= BIG {
                bytes.truncate(1);
            }
        }
        self.decodes.lock().unwrap().push(kept);
        Ok(Response::new(resp))
    }
}

/// Serves `mock` with a 200 MiB request ceiling, above the client's own, so
/// a send-side failure can only come from the client.
async fn grpc_endpoint(mock: MockManifests) -> String {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        Server::builder()
            .add_service(
                v1::manifest_service_server::ManifestServiceServer::new(mock)
                    .max_decoding_message_size(200 * 1024 * 1024),
            )
            .serve_with_incoming(tokio_stream::wrappers::TcpListenerStream::new(listener))
            .await
            .unwrap();
    });
    format!("http://{addr}")
}

async fn grpc(mock: &MockManifests) -> GrpcClient {
    GrpcClient::connect(&grpc_endpoint(mock.clone()).await)
        .await
        .unwrap()
}

#[tokio::test]
async fn grpc_build_manifest_sends_presence_and_reads_optional_sizes() {
    let mock = MockManifests::default();
    let client = grpc(&mock).await;
    let opts = BuildManifestOptions {
        name: Some("album".into()),
        torrent_info_hashes: vec!["aa".into()],
        ..Default::default()
    };
    let built = client
        .build_manifest_with_options(&two_entries(), &opts)
        .await
        .unwrap();

    let req = mock.builds.lock().unwrap().pop().unwrap();
    assert_eq!(req.name.as_deref(), Some("album"));
    assert_eq!(req.torrent_info_hashes, ["aa"]);
    // Sent explicitly, as the default: embed roots.
    assert_eq!(req.embed_roots, Some(true));
    let (first, second) = (&req.entries[0], &req.entries[1]);
    assert_eq!(
        (first.path.as_deref(), first.size, first.sha256.as_deref()),
        (Some("a.txt"), Some(10), Some(SHA))
    );
    assert_eq!(
        first.source,
        Some(v1::manifest_entry_input::Source::DataMap("abcd".into()))
    );
    // Unset path, size and sha256 have no presence on the wire, not "" and 0.
    assert_eq!(
        (
            second.path.as_deref(),
            second.size,
            second.sha256.as_deref()
        ),
        (None, None, None)
    );
    assert_eq!(
        second.source,
        Some(v1::manifest_entry_input::Source::Address("11".into()))
    );

    // gRPC carries raw bytes: no base64 on either side.
    assert_eq!(built.manifest, HEADER);
    assert_eq!(built.link.as_deref(), Some(LINK));
    assert_eq!(
        (built.entries[0].size, built.entries[0].exact_size),
        (Some(10), Some(10))
    );
    assert_eq!(built.entries[0].sha256.as_deref(), Some(SHA));
    let p = &built.entries[1];
    assert_eq!(
        (p.size, p.exact_size, p.path.as_deref()),
        (None, None, None)
    );
    assert_eq!((p.data_map.as_deref(), p.error.as_deref()), (None, None));
    // The empty proto string reads as unset.
    assert_eq!(p.sha256, None);
}

#[tokio::test]
async fn grpc_build_manifest_keep_shrunk_sends_embed_roots_false() {
    let mock = MockManifests::default();
    let client = grpc(&mock).await;
    let opts = BuildManifestOptions {
        keep_shrunk_data_maps: true,
        ..Default::default()
    };
    client
        .build_manifest_with_options(&[ManifestEntryInput::public("11")], &opts)
        .await
        .unwrap();
    client
        .build_manifest(&[ManifestEntryInput::public("11")])
        .await
        .unwrap();
    let builds = mock.builds.lock().unwrap();
    assert_eq!(builds[0].embed_roots, Some(false));
    assert_eq!(builds[0].name, None);
    assert_eq!(builds[1].embed_roots, Some(true));
}

#[tokio::test]
async fn grpc_build_manifest_rejects_both_or_neither_before_sending() {
    let mock = MockManifests::default();
    let client = grpc(&mock).await;
    let both = ManifestEntryInput {
        data_map: Some("aa".into()),
        address: Some("bb".into()),
        ..Default::default()
    };
    assert_bad_request(
        client.build_manifest(&[both]).await,
        "1 invalid entries: entries[0]: give data_map or address, not both",
    );
    assert_bad_request(
        client
            .build_manifest(&[ManifestEntryInput::default()])
            .await,
        "1 invalid entries: entries[0]: needs a data_map or an address",
    );
    assert!(mock.builds.lock().unwrap().is_empty());
}

#[tokio::test]
async fn grpc_invalid_argument_is_bad_request_with_the_daemon_message() {
    let mock = MockManifests::default();
    let client = grpc(&mock).await;
    match client
        .build_manifest(&[ManifestEntryInput::public(ADDR).with_path("../x")])
        .await
    {
        Err(AntdError::BadRequest(msg)) => assert_eq!(msg, BAD_PATH_MESSAGE),
        other => panic!("expected BadRequest, got {other:?}"),
    }
    match client.decode_manifest(b"nope", false).await {
        Err(AntdError::BadRequest(msg)) => assert!(msg.contains("not a manifest"), "{msg}"),
        other => panic!("expected BadRequest, got {other:?}"),
    }
}

#[tokio::test]
async fn grpc_decode_manifest_and_link() {
    let mock = MockManifests::default();
    let client = grpc(&mock).await;

    let d = client.decode_manifest(HEADER, true).await.unwrap();
    assert_eq!(d.source, "manifest");
    assert_eq!(d.name.as_deref(), Some("bytes"));
    assert_eq!(d.torrent_info_hash_v1.as_deref(), Some("resolved"));
    assert_eq!(d.torrent_info_hash_v2, None);
    let (a, b) = (&d.entries[0], &d.entries[1]);
    assert_eq!(a.data_map.as_deref(), Some("abcd"));
    assert_eq!((a.size, a.exact_size), (None, Some(3)));
    assert_eq!(b.error.as_deref(), Some("Record not found: gone"));
    // Present-but-zero is Some(0); absent is None.
    assert_eq!((b.size, b.exact_size), (Some(0), None));

    let l = client.decode_manifest_link(ADDR, false).await.unwrap();
    assert_eq!(l.source, "file_link");
    assert_eq!(l.torrent_info_hash_v1, None);
    assert_eq!(l.entries.len(), 1);
    assert_eq!(l.entries[0].content_address, ADDR);
    assert_eq!(l.entries[0].path, None);

    {
        let decodes = mock.decodes.lock().unwrap();
        assert_eq!(
            decodes[0].input,
            Some(v1::decode_manifest_request::Input::Manifest(
                HEADER.to_vec()
            ))
        );
        assert!(decodes[0].resolve);
        assert_eq!(
            decodes[1].input,
            Some(v1::decode_manifest_request::Input::Link(ADDR.into()))
        );
        assert!(!decodes[1].resolve);
    }
    assert_bad_request(client.decode_manifest(&[], true).await, EMPTY_DECODE);
    assert_bad_request(client.decode_manifest_link("", true).await, EMPTY_DECODE);
    assert_eq!(mock.decodes.lock().unwrap().len(), 2);
}

/// The ManifestService stub has its own receive ceiling: a 40 MiB manifest,
/// over tonic's 4 MiB default and the SDK's 32 MiB one, decodes on a default
/// client and on one connected with a 1 MiB ceiling for everything else.
#[tokio::test]
async fn grpc_manifest_receive_ceiling_is_raised() {
    const {
        assert!(BIG > DEFAULT_MAX_RECV_MESSAGE_BYTES);
        assert!(MANIFEST_MAX_RECV_MESSAGE_BYTES >= 64 * 1024 * 1024 * 2);
    }
    let mock = MockManifests::default();
    let endpoint = grpc_endpoint(mock.clone()).await;
    let big = BuildManifestOptions {
        name: Some("big".into()),
        ..Default::default()
    };
    let entries = [ManifestEntryInput::public("11")];

    let default = GrpcClient::connect(&endpoint).await.unwrap();
    let built = default
        .build_manifest_with_options(&entries, &big)
        .await
        .expect("a 40 MiB build response must fit the manifest stub's ceiling");
    assert_eq!(built.manifest.len(), BIG);

    let small = GrpcClient::connect_with_max_message_size(&endpoint, 1024 * 1024)
        .await
        .unwrap();
    let built = small
        .build_manifest_with_options(&entries, &big)
        .await
        .expect("a lower client-wide ceiling must not cap the manifest stub");
    assert_eq!(built.manifest.len(), BIG);
}

/// Decode sends the bytes: 40 MiB goes out, and a request over the daemon's
/// 100 MiB limit fails in the client. The mock server takes up to 200 MiB,
/// so only the stub's own send ceiling can stop it. (tonic reports the
/// refused send as a reset stream, not as `OUT_OF_RANGE`.)
#[tokio::test]
async fn grpc_manifest_send_ceiling_matches_the_daemon() {
    let mock = MockManifests::default();
    let client = grpc(&mock).await;

    client
        .decode_manifest(&vec![1; BIG], false)
        .await
        .expect("a 40 MiB decode request must go out");
    assert_eq!(mock.decodes.lock().unwrap().len(), 1);

    // One byte of field tag and four of length push this over the limit.
    let over = vec![1; MANIFEST_MAX_SEND_MESSAGE_BYTES];
    assert!(matches!(
        client.decode_manifest(&over, false).await,
        Err(AntdError::Grpc(_))
    ));
    // The server never saw it.
    assert_eq!(mock.decodes.lock().unwrap().len(), 1);
}
