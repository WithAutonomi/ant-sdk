use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use mockito::{Matcher, Mock, ServerGuard};
use serde_json::json;

use crate::errors::AntdError;
use crate::models::PaymentMode;
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
            "merkle_payment_timestamp": 1700000000
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
