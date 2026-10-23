use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use mockito::{Matcher, Mock, ServerGuard};
use serde_json::json;

use crate::errors::{error_for_body, parse_partial_upload_message, AntdError};
use crate::models::{
    PaymentMode, PointerController, PointerFinalityStatus, PointerKind, PointerOp, PointerResolved,
    PointerWriteResult, PrepareOptions, VerifyQuoteEntry,
};
use crate::Client;

async fn mock_server() -> ServerGuard {
    mockito::Server::new_async().await
}

fn mock_health(server: &mut ServerGuard) -> Mock {
    server
        .mock("GET", "/health")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
                "status":"ok",
                "network":"local",
                "version":"0.4.0",
                "evm_network":"local",
                "uptime_seconds":42,
                "build_commit":"abcdef123456",
                "payment_token_address":"0xtoken",
                "payment_vault_address":"0xvault"
            }"#,
        )
        .create()
}

fn mock_data_put_public(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/data/public")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"cost":"100","address":"abc123"}"#)
        .create()
}

fn mock_data_get_public(server: &mut ServerGuard) -> Mock {
    let encoded = BASE64.encode(b"hello");
    server
        .mock("GET", "/v1/data/public/abc123")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(format!(r#"{{"data":"{encoded}"}}"#))
        .create()
}

fn mock_data_put_private(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/data")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"cost":"200","data_map":"dm123"}"#)
        .create()
}

fn mock_data_get_private(server: &mut ServerGuard) -> Mock {
    let encoded = BASE64.encode(b"secret");
    server
        .mock("POST", "/v1/data/get")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(format!(r#"{{"data":"{encoded}"}}"#))
        .create()
}

fn mock_data_cost(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/data/cost")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"cost":"50","file_size":4,"chunk_count":3,"estimated_gas_cost_wei":"150000000000000","payment_mode":"single"}"#)
        .create()
}

fn mock_chunk_put(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/chunks")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"cost":"10","address":"chunk1"}"#)
        .create()
}

fn mock_chunk_get(server: &mut ServerGuard) -> Mock {
    let encoded = BASE64.encode(b"chunkdata");
    server
        .mock("GET", "/v1/chunks/chunk1")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(format!(r#"{{"data":"{encoded}"}}"#))
        .create()
}

fn mock_file_upload_public(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/files/public")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"address":"file1","storage_cost_atto":"1000","gas_cost_wei":"42","chunks_stored":3,"payment_mode_used":"auto"}"#)
        .create()
}

fn mock_file_download_public(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/files/public/get")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body("")
        .create()
}

fn mock_file_cost(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/files/cost")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"cost":"1000","file_size":4096,"chunk_count":3,"estimated_gas_cost_wei":"150000000000000","payment_mode":"auto"}"#)
        .create()
}

fn mock_prepare_upload_merkle(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/upload/prepare")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "upload_id": "up123",
            "payments": [],
            "total_amount": "5000",
            "payment_vault_address": "0xMP",
            "payment_token_address": "0xPT",
            "rpc_url": "http://rpc.local",
            "payment_type": "merkle",
            "depth": 4,
            "pool_commitments": [
                {
                    "pool_hash": "0xpool1",
                    "candidates": [
                        {"rewards_address": "0xnode1", "amount": "1000"},
                        {"rewards_address": "0xnode2", "amount": "2000"}
                    ]
                },
                {
                    "pool_hash": "0xpool2",
                    "candidates": [
                        {"rewards_address": "0xnode3", "amount": "2000"}
                    ]
                }
            ],
            "merkle_payment_timestamp": 1700000000,
            "total_chunks": 128,
            "already_stored_count": 4
        }"#,
        )
        .create()
}

fn mock_finalize_merkle_upload(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/upload/finalize")
        .match_body(Matcher::JsonString(
            r#"{"upload_id":"up123","winner_pool_hash":"0xpool1","store_data_map":true}"#
                .to_string(),
        ))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"address":"addr456","chunks_stored":10}"#)
        .create()
}

fn mock_prepare_upload_legacy(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/upload/prepare")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "upload_id": "up_old",
            "payments": [{"quote_hash":"qh1","rewards_address":"0xr1","amount":"100"}],
            "total_amount": "100",
            "payment_vault_address": "0xDP",
            "payment_token_address": "0xPT",
            "rpc_url": "http://rpc.local"
        }"#,
        )
        .create()
}

#[tokio::test]
async fn test_health() {
    let mut server = mock_server().await;
    let _m = mock_health(&mut server);
    let client = Client::new(&server.url());

    let health = client.health().await.unwrap();
    assert!(health.ok);
    assert_eq!(health.network, "local");
    assert_eq!(health.version, "0.4.0");
    assert_eq!(health.evm_network, "local");
    assert_eq!(health.uptime_seconds, 42);
    assert_eq!(health.build_commit, "abcdef123456");
    assert_eq!(health.payment_token_address, "0xtoken");
    assert_eq!(health.payment_vault_address, "0xvault");
}

#[tokio::test]
async fn test_data_put_public() {
    let mut server = mock_server().await;
    let _m = mock_data_put_public(&mut server);
    let client = Client::new(&server.url());

    let result = client
        .data_put_public(b"hello", PaymentMode::Auto)
        .await
        .unwrap();
    assert_eq!(result.address, "abc123");
}

#[tokio::test]
async fn test_data_get_public() {
    let mut server = mock_server().await;
    let _m = mock_data_get_public(&mut server);
    let client = Client::new(&server.url());

    let data = client.data_get_public("abc123").await.unwrap();
    assert_eq!(data, b"hello");
}

#[tokio::test]
async fn test_data_put_private() {
    let mut server = mock_server().await;
    let _m = mock_data_put_private(&mut server);
    let client = Client::new(&server.url());

    let result = client.data_put(b"secret", PaymentMode::Auto).await.unwrap();
    assert_eq!(result.data_map, "dm123");
}

#[tokio::test]
async fn test_data_get_private() {
    let mut server = mock_server().await;
    let _m = mock_data_get_private(&mut server);
    let client = Client::new(&server.url());

    let data = client.data_get("dm123").await.unwrap();
    assert_eq!(data, b"secret");
}

fn mock_data_stream_private(server: &mut ServerGuard) -> Mock {
    // Streaming endpoint returns raw decrypted bytes (NOT base64/JSON).
    server
        .mock("POST", "/v1/data/stream")
        .match_body(Matcher::Json(json!({"data_map": "dm123"})))
        .with_status(200)
        .with_header("content-type", "application/octet-stream")
        .with_header("content-length", "6")
        .with_body("secret")
        .create()
}

fn mock_data_stream_public(server: &mut ServerGuard) -> Mock {
    server
        .mock("GET", "/v1/data/public/abc123/stream")
        .with_status(200)
        .with_header("content-type", "application/octet-stream")
        .with_header("content-length", "5")
        .with_body("hello")
        .create()
}

async fn collect_stream(
    stream: impl tokio_stream::Stream<Item = Result<bytes::Bytes, reqwest::Error>>,
) -> Vec<u8> {
    use tokio_stream::StreamExt;
    let mut out = Vec::new();
    tokio::pin!(stream);
    while let Some(chunk) = stream.next().await {
        out.extend_from_slice(&chunk.unwrap());
    }
    out
}

#[tokio::test]
async fn test_data_stream_private() {
    let mut server = mock_server().await;
    let _m = mock_data_stream_private(&mut server);
    let client = Client::new(&server.url());

    let stream = client.data_stream("dm123").await.unwrap();
    let data = collect_stream(stream).await;
    assert_eq!(data, b"secret");
}

#[tokio::test]
async fn test_data_stream_public() {
    let mut server = mock_server().await;
    let _m = mock_data_stream_public(&mut server);
    let client = Client::new(&server.url());

    let stream = client.data_stream_public("abc123").await.unwrap();
    let data = collect_stream(stream).await;
    assert_eq!(data, b"hello");
}

#[tokio::test]
async fn test_data_stream_with_progress_parses_ndjson() {
    use crate::DownloadFrame;
    use tokio_stream::StreamExt;

    // Daemon NDJSON framing: a leading meta line (byte denominator), then
    // interleaved progress + base64 data frames.
    let body = concat!(
        "{\"type\":\"meta\",\"total_size\":6}\n",
        "{\"type\":\"progress\",\"phase\":\"fetching\",\"fetched\":1,\"total\":2}\n",
        "{\"type\":\"data\",\"chunk\":\"c2Vj\"}\n",
        "{\"type\":\"progress\",\"phase\":\"fetching\",\"fetched\":2,\"total\":2}\n",
        "{\"type\":\"data\",\"chunk\":\"cmV0\"}\n",
    );
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/data/stream")
        .match_header("accept", "application/x-ndjson")
        .match_body(Matcher::Json(json!({"data_map": "dm123"})))
        .with_status(200)
        .with_header("content-type", "application/x-ndjson")
        .with_body(body)
        .create();
    let client = Client::new(&server.url());

    let stream = client.data_stream_with_progress("dm123").await.unwrap();
    tokio::pin!(stream);
    let mut data = Vec::new();
    let mut progress = Vec::new();
    let mut total = None;
    while let Some(item) = stream.next().await {
        match item.unwrap() {
            DownloadFrame::Meta(t) => total = Some(t),
            DownloadFrame::Data(b) => data.extend_from_slice(&b),
            DownloadFrame::Progress(p) => progress.push(p),
        }
    }
    // Data frames reassemble to the payload; the meta line surfaces as the byte
    // denominator; both progress frames surface separately.
    assert_eq!(data, b"secret");
    assert_eq!(total, Some(6));
    assert_eq!(progress.len(), 2);
    assert_eq!(progress[0].phase, "fetching");
    assert_eq!(progress[0].fetched, 1);
    assert_eq!(progress[1].fetched, 2);
    assert_eq!(progress[1].total, 2);
}

#[tokio::test]
async fn test_data_stream_with_progress_surfaces_error_frame() {
    use tokio_stream::StreamExt;

    // A terminal `error` frame mid-stream must surface as a stream error
    // (NDJSON can signal failure explicitly, unlike the raw short-read path).
    let body = concat!(
        "{\"type\":\"meta\",\"total_size\":10}\n",
        "{\"type\":\"data\",\"chunk\":\"c2Vj\"}\n",
        "{\"type\":\"error\",\"message\":\"network: peer timeout\"}\n",
    );
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/data/stream")
        .match_header("accept", "application/x-ndjson")
        .with_status(200)
        .with_header("content-type", "application/x-ndjson")
        .with_body(body)
        .create();
    let client = Client::new(&server.url());

    let stream = client.data_stream_with_progress("dm123").await.unwrap();
    tokio::pin!(stream);
    let mut saw_error = false;
    while let Some(item) = stream.next().await {
        if let Err(AntdError::Internal(msg)) = item {
            assert!(msg.contains("peer timeout"));
            saw_error = true;
        }
    }
    assert!(saw_error, "expected a terminal error frame to surface");
}

#[tokio::test]
async fn test_data_stream_private_error_mapping() {
    // A non-2xx JSON error body is surfaced before any stream item.
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/data/stream")
        .with_status(404)
        .with_header("content-type", "application/json")
        .with_body(r#"{"error":"data map not found","code":"not_found"}"#)
        .create();
    let client = Client::new(&server.url());

    // Can't `unwrap_err()` — the Ok variant (impl Stream) is not Debug.
    match client.data_stream("missing").await {
        Err(AntdError::NotFound(msg)) => assert_eq!(msg, "data map not found"),
        Err(other) => panic!("expected NotFound, got: {other:?}"),
        Ok(_) => panic!("expected NotFound error, got Ok stream"),
    }
}

#[tokio::test]
async fn test_data_stream_public_error_mapping() {
    let mut server = mock_server().await;
    let _m = server
        .mock("GET", "/v1/data/public/missing/stream")
        .with_status(404)
        .with_header("content-type", "application/json")
        .with_body(r#"{"error":"address not found","code":"not_found"}"#)
        .create();
    let client = Client::new(&server.url());

    match client.data_stream_public("missing").await {
        Err(AntdError::NotFound(msg)) => assert_eq!(msg, "address not found"),
        Err(other) => panic!("expected NotFound, got: {other:?}"),
        Ok(_) => panic!("expected NotFound error, got Ok stream"),
    }
}

#[tokio::test]
async fn test_data_cost() {
    let mut server = mock_server().await;
    let _m = mock_data_cost(&mut server);
    let client = Client::new(&server.url());

    let est = client.data_cost(b"test", PaymentMode::Auto).await.unwrap();
    assert_eq!(est.cost, "50");
    assert_eq!(est.file_size, 4);
    assert_eq!(est.chunk_count, 3);
    assert_eq!(est.estimated_gas_cost_wei, "150000000000000");
    assert_eq!(est.payment_mode, "single");
}

#[tokio::test]
async fn test_chunk_put() {
    let mut server = mock_server().await;
    let _m = mock_chunk_put(&mut server);
    let client = Client::new(&server.url());

    let result = client.chunk_put(b"chunkdata").await.unwrap();
    assert_eq!(result.address, "chunk1");
    assert_eq!(result.cost, "10");
}

#[tokio::test]
async fn test_chunk_get() {
    let mut server = mock_server().await;
    let _m = mock_chunk_get(&mut server);
    let client = Client::new(&server.url());

    let data = client.chunk_get("chunk1").await.unwrap();
    assert_eq!(data, b"chunkdata");
}

#[tokio::test]
async fn test_file_upload_public() {
    let mut server = mock_server().await;
    let _m = mock_file_upload_public(&mut server);
    let client = Client::new(&server.url());

    let result = client
        .file_put_public("/tmp/test.txt", PaymentMode::Auto)
        .await
        .unwrap();
    assert_eq!(result.address, "file1");
    assert_eq!(result.storage_cost_atto, "1000");
    assert_eq!(result.gas_cost_wei, "42");
    assert_eq!(result.chunks_stored, 3);
    assert_eq!(result.payment_mode_used, "auto");
}

#[tokio::test]
async fn test_file_download_public() {
    let mut server = mock_server().await;
    let _m = mock_file_download_public(&mut server);
    let client = Client::new(&server.url());

    client
        .file_get_public("file1", "/tmp/out.txt")
        .await
        .unwrap();
}

#[tokio::test]
async fn test_file_cost() {
    let mut server = mock_server().await;
    let _m = mock_file_cost(&mut server);
    let client = Client::new(&server.url());

    let est = client
        .file_cost("/tmp/test.txt", true, PaymentMode::Auto)
        .await
        .unwrap();
    assert_eq!(est.cost, "1000");
    assert_eq!(est.file_size, 4096);
    assert_eq!(est.chunk_count, 3);
    assert_eq!(est.estimated_gas_cost_wei, "150000000000000");
    assert_eq!(est.payment_mode, "auto");
}

#[tokio::test]
async fn test_error_mapping_not_found() {
    let mut server = mock_server().await;
    let _m = server
        .mock("GET", "/health")
        .with_status(404)
        .with_header("content-type", "application/json")
        .with_body(r#"{"error":"not found"}"#)
        .create();
    let client = Client::new(&server.url());

    let err = client.health().await.unwrap_err();
    match err {
        AntdError::NotFound(msg) => assert_eq!(msg, "not found"),
        other => panic!("expected NotFound, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_error_mapping_bad_request() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/data/public")
        .with_status(400)
        .with_header("content-type", "application/json")
        .with_body(r#"{"error":"invalid data"}"#)
        .create();
    let client = Client::new(&server.url());

    let err = client
        .data_put_public(b"bad", PaymentMode::Auto)
        .await
        .unwrap_err();
    match err {
        AntdError::BadRequest(msg) => assert_eq!(msg, "invalid data"),
        other => panic!("expected BadRequest, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_error_mapping_payment() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/data/public")
        .with_status(402)
        .with_header("content-type", "application/json")
        .with_body(r#"{"error":"insufficient funds"}"#)
        .create();
    let client = Client::new(&server.url());

    let err = client
        .data_put_public(b"data", PaymentMode::Auto)
        .await
        .unwrap_err();
    match err {
        AntdError::Payment(msg) => assert_eq!(msg, "insufficient funds"),
        other => panic!("expected Payment, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_error_mapping_too_large() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/chunks")
        .with_status(413)
        .with_header("content-type", "application/json")
        .with_body(r#"{"error":"payload too large"}"#)
        .create();
    let client = Client::new(&server.url());

    let err = client.chunk_put(b"big").await.unwrap_err();
    match err {
        AntdError::TooLarge(msg) => assert_eq!(msg, "payload too large"),
        other => panic!("expected TooLarge, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_error_mapping_internal() {
    let mut server = mock_server().await;
    let _m = server
        .mock("GET", "/health")
        .with_status(500)
        .with_header("content-type", "application/json")
        .with_body(r#"{"error":"server error"}"#)
        .create();
    let client = Client::new(&server.url());

    let err = client.health().await.unwrap_err();
    match err {
        AntdError::Internal(msg) => assert_eq!(msg, "server error"),
        other => panic!("expected Internal, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_error_mapping_network() {
    let mut server = mock_server().await;
    let _m = server
        .mock("GET", "/health")
        .with_status(502)
        .with_header("content-type", "application/json")
        .with_body(r#"{"error":"network unreachable"}"#)
        .create();
    let client = Client::new(&server.url());

    let err = client.health().await.unwrap_err();
    match err {
        AntdError::Network(msg) => assert_eq!(msg, "network unreachable"),
        other => panic!("expected Network, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_partial_upload_error_carries_counts_and_retryable() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/upload/finalize")
        .with_status(502)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "error": "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)",
            "code": "PARTIAL_UPLOAD",
            "chunks_stored": 300,
            "chunks_failed": 12,
            "total_chunks": 312,
            "retryable": true
        }"#,
        )
        .create();
    let client = Client::new(&server.url());

    let err = client
        .finalize_merkle_upload("mb1", "0xw1", false)
        .await
        .unwrap_err();
    match err {
        AntdError::PartialUpload {
            chunks_stored,
            chunks_failed,
            total_chunks,
            retryable,
            retention_known,
            message,
        } => {
            assert_eq!(chunks_stored, 300);
            assert_eq!(chunks_failed, 12);
            assert_eq!(total_chunks, 312);
            assert!(retryable, "expected retryable from the body flag");
            assert!(
                retention_known,
                "a JSON bool retryable establishes retention"
            );
            assert!(message.starts_with("Partial upload: 300/312"), "{message}");
        }
        other => panic!("expected PartialUpload, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_partial_upload_error_missing_retryable_is_unknown_retention() {
    // An older daemon (< 0.14.0) never sends `retryable`. The flag reads
    // false, so callers do not loop on the upload_id, and retention reads as
    // unknown rather than "nothing retained", so callers stop and reconcile
    // instead of paying again.
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/upload/finalize")
        .with_status(502)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "error": "Partial upload: 300/312 chunks stored, 12 failed after retries",
            "code": "PARTIAL_UPLOAD",
            "chunks_stored": 300,
            "chunks_failed": 12,
            "total_chunks": 312
        }"#,
        )
        .create();
    let client = Client::new(&server.url());

    let mut tx_hashes = std::collections::HashMap::new();
    tx_hashes.insert("0xq".to_string(), "0xt".to_string());
    let err = client.finalize_upload("u1", &tx_hashes).await.unwrap_err();
    match err {
        AntdError::PartialUpload {
            chunks_stored,
            chunks_failed,
            total_chunks,
            retryable,
            retention_known,
            ..
        } => {
            assert_eq!((chunks_stored, chunks_failed, total_chunks), (300, 12, 312));
            assert!(
                !retryable,
                "retryable must default to false without the body flag"
            );
            assert!(
                !retention_known,
                "a missing retryable must leave retention unknown"
            );
        }
        other => panic!("expected PartialUpload, got: {other:?}"),
    }
}

#[test]
fn test_partial_upload_body_mistyped_fields_read_zero_and_false() {
    // REST reads typed JSON: a count is a non-negative integer that fits a
    // u64 and `retryable` is a JSON bool. Anything else (a quoted number, a
    // quoted "true", a negative, a fraction, an overflow, null) reads as
    // 0 / false rather than being coerced, and a mistyped `retryable` leaves
    // retention unknown, so a malformed body never selects paid-attempt
    // recovery and never reads as "nothing retained".
    let bodies = [
        r#"{"error":"Partial upload: 300/312 chunks stored, 12 failed","code":"PARTIAL_UPLOAD","chunks_stored":"300","chunks_failed":"12","total_chunks":"312","retryable":"true"}"#,
        r#"{"error":"Partial upload: 300/312 chunks stored, 12 failed","code":"PARTIAL_UPLOAD","chunks_stored":-1,"chunks_failed":12.5,"total_chunks":18446744073709551616,"retryable":1}"#,
        r#"{"error":"Partial upload: 300/312 chunks stored, 12 failed","code":"PARTIAL_UPLOAD","chunks_stored":null,"chunks_failed":null,"total_chunks":null,"retryable":null}"#,
    ];
    for body in bodies {
        match error_for_body(502, body.as_bytes()) {
            AntdError::PartialUpload {
                chunks_stored,
                chunks_failed,
                total_chunks,
                retryable,
                retention_known,
                ..
            } => {
                assert_eq!(
                    (chunks_stored, chunks_failed, total_chunks),
                    (0, 0, 0),
                    "{body}"
                );
                assert!(!retryable, "mistyped retryable must read false: {body}");
                assert!(
                    !retention_known,
                    "mistyped retryable must leave retention unknown: {body}"
                );
            }
            other => panic!("expected PartialUpload for {body}, got: {other:?}"),
        }
    }
}

#[test]
fn test_partial_upload_body_retention_known() {
    // Only a JSON bool `retryable` establishes retention: `true` is a
    // retained attempt, `false` a confirmed non-retention. Missing, null or
    // any other type is unknown retention, never "nothing retained".
    let cases = [
        (Some(json!(true)), (true, true)),
        (Some(json!(false)), (false, true)),
        (None, (false, false)),
        (Some(json!(null)), (false, false)),
        (Some(json!("true")), (false, false)),
        (Some(json!("false")), (false, false)),
        (Some(json!(1)), (false, false)),
        (Some(json!(0)), (false, false)),
    ];
    for (flag, (want_retryable, want_known)) in cases {
        let mut body = json!({
            "error": "Partial upload: 300/312 chunks stored, 12 failed after retries",
            "code": "PARTIAL_UPLOAD",
            "chunks_stored": 300,
            "chunks_failed": 12,
            "total_chunks": 312,
        });
        if let Some(flag) = &flag {
            body["retryable"] = flag.clone();
        }
        match error_for_body(502, body.to_string().as_bytes()) {
            AntdError::PartialUpload {
                chunks_stored,
                chunks_failed,
                total_chunks,
                retryable,
                retention_known,
                ..
            } => {
                assert_eq!(
                    (chunks_stored, chunks_failed, total_chunks),
                    (300, 12, 312),
                    "{flag:?}"
                );
                assert_eq!(
                    (retryable, retention_known),
                    (want_retryable, want_known),
                    "retryable = {flag:?}"
                );
            }
            other => panic!("expected PartialUpload for {flag:?}, got: {other:?}"),
        }
    }
}

#[tokio::test]
async fn test_plain_502_still_maps_to_network() {
    // Only `code: PARTIAL_UPLOAD` is special-cased; a 502 with any other
    // code keeps the status-based mapping.
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/upload/finalize")
        .with_status(502)
        .with_header("content-type", "application/json")
        .with_body(r#"{"error":"upstream unreachable","code":"NETWORK_ERROR"}"#)
        .create();
    let client = Client::new(&server.url());

    let tx_hashes = std::collections::HashMap::new();
    let err = client.finalize_upload("up1", &tx_hashes).await.unwrap_err();
    match err {
        AntdError::Network(msg) => assert_eq!(msg, "upstream unreachable"),
        other => panic!("expected Network for plain 502, got: {other:?}"),
    }
}

#[test]
fn test_parse_partial_upload_message() {
    // (stored, failed, total, retryable, retention_known)
    let cases = [
        // Well-formed with the hint: retention known, retryable.
        (
            "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)",
            (300, 12, 312, true, true),
        ),
        // Well-formed with the not-retained hint: retention known, nothing
        // retained.
        (
            "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (stored chunks persist; re-prepare the same content to retry only the remainder)",
            (300, 12, 312, false, true),
        ),
        // Readable counts but no retention hint: the daemon's answer was not
        // read, so retention is unknown, never "nothing retained".
        (
            "Partial upload: 300/312 chunks stored, 12 failed after retries",
            (300, 12, 312, false, false),
        ),
        (
            "Partial upload: 0/1 chunks stored, 1 failed",
            (0, 1, 1, false, false),
        ),
        // The largest u64 still converts, so the hint is honoured.
        (
            "Partial upload: 18446744073709551615/18446744073709551615 chunks stored, 18446744073709551615 failed (paid attempt retained)",
            (u64::MAX, u64::MAX, u64::MAX, true, true),
        ),
        // Pattern misses: the counts gate retention, so the hint alone never
        // makes the error retryable, and retention reads as unknown.
        (
            "Partial upload: 300/312 chunks (paid attempt retained)",
            (0, 0, 0, false, false),
        ),
        (
            "Partial upload: n/a chunks stored, 12 failed (paid attempt retained)",
            (0, 0, 0, false, false),
        ),
        (
            "Partial upload: -1/312 chunks stored, 12 failed (paid attempt retained)",
            (0, 0, 0, false, false),
        ),
        (
            "something else (paid attempt retained)",
            (0, 0, 0, false, false),
        ),
        ("something else entirely", (0, 0, 0, false, false)),
    ];
    for (msg, want) in cases {
        let got = parse_partial_upload_message(msg);
        assert_eq!(got, want, "{msg:?}");
        // Invariant: retryable implies retention_known.
        assert!(
            !got.3 || got.4,
            "retryable without known retention: {msg:?}"
        );
    }
}

#[test]
fn test_parse_partial_upload_message_overflow_disables_retry() {
    // 2^64, one past u64::MAX. A count that fails to convert, in any
    // position, zeroes every count, disables retry and leaves retention
    // unknown even though the retained hint is present: fields the client
    // could not read must not select paid-attempt recovery, nor read as
    // "nothing retained".
    const OVER: &str = "18446744073709551616";
    const TAIL: &str = "after retries: quorum (paid attempt retained: call finalize again \
                        with the same upload_id to store the remainder against the same payment)";
    let msgs = [
        format!("Partial upload: {OVER}/312 chunks stored, 12 failed {TAIL}"),
        format!("Partial upload: 300/{OVER} chunks stored, 12 failed {TAIL}"),
        format!("Partial upload: 300/312 chunks stored, {OVER} failed {TAIL}"),
        format!("Partial upload: {OVER}/{OVER} chunks stored, {OVER} failed {TAIL}"),
    ];
    for msg in &msgs {
        assert!(msg.contains("paid attempt retained"), "{msg:?}");
        assert_eq!(
            parse_partial_upload_message(msg),
            (0, 0, 0, false, false),
            "{msg:?}"
        );
    }
}

/// The daemon's two closing hints (`partial_upload_hint` in
/// `antd/src/error.rs`), with the space before them.
const RETAINED_TAIL: &str = " (paid attempt retained: call finalize again with the same \
                             upload_id to store the remainder against the same payment)";
const NOT_RETAINED_TAIL: &str =
    " (stored chunks persist; re-prepare the same content to retry only the remainder)";

#[test]
fn test_parse_partial_upload_message_retention_needs_the_closing_hint() {
    // Readable counts alone do not establish retention: the message must end
    // with one of the daemon's two hints. Every case runs through the parser
    // and through the gRPC mapping (`From<tonic::Status>` for an ABORTED).
    // Mismatches are collected so a regression reports every failing case.
    const COUNTS: &str = "Partial upload: 1/3 chunks stored, 2 failed after retries:";
    let cases = [
        // Known: the message ends with one of the daemon's hints.
        (
            "retained hint",
            format!("{COUNTS} quorum{RETAINED_TAIL}"),
            (1, 2, 3, true, true),
        ),
        (
            "short retained hint",
            format!("{COUNTS} quorum (paid attempt retained)"),
            (1, 2, 3, true, true),
        ),
        (
            "not-retained hint",
            format!("{COUNTS} quorum{NOT_RETAINED_TAIL}"),
            (1, 2, 3, false, true),
        ),
        // Only the closing hint decides.
        (
            "parenthesised reason before the hint",
            format!("{COUNTS} quorum (2 of 5 peers){NOT_RETAINED_TAIL}"),
            (1, 2, 3, false, true),
        ),
        (
            "retained hint in the reason, not-retained tail",
            format!("{COUNTS} peer said (paid attempt retained){NOT_RETAINED_TAIL}"),
            (1, 2, 3, false, true),
        ),
        // Unknown: the counts still read, but the daemon's answer on
        // retention was not read, so both flags stay false (stop and
        // reconcile, never "nothing retained").
        ("no hint", format!("{COUNTS} quorum"), (1, 2, 3, false, false)),
        (
            // The review's reproducer: the retained hint cut short.
            "truncated retained hint",
            format!("{COUNTS} quorum (paid attempt retai"),
            (1, 2, 3, false, false),
        ),
        (
            "retained hint without its closing paren",
            format!("{COUNTS} quorum (paid attempt retained: call finalize again"),
            (1, 2, 3, false, false),
        ),
        (
            "truncated not-retained hint",
            format!("{COUNTS} quorum (stored chunks persist; re-prepare the same con"),
            (1, 2, 3, false, false),
        ),
        (
            "unrecognised hint",
            format!("{COUNTS} quorum (something else)"),
            (1, 2, 3, false, false),
        ),
        (
            "text after the hint",
            format!("{COUNTS} quorum{RETAINED_TAIL} trailing"),
            (1, 2, 3, false, false),
        ),
        (
            "newline after the retained hint",
            format!("{COUNTS} quorum{RETAINED_TAIL}\n"),
            (1, 2, 3, false, false),
        ),
        (
            "newline after the not-retained hint",
            format!("{COUNTS} quorum{NOT_RETAINED_TAIL}\n"),
            (1, 2, 3, false, false),
        ),
        (
            "retained hint quoted in the reason only",
            format!("{COUNTS} peer said (paid attempt retained) (connection reset)"),
            (1, 2, 3, false, false),
        ),
        // The counts pattern is anchored at the start of the message, and the
        // failed count must be followed by ` failed`: counts quoted later in
        // a garbled message are not read, hint or not.
        (
            "embedded counts",
            format!(
                "Partial upload: garbled; was Partial upload: 1/3 chunks stored, 2 failed{RETAINED_TAIL}"
            ),
            (0, 0, 0, false, false),
        ),
        (
            "failed count not followed by ` failed`",
            format!("Partial upload: 1/3 chunks stored, 2x failed after retries: quorum{RETAINED_TAIL}"),
            (0, 0, 0, false, false),
        ),
    ];
    let mut mismatches = Vec::new();
    for (name, msg, want) in &cases {
        let parsed = parse_partial_upload_message(msg);
        if parsed != *want {
            mismatches.push(format!("{name}: parser gave {parsed:?}, want {want:?}"));
        }
        match AntdError::from(tonic::Status::aborted(msg.clone())) {
            AntdError::PartialUpload {
                chunks_stored,
                chunks_failed,
                total_chunks,
                retryable,
                retention_known,
                message,
            } => {
                let mapped = (
                    chunks_stored,
                    chunks_failed,
                    total_chunks,
                    retryable,
                    retention_known,
                );
                if mapped != *want || message != *msg {
                    mismatches.push(format!(
                        "{name}: gRPC mapping gave {mapped:?} / {message:?}, want {want:?}"
                    ));
                }
            }
            other => mismatches.push(format!("{name}: expected PartialUpload, got {other:?}")),
        }
    }
    assert!(
        mismatches.is_empty(),
        "{} mismatch(es):\n{}",
        mismatches.len(),
        mismatches.join("\n")
    );
}

#[tokio::test]
async fn test_error_mapping_already_exists() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/data/public")
        .with_status(409)
        .with_header("content-type", "application/json")
        .with_body(r#"{"error":"already exists"}"#)
        .create();
    let client = Client::new(&server.url());

    let err = client
        .data_put_public(b"test", PaymentMode::Auto)
        .await
        .unwrap_err();
    match err {
        AntdError::AlreadyExists(msg) => assert_eq!(msg, "already exists"),
        other => panic!("expected AlreadyExists, got: {other:?}"),
    }
}

#[tokio::test]
async fn test_prepare_upload_merkle() {
    let mut server = mock_server().await;
    let _m = mock_prepare_upload_merkle(&mut server);
    let client = Client::new(&server.url());

    let result = client.prepare_upload("/tmp/test.bin", None).await.unwrap();
    assert_eq!(result.upload_id, "up123");
    assert_eq!(result.payment_type, "merkle");
    assert_eq!(result.total_amount, "5000");
    assert_eq!(result.depth, Some(4));
    assert_eq!(result.merkle_payment_timestamp, Some(1700000000));
    assert_eq!(result.payment_vault_address, "0xMP");

    let pools = result.pool_commitments.unwrap();
    assert_eq!(pools.len(), 2);
    assert_eq!(pools[0].pool_hash, "0xpool1");
    assert_eq!(pools[0].candidates.len(), 2);
    assert_eq!(pools[0].candidates[0].rewards_address, "0xnode1");
    assert_eq!(pools[0].candidates[0].amount, "1000");
    assert_eq!(pools[0].candidates[1].rewards_address, "0xnode2");
    assert_eq!(pools[0].candidates[1].amount, "2000");
    assert_eq!(pools[1].pool_hash, "0xpool2");
    assert_eq!(pools[1].candidates.len(), 1);
    assert_eq!(pools[1].candidates[0].rewards_address, "0xnode3");
    // already-stored preflight (added in antd 0.10.0)
    assert_eq!(result.total_chunks, 128);
    assert_eq!(result.already_stored_count, 4);
}

#[tokio::test]
async fn test_finalize_merkle_upload() {
    let mut server = mock_server().await;
    let _m = mock_finalize_merkle_upload(&mut server);
    let client = Client::new(&server.url());

    let result = client
        .finalize_merkle_upload("up123", "0xpool1", true)
        .await
        .unwrap();
    assert_eq!(result.address, "addr456");
    assert_eq!(result.chunks_stored, 10);
}

#[tokio::test]
async fn test_prepare_upload_backward_compat() {
    let mut server = mock_server().await;
    let _m = mock_prepare_upload_legacy(&mut server);
    let client = Client::new(&server.url());

    let result = client.prepare_upload("/tmp/old.bin", None).await.unwrap();
    assert_eq!(result.upload_id, "up_old");
    assert_eq!(result.payment_type, "");
    assert_eq!(result.depth, None);
    assert!(result.pool_commitments.is_none());
    assert!(result.merkle_payment_timestamp.is_none());
    assert_eq!(result.payment_vault_address, "0xDP");
    assert_eq!(result.payments.len(), 1);
    assert_eq!(result.payments[0].quote_hash, "qh1");
    // preflight fields absent in older-daemon responses default to 0
    assert_eq!(result.total_chunks, 0);
    assert_eq!(result.already_stored_count, 0);
}

// ---------------------------------------------------------------------------
// V2-249 PR4 + V2-274 — visibility, data_map_address, chunks prepare/finalize.
// ---------------------------------------------------------------------------

/// Body matcher for prepare_upload: asserts visibility="public" is forwarded.
fn mock_prepare_upload_public(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/upload/prepare")
        .match_body(Matcher::Json(json!({
            "path": "/tmp/wave/file.dat",
            "visibility": "public",
        })))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "upload_id": "up_wave_1",
            "payment_type": "wave_batch",
            "payments": [{"quote_hash":"qh1","rewards_address":"0xR1","amount":"100"}],
            "total_amount": "100",
            "payment_vault_address": "0xDP",
            "payment_token_address": "0xPT",
            "rpc_url": "http://rpc.local"
        }"#,
        )
        .create()
}

#[tokio::test]
async fn test_prepare_upload_public_forwards_visibility() {
    let mut server = mock_server().await;
    let _m = mock_prepare_upload_public(&mut server);
    let client = Client::new(&server.url());

    let result = client
        .prepare_upload_public("/tmp/wave/file.dat")
        .await
        .unwrap();
    assert_eq!(result.upload_id, "up_wave_1");
    assert_eq!(result.payment_type, "wave_batch");
    // The PartialJsonString matcher on the mock verifies the daemon saw
    // visibility="public".
}

#[tokio::test]
async fn test_prepare_upload_without_visibility_omits_field() {
    // Mock asserts the body has exactly {"path": "..."} — no visibility key.
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/upload/prepare")
        .match_body(Matcher::Json(json!({"path": "/tmp/wave/file.dat"})))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "upload_id": "up_priv",
            "payment_type": "wave_batch",
            "payments": [],
            "total_amount": "0",
            "payment_vault_address": "0xDP",
            "payment_token_address": "0xPT",
            "rpc_url": "http://rpc.local"
        }"#,
        )
        .create();
    let client = Client::new(&server.url());

    let result = client
        .prepare_upload("/tmp/wave/file.dat", None)
        .await
        .unwrap();
    assert_eq!(result.upload_id, "up_priv");
    // If `visibility: null` had been serialized, the strict Matcher::Json
    // above would reject the request.
}

#[tokio::test]
async fn test_finalize_upload_parses_data_map_address_when_present() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/upload/finalize")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "address": "0xFINAL",
            "chunks_stored": 42,
            "data_map": "deadbeef",
            "data_map_address": "0xDMAP"
        }"#,
        )
        .create();
    let client = Client::new(&server.url());

    let mut tx_hashes = std::collections::HashMap::new();
    tx_hashes.insert("qh1".to_string(), "tx1".to_string());
    let result = client
        .finalize_upload("up_wave_1", &tx_hashes)
        .await
        .unwrap();
    assert_eq!(result.address, "0xFINAL");
    assert_eq!(result.chunks_stored, 42);
    assert_eq!(result.data_map, "deadbeef");
    assert_eq!(result.data_map_address, "0xDMAP");
}

#[tokio::test]
async fn test_finalize_upload_data_map_address_empty_when_absent() {
    // Private uploads return no data_map_address — serde(default) means
    // it deserializes to "".
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/upload/finalize")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "address": "0xFINAL",
            "chunks_stored": 7,
            "data_map": "deadbeef"
        }"#,
        )
        .create();
    let client = Client::new(&server.url());

    let tx_hashes = std::collections::HashMap::new();
    let result = client.finalize_upload("up_priv", &tx_hashes).await.unwrap();
    assert_eq!(result.address, "0xFINAL");
    assert_eq!(result.data_map, "deadbeef");
    assert_eq!(result.data_map_address, "");
}

#[tokio::test]
async fn test_prepare_upload_with_options_sends_flag_and_parses_signed_quotes() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/upload/prepare")
        .match_body(Matcher::Json(json!({
            "path": "/tmp/x",
            "include_signed_quotes": true
        })))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "upload_id": "up9", "payment_type": "wave_batch",
            "payments": [{"quote_hash": "qh9", "rewards_address": "ra9", "amount": "5"}],
            "signed_quotes": [{"quote_hash": "qh9", "quote": "b3BhcXVl", "commitment_sidecar": "c2lkZQ=="}],
            "total_amount": "5", "payment_vault_address": "dp", "payment_token_address": "pt",
            "rpc_url": "http://localhost:1"
        }"#,
        )
        .create();
    let client = Client::new(&server.url());

    let opts = PrepareOptions {
        visibility: None,
        include_signed_quotes: true,
    };
    let res = client
        .prepare_upload_with_options("/tmp/x", &opts)
        .await
        .unwrap();
    assert_eq!(res.upload_id, "up9");
    assert_eq!(res.signed_quotes.len(), 1);
    let sq = &res.signed_quotes[0];
    assert_eq!(sq.quote_hash, "qh9");
    assert_eq!(sq.quote, "b3BhcXVl");
    assert_eq!(sq.commitment_sidecar.as_deref(), Some("c2lkZQ=="));
}

#[tokio::test]
async fn test_prepare_upload_without_flag_omits_field_and_has_no_signed_quotes() {
    // The exact-match body proves neither `visibility` nor
    // `include_signed_quotes` is sent when at their defaults.
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/upload/prepare")
        .match_body(Matcher::Json(json!({ "path": "/tmp/x" })))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"upload_id": "up1", "payment_type": "wave_batch", "payments": []}"#)
        .create();
    let client = Client::new(&server.url());

    let res = client.prepare_upload("/tmp/x", None).await.unwrap();
    assert_eq!(res.upload_id, "up1");
    assert!(res.signed_quotes.is_empty());
}

#[tokio::test]
async fn test_prepare_data_upload_with_options_sends_flag_and_visibility() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/data/prepare")
        .match_body(Matcher::Json(json!({
            "data": BASE64.encode(b"hello"),
            "visibility": "public",
            "include_signed_quotes": true
        })))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "upload_id": "up2", "payment_type": "wave_batch",
            "payments": [{"quote_hash": "qh2", "rewards_address": "ra2", "amount": "7"}],
            "signed_quotes": [{"quote_hash": "qh2", "quote": "b3BhcXVl"}]
        }"#,
        )
        .create();
    let client = Client::new(&server.url());

    let opts = PrepareOptions {
        visibility: Some("public".to_string()),
        include_signed_quotes: true,
    };
    let res = client
        .prepare_data_upload_with_options(b"hello", &opts)
        .await
        .unwrap();
    assert_eq!(res.upload_id, "up2");
    assert_eq!(res.signed_quotes.len(), 1);
    // Baseline quote: no sidecar on the wire → None in the model.
    assert_eq!(res.signed_quotes[0].commitment_sidecar, None);
}

#[tokio::test]
async fn test_prepare_chunk_upload_with_options_parses_signed_quotes() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/chunks/prepare")
        .match_body(Matcher::Json(json!({
            "data": BASE64.encode(b"chunk"),
            "include_signed_quotes": true
        })))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "address": "addr_new", "already_stored": false, "upload_id": "upc1",
            "payment_type": "wave_batch",
            "payments": [{"quote_hash": "qhc", "rewards_address": "rac", "amount": "3"}],
            "signed_quotes": [{"quote_hash": "qhc", "quote": "b3BhcXVl", "commitment_sidecar": "c2lkZQ=="}]
        }"#,
        )
        .create();
    let client = Client::new(&server.url());

    let opts = PrepareOptions {
        visibility: None,
        include_signed_quotes: true,
    };
    let res = client
        .prepare_chunk_upload_with_options(b"chunk", &opts)
        .await
        .unwrap();
    assert_eq!(res.upload_id, "upc1");
    assert_eq!(res.signed_quotes.len(), 1);
    assert_eq!(res.signed_quotes[0].quote_hash, "qhc");
}

#[tokio::test]
async fn test_verify_quotes() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/verify/quotes")
        .match_body(Matcher::Json(json!({
            "entries": [
                {"quote_hash": "qh1", "rewards_address": "ra1", "amount": "5",
                 "signed_quote": "b3BhcXVl", "commitment_sidecar": "c2lkZQ=="},
                {"quote_hash": "qh2", "rewards_address": "ra2", "amount": "6",
                 "signed_quote": "b3BhcXVlMg=="}
            ]
        })))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "valid": false,
            "entries": [
                {"quote_hash": "qh1", "valid": true, "timestamp_unix_secs": 1756000000,
                 "content": "aa", "price": "5", "rewards_address": "ra1",
                 "committed_key_count": 42, "pinned": true},
                {"quote_hash": "qh2", "valid": false,
                 "error": "price 6 does not equal calculate_price(committed_key_count=0)"}
            ]
        }"#,
        )
        .create();
    let client = Client::new(&server.url());

    let res = client
        .verify_quotes(&[
            VerifyQuoteEntry {
                quote_hash: "qh1".into(),
                rewards_address: "ra1".into(),
                amount: "5".into(),
                signed_quote: "b3BhcXVl".into(),
                commitment_sidecar: Some("c2lkZQ==".into()),
            },
            VerifyQuoteEntry {
                quote_hash: "qh2".into(),
                rewards_address: "ra2".into(),
                amount: "6".into(),
                signed_quote: "b3BhcXVlMg==".into(),
                commitment_sidecar: None,
            },
        ])
        .await
        .unwrap();
    assert!(!res.valid);
    assert_eq!(res.entries.len(), 2);
    let first = &res.entries[0];
    assert!(first.valid && first.quote_decoded());
    assert_eq!(first.committed_key_count, Some(42));
    assert_eq!(first.pinned, Some(true));
    assert_eq!(first.timestamp_unix_secs, Some(1_756_000_000));
    let second = &res.entries[1];
    assert!(!second.valid && !second.quote_decoded());
    assert!(second.error.as_deref().unwrap().contains("calculate_price"));
}

#[tokio::test]
async fn test_prepare_chunk_upload_already_stored() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/chunks/prepare")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "address": "addr_already_stored",
            "already_stored": true
        }"#,
        )
        .create();
    let client = Client::new(&server.url());

    let result = client.prepare_chunk_upload(b"already_chunk").await.unwrap();
    assert_eq!(result.address, "addr_already_stored");
    assert!(result.already_stored);
    assert_eq!(result.upload_id, "");
    assert!(result.payments.is_empty());
    assert_eq!(result.total_amount, "");
    assert_eq!(result.payment_type, "");
    assert_eq!(result.payment_vault_address, "");
    assert_eq!(result.payment_token_address, "");
    assert_eq!(result.rpc_url, "");
}

#[tokio::test]
async fn test_prepare_chunk_upload_wave_batch() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/chunks/prepare")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{
            "address": "addr_chunk_new",
            "already_stored": false,
            "upload_id": "chunk_up_1",
            "payment_type": "wave_batch",
            "payments": [
                {"quote_hash":"qhC","rewards_address":"0xRC","amount":"7"}
            ],
            "total_amount": "7",
            "payment_vault_address": "0xVC",
            "payment_token_address": "0xTC",
            "rpc_url": "http://rpc.local"
        }"#,
        )
        .create();
    let client = Client::new(&server.url());

    let result = client.prepare_chunk_upload(b"new_chunk").await.unwrap();
    assert_eq!(result.address, "addr_chunk_new");
    assert!(!result.already_stored);
    assert_eq!(result.upload_id, "chunk_up_1");
    assert_eq!(result.payment_type, "wave_batch");
    assert_eq!(result.payments.len(), 1);
    assert_eq!(result.payments[0].quote_hash, "qhC");
    assert_eq!(result.payments[0].rewards_address, "0xRC");
    assert_eq!(result.payments[0].amount, "7");
    assert_eq!(result.total_amount, "7");
    assert_eq!(result.payment_vault_address, "0xVC");
    assert_eq!(result.payment_token_address, "0xTC");
    assert_eq!(result.rpc_url, "http://rpc.local");
}

#[tokio::test]
async fn test_finalize_chunk_upload_returns_address_and_forwards_body() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/chunks/finalize")
        .match_body(Matcher::Json(json!({
            "upload_id": "chunk_up_1",
            "tx_hashes": {"qhC": "tx_C"},
        })))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"address": "addr_chunk_new"}"#)
        .create();
    let client = Client::new(&server.url());

    let mut tx_hashes = std::collections::HashMap::new();
    tx_hashes.insert("qhC".to_string(), "tx_C".to_string());
    let addr = client
        .finalize_chunk_upload("chunk_up_1", &tx_hashes)
        .await
        .unwrap();
    assert_eq!(addr, "addr_chunk_new");
}

// ---------------------------------------------------------------------------
// Byte-range downloads
// ---------------------------------------------------------------------------

async fn collect_range(mut range: crate::RangeStream) -> Result<Vec<u8>, AntdError> {
    use tokio_stream::StreamExt;
    let mut out = Vec::new();
    while let Some(chunk) = range.next().await {
        out.extend_from_slice(&chunk?);
    }
    Ok(out)
}

#[tokio::test]
async fn test_data_stream_range_private() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/data/stream")
        .match_header("range", "bytes=1-3")
        .match_body(Matcher::Json(json!({"data_map": "dm123"})))
        .with_status(206)
        .with_header("content-range", "bytes 1-3/6")
        .with_body("ecr")
        .create();
    let client = Client::new(&server.url());

    let range = client.data_stream_range("dm123", 1, Some(3)).await.unwrap();
    assert_eq!((range.offset, range.length, range.size), (1, 3, 6));
    assert_eq!(collect_range(range).await.unwrap(), b"ecr");
}

#[tokio::test]
async fn test_data_stream_range_public_to_end() {
    let mut server = mock_server().await;
    let _m = server
        .mock("GET", "/v1/data/public/abc123/stream")
        .match_header("range", "bytes=3-")
        .with_status(206)
        .with_header("content-range", "bytes 3-4/5")
        .with_body("lo")
        .create();
    let client = Client::new(&server.url());

    let range = client
        .data_stream_public_range("abc123", 3, None)
        .await
        .unwrap();
    assert_eq!((range.offset, range.length, range.size), (3, 2, 5));
    assert_eq!(collect_range(range).await.unwrap(), b"lo");
}

#[tokio::test]
async fn test_data_stream_range_not_satisfiable_carries_size() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/data/stream")
        .match_header("range", "bytes=6-")
        .with_status(416)
        .with_header("content-type", "application/json")
        .with_header("content-range", "bytes */6")
        .with_body(r#"{"error":"Range not satisfiable: the object is 6 bytes","code":"RANGE_NOT_SATISFIABLE"}"#)
        .create();
    let client = Client::new(&server.url());

    match client.data_stream_range("dm123", 6, None).await {
        Err(AntdError::RangeNotSatisfiable { size, message }) => {
            assert_eq!(size, Some(6));
            assert!(message.contains("6 bytes"), "{message}");
        }
        other => panic!("expected RangeNotSatisfiable, got {other:?}"),
    }
}

#[tokio::test]
async fn test_data_stream_range_not_satisfiable_without_size() {
    // A 416 without Content-Range is still the typed error, with no size.
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/data/stream")
        .with_status(416)
        .with_header("content-type", "application/json")
        .with_body(r#"{"error":"Range not satisfiable","code":"RANGE_NOT_SATISFIABLE"}"#)
        .create();
    let client = Client::new(&server.url());

    match client.data_stream_range("dm123", 6, None).await {
        Err(AntdError::RangeNotSatisfiable { size, .. }) => assert_eq!(size, None),
        other => panic!("expected RangeNotSatisfiable, got {other:?}"),
    }
}

#[tokio::test]
async fn test_data_stream_range_rejects_206_without_content_range() {
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/data/stream")
        .with_status(206)
        .with_body("ecr")
        .create();
    let client = Client::new(&server.url());

    match client.data_stream_range("dm123", 1, Some(3)).await {
        Err(AntdError::Internal(msg)) => assert!(msg.contains("without Content-Range"), "{msg}"),
        other => panic!("expected the missing Content-Range error, got {other:?}"),
    }
}

#[tokio::test]
async fn test_data_stream_range_rejects_an_ignored_range() {
    // A daemon without range support answers 200 with the whole object.
    let mut server = mock_server().await;
    let _m = mock_data_stream_private(&mut server);
    let client = Client::new(&server.url());

    match client.data_stream_range("dm123", 1, Some(3)).await {
        Err(AntdError::Internal(msg)) => assert!(msg.contains("ignored the byte range"), "{msg}"),
        other => panic!("expected the ignored-range error, got {other:?}"),
    }
}

#[tokio::test]
async fn test_data_stream_range_validates_before_sending() {
    let mut server = mock_server().await;
    let m = server.mock("POST", "/v1/data/stream").expect(0).create();
    let client = Client::new(&server.url());

    assert!(matches!(
        client.data_stream_range("dm123", 0, Some(0)).await,
        Err(AntdError::BadRequest(_))
    ));
    m.assert();
}

#[tokio::test]
async fn test_data_stream_range_reports_a_short_body() {
    // Content-Range promises 3 bytes but only 2 arrive.
    let mut server = mock_server().await;
    let _m = server
        .mock("POST", "/v1/data/stream")
        .with_status(206)
        .with_header("content-range", "bytes 1-3/6")
        .with_body("ec")
        .create();
    let client = Client::new(&server.url());

    let range = client.data_stream_range("dm123", 1, Some(3)).await.unwrap();
    assert!(matches!(
        collect_range(range).await,
        Err(AntdError::Network(_))
    ));
}

// --- Pointers ---

const OWNER: &str = "11111111111111111111111111111111111111111111111111111111111111aa";
const TARGET: &str = "22222222222222222222222222222222222222222222222222222222222222bb";
const RECIPIENT: &str = "33333333333333333333333333333333333333333333333333333333333333cc";

fn json_mock(
    server: &mut ServerGuard,
    method: &str,
    path: &str,
    status: usize,
    body: serde_json::Value,
) -> Mock {
    server
        .mock(method, path)
        .with_status(status)
        .with_header("content-type", "application/json")
        .with_body(body.to_string())
        .create()
}

#[tokio::test]
async fn test_pointer_keys() {
    let mut server = mock_server().await;
    let _m = json_mock(
        &mut server,
        "GET",
        "/v1/pointers/keys",
        200,
        json!({"keys": [{"address": OWNER}, {"address": RECIPIENT}]}),
    );
    let client = Client::new(&server.url());
    let keys = client.pointer_keys().await.unwrap();
    assert_eq!(
        keys.iter().map(|k| k.address.as_str()).collect::<Vec<_>>(),
        vec![OWNER, RECIPIENT]
    );
}

#[tokio::test]
async fn test_pointer_create_sends_owner_target_kind_and_parses_the_counter() {
    let mut server = mock_server().await;
    let m = server
        .mock("POST", "/v1/pointers")
        .match_body(Matcher::Json(
            json!({"owner": OWNER, "target": TARGET, "kind": "chunk"}),
        ))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(json!({"address": OWNER, "state_id": "ab", "counter": "0"}).to_string())
        .create();
    let client = Client::new(&server.url());
    let w = client
        .pointer_create(OWNER, TARGET, PointerKind::Chunk)
        .await
        .unwrap();
    m.assert();
    assert_eq!(
        w,
        PointerWriteResult {
            address: OWNER.into(),
            state_id: "ab".into(),
            counter: 0
        }
    );
}

#[tokio::test]
async fn test_pointer_update_forwarding_sends_kind_pointer() {
    let mut server = mock_server().await;
    let m = server
        .mock("POST", "/v1/pointers/update")
        .match_body(Matcher::Json(
            json!({"owner": OWNER, "target": RECIPIENT, "kind": "pointer"}),
        ))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(json!({"address": OWNER, "state_id": "cd", "counter": "7"}).to_string())
        .create();
    let client = Client::new(&server.url());
    let w = client
        .pointer_update(OWNER, RECIPIENT, PointerKind::Pointer)
        .await
        .unwrap();
    m.assert();
    assert_eq!(w.counter, 7);
}

#[tokio::test]
async fn test_pointer_get_final_record_reads_u64_max_and_the_transfer() {
    let mut server = mock_server().await;
    let _m = json_mock(
        &mut server,
        "GET",
        &format!("/v1/pointers/{OWNER}"),
        200,
        json!({
            "address": OWNER, "owner": "ab".repeat(1952), "counter": "18446744073709551615",
            "kind": "pointer", "kind_tag": 1, "target": RECIPIENT, "state_id": "ef",
            "is_final": true, "transferred_to": RECIPIENT
        }),
    );
    let client = Client::new(&server.url());
    let r = client.pointer_get(OWNER).await.unwrap();
    assert_eq!(r.counter, u64::MAX);
    assert!(r.is_final);
    assert_eq!(r.transferred_to.as_deref(), Some(RECIPIENT));
    assert_eq!(r.target_kind(), Some(PointerKind::Pointer));
    assert_eq!(r.owner.len(), 3904);
}

#[tokio::test]
async fn test_pointer_get_open_record_has_no_transfer() {
    let mut server = mock_server().await;
    let _m = json_mock(
        &mut server,
        "GET",
        &format!("/v1/pointers/{OWNER}"),
        200,
        json!({
            "address": OWNER, "owner": "ab", "counter": "4", "kind": "unknown", "kind_tag": 42,
            "target": TARGET, "state_id": "ef", "is_final": false, "transferred_to": null
        }),
    );
    let client = Client::new(&server.url());
    let r = client.pointer_get(OWNER).await.unwrap();
    assert_eq!(
        (r.counter, r.is_final, r.transferred_to.as_deref()),
        (4, false, None)
    );
    assert_eq!((r.kind.as_str(), r.kind_tag), ("unknown", 42));
    assert_eq!(r.target_kind(), None);
}

#[tokio::test]
async fn test_pointer_counter_that_is_not_a_decimal_string_is_an_error() {
    for counter in [
        json!("abc"),
        json!(5),
        json!("-1"),
        json!("18446744073709551616"),
    ] {
        let mut server = mock_server().await;
        let _m = json_mock(
            &mut server,
            "POST",
            "/v1/pointers",
            200,
            json!({"address": OWNER, "state_id": "ab", "counter": counter}),
        );
        let client = Client::new(&server.url());
        let err = client
            .pointer_create(OWNER, TARGET, PointerKind::Chunk)
            .await
            .expect_err("a malformed counter must not read as a number");
        assert!(matches!(err, AntdError::Internal(_)), "{counter}: {err:?}");
    }
}

#[tokio::test]
async fn test_pointer_get_missing_is_not_found() {
    let mut server = mock_server().await;
    let _m = json_mock(
        &mut server,
        "GET",
        &format!("/v1/pointers/{OWNER}"),
        404,
        json!({"error": "Record not found: no pointer at x", "code": "NOT_FOUND"}),
    );
    let client = Client::new(&server.url());
    assert!(matches!(
        client.pointer_get(OWNER).await,
        Err(AntdError::NotFound(_))
    ));
}

#[tokio::test]
async fn test_pointer_finality_open_and_forked() {
    let mut server = mock_server().await;
    let _open = json_mock(
        &mut server,
        "GET",
        &format!("/v1/pointers/{OWNER}/finality"),
        200,
        json!({
            "address": OWNER, "group": 7, "answered": 7, "status": "open", "counter": "3",
            "state": null, "states": [], "majority": null, "transferred_to": null
        }),
    );
    let state = |target: &str, holders: u32, tag: u8| {
        json!({"state_id": "s", "kind": if tag == 1 { "pointer" } else { "chunk" }, "kind_tag": tag,
               "target": target, "holders": holders,
               "transferred_to": if tag == 1 { json!(target) } else { json!(null) }})
    };
    let _forked = json_mock(
        &mut server,
        "GET",
        &format!("/v1/pointers/{RECIPIENT}/finality"),
        200,
        json!({
            "address": RECIPIENT, "group": 7, "answered": 6, "status": "forked", "counter": null,
            "state": null, "states": [state(OWNER, 4, 1), state(TARGET, 2, 0)],
            "majority": state(OWNER, 4, 1), "transferred_to": null
        }),
    );
    let client = Client::new(&server.url());

    let open = client.pointer_finality(OWNER).await.unwrap();
    assert_eq!(open.status, PointerFinalityStatus::Open);
    assert_eq!(open.counter, Some(3));
    assert!(open.state.is_none() && open.states.is_empty() && !open.is_final());

    let forked = client.pointer_finality(RECIPIENT).await.unwrap();
    assert_eq!(forked.status, PointerFinalityStatus::Forked);
    assert_eq!(
        (forked.group, forked.answered, forked.counter),
        (7, 6, None)
    );
    assert_eq!(forked.states.len(), 2);
    assert_eq!(forked.states[0].transferred_to.as_deref(), Some(OWNER));
    assert_eq!(forked.states[1].transferred_to, None);
    assert_eq!(forked.majority.as_ref().unwrap().holders, 4);
}

#[tokio::test]
async fn test_pointer_finality_unknown_status_is_kept() {
    let mut server = mock_server().await;
    let _m = json_mock(
        &mut server,
        "GET",
        &format!("/v1/pointers/{OWNER}/finality"),
        200,
        json!({"address": OWNER, "group": 7, "answered": 7, "status": "pondering", "states": []}),
    );
    let client = Client::new(&server.url());
    let f = client.pointer_finality(OWNER).await.unwrap();
    assert_eq!(f.status, PointerFinalityStatus::Unknown("pondering".into()));
}

#[tokio::test]
async fn test_pointer_transfer_with_and_without_a_finality_check() {
    let mut server = mock_server().await;
    let m = server
        .mock("POST", "/v1/pointers/transfer")
        .match_body(Matcher::Json(
            json!({"owner": OWNER, "recipient": RECIPIENT}),
        ))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            json!({
                "address": OWNER, "state_id": "f1",
                "finality": {
                    "address": OWNER, "group": 7, "answered": 7, "status": "final",
                    "counter": null, "states": [], "majority": null, "transferred_to": RECIPIENT,
                    "state": {"state_id": "f1", "kind": "pointer", "kind_tag": 1,
                              "target": RECIPIENT, "holders": 7, "transferred_to": RECIPIENT}
                }
            })
            .to_string(),
        )
        .create();
    let client = Client::new(&server.url());
    let t = client.pointer_transfer(OWNER, RECIPIENT).await.unwrap();
    m.assert();
    let f = t.finality.unwrap();
    assert!(f.is_final());
    assert_eq!(f.transferred_to.as_deref(), Some(RECIPIENT));
    assert_eq!(t.finality_error, None);

    let mut server = mock_server().await;
    let _m = json_mock(
        &mut server,
        "POST",
        "/v1/pointers/transfer",
        200,
        json!({"address": OWNER, "state_id": "f1", "finality": null,
               "finality_error": "only 3 of the close group answered"}),
    );
    let client = Client::new(&server.url());
    let t = client.pointer_transfer(OWNER, RECIPIENT).await.unwrap();
    assert!(t.finality.is_none());
    assert_eq!(
        t.finality_error.as_deref(),
        Some("only 3 of the close group answered")
    );
}

#[tokio::test]
async fn test_pointer_resolve_and_controller() {
    let mut server = mock_server().await;
    let _r = json_mock(
        &mut server,
        "GET",
        &format!("/v1/pointers/{OWNER}/resolve"),
        200,
        json!({"kind": "chunk", "kind_tag": 0, "target": TARGET}),
    );
    let _c = json_mock(
        &mut server,
        "GET",
        &format!("/v1/pointers/{OWNER}/controller"),
        200,
        json!({"pointer": RECIPIENT, "transfers": [RECIPIENT], "frozen": false}),
    );
    let client = Client::new(&server.url());
    assert_eq!(
        client.pointer_resolve(OWNER).await.unwrap(),
        PointerResolved {
            kind: "chunk".into(),
            kind_tag: 0,
            target: TARGET.into()
        }
    );
    assert_eq!(
        client.pointer_controller(OWNER).await.unwrap(),
        PointerController {
            pointer: RECIPIENT.into(),
            transfers: vec![RECIPIENT.into()],
            frozen: false
        }
    );
}

#[tokio::test]
async fn test_pointer_prepare_sends_each_op_shape() {
    let cases = [
        (
            PointerOp::Create {
                target: TARGET.into(),
                kind: PointerKind::Chunk,
            },
            json!({"owner": OWNER, "op": "create", "target": TARGET, "kind": "chunk"}),
        ),
        (
            PointerOp::Update {
                target: RECIPIENT.into(),
                kind: PointerKind::Pointer,
            },
            json!({"owner": OWNER, "op": "update", "target": RECIPIENT, "kind": "pointer"}),
        ),
        (
            PointerOp::Transfer {
                recipient: RECIPIENT.into(),
            },
            json!({"owner": OWNER, "op": "transfer", "recipient": RECIPIENT}),
        ),
    ];
    for (op, body) in cases {
        let mut server = mock_server().await;
        let m = server
            .mock("POST", "/v1/pointers/prepare")
            .match_body(Matcher::Json(body))
            .with_status(200)
            .with_header("content-type", "application/json")
            .with_body(
                json!({
                    "upload_id": "u1", "op": "x", "address": OWNER, "state_id": "s1",
                    "counter": "18446744073709551615", "payment_type": "wave_batch",
                    "payments": [{"quote_hash": "0xq", "rewards_address": "0xr", "amount": "123"}],
                    "total_amount": "123", "payment_vault_address": "0xv",
                    "payment_token_address": "0xt", "rpc_url": "http://rpc"
                })
                .to_string(),
            )
            .create();
        let client = Client::new(&server.url());
        let p = client.pointer_prepare(OWNER, &op).await.unwrap();
        m.assert();
        assert_eq!(p.upload_id, "u1");
        assert_eq!(p.counter, u64::MAX);
        assert_eq!(p.payments.len(), 1);
        assert_eq!(p.payments[0].amount, "123");
        assert!(p.signed_quotes.is_empty());
    }
}

#[tokio::test]
async fn test_pointer_prepare_with_signed_quotes() {
    let mut server = mock_server().await;
    let m = server
        .mock("POST", "/v1/pointers/prepare")
        .match_body(Matcher::PartialJson(json!({"include_signed_quotes": true})))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            json!({
                "upload_id": "u1", "op": "create", "address": OWNER, "state_id": "s1",
                "counter": "0", "payment_type": "wave_batch", "payments": [],
                "total_amount": "0", "payment_vault_address": "", "payment_token_address": "",
                "rpc_url": "", "signed_quotes": [{"quote_hash": "0xq", "quote": "b3BhcXVl"}]
            })
            .to_string(),
        )
        .create();
    let client = Client::new(&server.url());
    let p = client
        .pointer_prepare_with_options(
            OWNER,
            &PointerOp::Create {
                target: TARGET.into(),
                kind: PointerKind::Chunk,
            },
            &PrepareOptions {
                include_signed_quotes: true,
                ..Default::default()
            },
        )
        .await
        .unwrap();
    m.assert();
    assert_eq!(p.signed_quotes.len(), 1);
}

#[tokio::test]
async fn test_pointer_finalize_sends_hashes_and_reads_a_transfer_finality() {
    let mut server = mock_server().await;
    let m = server
        .mock("POST", "/v1/pointers/finalize")
        .match_body(Matcher::Json(
            json!({"upload_id": "u1", "tx_hashes": {"0xq": "0xt"}}),
        ))
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            json!({
                "address": OWNER, "state_id": "s1", "counter": "18446744073709551615",
                "finality": {"address": OWNER, "group": 7, "answered": 7, "status": "final",
                             "states": [], "transferred_to": RECIPIENT,
                             "state": {"state_id": "s1", "kind": "pointer", "kind_tag": 1,
                                       "target": RECIPIENT, "holders": 6,
                                       "transferred_to": RECIPIENT}}
            })
            .to_string(),
        )
        .create();
    let client = Client::new(&server.url());
    let hashes = std::collections::HashMap::from([("0xq".to_string(), "0xt".to_string())]);
    let f = client.pointer_finalize("u1", &hashes).await.unwrap();
    m.assert();
    assert_eq!(f.counter, u64::MAX);
    assert_eq!(
        f.finality.unwrap().state.unwrap().transferred_to.as_deref(),
        Some(RECIPIENT)
    );
}

#[tokio::test]
async fn test_pointer_finalize_retained_shortfall_is_retryable() {
    let mut server = mock_server().await;
    let _m = json_mock(
        &mut server,
        "POST",
        "/v1/pointers/finalize",
        503,
        json!({
            "error": "Close group shortfall: pointer x stored on 4 of 5 close-group peers (paid attempt retained: call finalize again with the same upload_id to store it against the same payment)",
            "code": "CLOSE_GROUP_SHORTFALL",
            "retryable": true
        }),
    );
    let client = Client::new(&server.url());
    match client
        .pointer_finalize("u1", &std::collections::HashMap::new())
        .await
    {
        Err(AntdError::CloseGroupShortfall { retryable, message }) => {
            assert!(retryable);
            assert!(message.contains("paid attempt retained"));
        }
        other => panic!("expected CloseGroupShortfall, got {other:?}"),
    }
}

#[test]
fn test_pointer_error_codes_map_by_code_not_status() {
    let body = |code: &str| json!({"error": "msg", "code": code}).to_string();
    assert!(matches!(
        error_for_body(409, body("POINTER_FINAL").as_bytes()),
        AntdError::PointerFinal(m) if m == "msg"
    ));
    assert!(matches!(
        error_for_body(409, body("POINTER_FORKED").as_bytes()),
        AntdError::PointerForked(_)
    ));
    assert!(matches!(
        error_for_body(409, body("CONFLICT").as_bytes()),
        AntdError::Conflict(_)
    ));
    // ALREADY_EXISTS, or a 409 with no code at all, keep the status mapping.
    assert!(matches!(
        error_for_body(409, body("ALREADY_EXISTS").as_bytes()),
        AntdError::AlreadyExists(_)
    ));
    assert!(matches!(
        error_for_body(409, br#"{"error":"msg"}"#),
        AntdError::AlreadyExists(_)
    ));
    // A shortfall without `retryable` (a read, a daemon-wallet write, a chunk
    // store) is not a retained paid attempt; nor is a non-bool flag.
    assert!(matches!(
        error_for_body(503, body("CLOSE_GROUP_SHORTFALL").as_bytes()),
        AntdError::CloseGroupShortfall {
            retryable: false,
            ..
        }
    ));
    assert!(matches!(
        error_for_body(
            503,
            br#"{"error":"m","code":"CLOSE_GROUP_SHORTFALL","retryable":"yes"}"#
        ),
        AntdError::CloseGroupShortfall {
            retryable: false,
            ..
        }
    ));
    // The wallet-missing 503 stays ServiceUnavailable.
    assert!(matches!(
        error_for_body(503, body("SERVICE_UNAVAILABLE").as_bytes()),
        AntdError::ServiceUnavailable(_)
    ));
}

// --- sha256 on upload results ---

/// SHA-256 of "hello\n".
const SHA: &str = "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03";

/// Mocks one POST endpoint, answering `body`.
fn mock_post(server: &mut ServerGuard, path: &str, body: String) -> Mock {
    server
        .mock("POST", path)
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(body)
        .create()
}

#[tokio::test]
async fn test_data_put_reads_sha256_when_present_and_none_when_absent() {
    let mut server = mock_server().await;
    let client = Client::new(&server.url());
    let m = mock_post(
        &mut server,
        "/v1/data",
        json!({"data_map": "dm", "sha256": SHA}).to_string(),
    );
    let r = client.data_put(b"x", PaymentMode::Auto).await.unwrap();
    assert_eq!(r.sha256.as_deref(), Some(SHA));
    m.remove();
    let _m = mock_post(&mut server, "/v1/data", r#"{"data_map":"dm"}"#.into());
    let r = client.data_put(b"x", PaymentMode::Auto).await.unwrap();
    assert_eq!(r.sha256, None);
}

#[tokio::test]
async fn test_data_put_public_reads_sha256_when_present_and_none_when_absent() {
    let mut server = mock_server().await;
    let client = Client::new(&server.url());
    let m = mock_post(
        &mut server,
        "/v1/data/public",
        json!({"address": "a", "sha256": SHA}).to_string(),
    );
    let r = client
        .data_put_public(b"x", PaymentMode::Auto)
        .await
        .unwrap();
    assert_eq!(r.sha256.as_deref(), Some(SHA));
    m.remove();
    let _m = mock_post(
        &mut server,
        "/v1/data/public",
        r#"{"address":"a","sha256":""}"#.into(),
    );
    let r = client
        .data_put_public(b"x", PaymentMode::Auto)
        .await
        .unwrap();
    assert_eq!(r.sha256, None);
}

#[tokio::test]
async fn test_file_put_reads_sha256_when_present_and_none_when_absent() {
    let mut server = mock_server().await;
    let client = Client::new(&server.url());
    let m = mock_post(
        &mut server,
        "/v1/files",
        json!({"data_map": "dm", "sha256": SHA}).to_string(),
    );
    let r = client.file_put("/tmp/x", PaymentMode::Auto).await.unwrap();
    assert_eq!(r.sha256.as_deref(), Some(SHA));
    m.remove();
    let _m = mock_post(&mut server, "/v1/files", r#"{"data_map":"dm"}"#.into());
    let r = client.file_put("/tmp/x", PaymentMode::Auto).await.unwrap();
    assert_eq!(r.sha256, None);
}

#[tokio::test]
async fn test_file_put_public_reads_sha256_when_present_and_none_when_absent() {
    let mut server = mock_server().await;
    let client = Client::new(&server.url());
    let m = mock_post(
        &mut server,
        "/v1/files/public",
        json!({"address": "a", "sha256": SHA}).to_string(),
    );
    let r = client
        .file_put_public("/tmp/x", PaymentMode::Auto)
        .await
        .unwrap();
    assert_eq!(r.sha256.as_deref(), Some(SHA));
    m.remove();
    let _m = mock_post(&mut server, "/v1/files/public", r#"{"address":"a"}"#.into());
    let r = client
        .file_put_public("/tmp/x", PaymentMode::Auto)
        .await
        .unwrap();
    assert_eq!(r.sha256, None);
}

#[tokio::test]
async fn test_finalize_upload_reads_sha256_when_present_and_none_when_absent() {
    let mut server = mock_server().await;
    let client = Client::new(&server.url());
    let tx_hashes = std::collections::HashMap::from([("qh1".to_string(), "tx1".to_string())]);
    let m = mock_post(
        &mut server,
        "/v1/upload/finalize",
        json!({"address": "a", "chunks_stored": 2, "sha256": SHA}).to_string(),
    );
    // Wave-batch and merkle finalize share the parser.
    let r = client.finalize_upload("up", &tx_hashes).await.unwrap();
    assert_eq!(r.sha256.as_deref(), Some(SHA));
    let r = client
        .finalize_merkle_upload("up", "0xwinpool", false)
        .await
        .unwrap();
    assert_eq!(r.sha256.as_deref(), Some(SHA));
    m.remove();
    let _m = mock_post(
        &mut server,
        "/v1/upload/finalize",
        r#"{"address":"a","chunks_stored":2}"#.into(),
    );
    let r = client.finalize_upload("up", &tx_hashes).await.unwrap();
    assert_eq!(r.sha256, None);
    let r = client
        .finalize_merkle_upload("up", "0xwinpool", false)
        .await
        .unwrap();
    assert_eq!(r.sha256, None);
}

/// A malformed entry hash is the daemon's 400; it reaches the caller as
/// `BadRequest` with the server's message.
#[tokio::test]
async fn test_manifest_build_bad_sha256_is_bad_request() {
    use crate::manifests::ManifestEntryInput;
    let mut server = mock_server().await;
    let msg =
        "1 invalid entries: entries[0]: invalid hex sha256: Invalid character 'z' at position 0";
    let _m = server
        .mock("POST", "/v1/manifests/build")
        .with_status(400)
        .with_header("content-type", "application/json")
        .with_body(json!({"error": msg, "code": "BAD_REQUEST"}).to_string())
        .create();
    let client = Client::new(&server.url());
    match client
        .build_manifest(&[ManifestEntryInput::public("11").with_sha256("zz")])
        .await
    {
        Err(AntdError::BadRequest(m)) => assert_eq!(m, msg),
        other => panic!("expected BadRequest, got {other:?}"),
    }
}
