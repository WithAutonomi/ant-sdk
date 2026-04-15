use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use mockito::{Matcher, Mock, ServerGuard};

use crate::errors::AntdError;
use crate::models::*;
use crate::Client;

async fn mock_server() -> ServerGuard {
    mockito::Server::new_async().await
}

fn mock_health(server: &mut ServerGuard) -> Mock {
    server
        .mock("GET", "/health")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"status":"ok","network":"local"}"#)
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
        .mock("POST", "/v1/data/private")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"cost":"200","data_map":"dm123"}"#)
        .create()
}

fn mock_data_get_private(server: &mut ServerGuard) -> Mock {
    let encoded = BASE64.encode(b"secret");
    server
        .mock("GET", Matcher::Regex(r"/v1/data/private\?data_map=.*".to_string()))
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
        .with_body(r#"{"cost":"50"}"#)
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
        .mock("POST", "/v1/files/upload/public")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"address":"file1","storage_cost_atto":"1000","gas_cost_wei":"42","chunks_stored":3,"payment_mode_used":"auto"}"#)
        .create()
}

fn mock_file_download_public(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/files/download/public")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body("")
        .create()
}

fn mock_dir_upload_public(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/dirs/upload/public")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"address":"dir1","storage_cost_atto":"2000","gas_cost_wei":"100","chunks_stored":5,"payment_mode_used":"merkle"}"#)
        .create()
}

fn mock_dir_download_public(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/dirs/download/public")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body("")
        .create()
}

fn mock_file_cost(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/cost/file")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"cost":"1000"}"#)
        .create()
}

fn mock_prepare_upload_merkle(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/upload/prepare")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{
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
        }"#)
        .create()
}

fn mock_finalize_merkle_upload(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/upload/finalize")
        .match_body(Matcher::JsonString(
            r#"{"upload_id":"up123","winner_pool_hash":"0xpool1","store_data_map":true}"#.to_string(),
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
        .with_body(r#"{
            "upload_id": "up_old",
            "payments": [{"quote_hash":"qh1","rewards_address":"0xr1","amount":"100"}],
            "total_amount": "100",
            "payment_vault_address": "0xDP",
            "payment_token_address": "0xPT",
            "rpc_url": "http://rpc.local"
        }"#)
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
}

#[tokio::test]
async fn test_data_put_public() {
    let mut server = mock_server().await;
    let _m = mock_data_put_public(&mut server);
    let client = Client::new(&server.url());

    let result = client.data_put_public(b"hello", None).await.unwrap();
    assert_eq!(result.address, "abc123");
    assert_eq!(result.cost, "100");
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

    let result = client.data_put_private(b"secret", None).await.unwrap();
    assert_eq!(result.address, "dm123");
    assert_eq!(result.cost, "200");
}

#[tokio::test]
async fn test_data_get_private() {
    let mut server = mock_server().await;
    let _m = mock_data_get_private(&mut server);
    let client = Client::new(&server.url());

    let data = client.data_get_private("dm123").await.unwrap();
    assert_eq!(data, b"secret");
}

#[tokio::test]
async fn test_data_cost() {
    let mut server = mock_server().await;
    let _m = mock_data_cost(&mut server);
    let client = Client::new(&server.url());

    let cost = client.data_cost(b"test").await.unwrap();
    assert_eq!(cost, "50");
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

    let result = client.file_upload_public("/tmp/test.txt", None).await.unwrap();
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
        .file_download_public("file1", "/tmp/out.txt")
        .await
        .unwrap();
}

#[tokio::test]
async fn test_dir_upload_public() {
    let mut server = mock_server().await;
    let _m = mock_dir_upload_public(&mut server);
    let client = Client::new(&server.url());

    let result = client.dir_upload_public("/tmp/mydir", None).await.unwrap();
    assert_eq!(result.address, "dir1");
    assert_eq!(result.storage_cost_atto, "2000");
    assert_eq!(result.gas_cost_wei, "100");
    assert_eq!(result.chunks_stored, 5);
    assert_eq!(result.payment_mode_used, "merkle");
}

#[tokio::test]
async fn test_dir_download_public() {
    let mut server = mock_server().await;
    let _m = mock_dir_download_public(&mut server);
    let client = Client::new(&server.url());

    client
        .dir_download_public("dir1", "/tmp/outdir")
        .await
        .unwrap();
}

#[tokio::test]
async fn test_file_cost() {
    let mut server = mock_server().await;
    let _m = mock_file_cost(&mut server);
    let client = Client::new(&server.url());

    let cost = client
        .file_cost("/tmp/test.txt", true)
        .await
        .unwrap();
    assert_eq!(cost, "1000");
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

    let err = client.data_put_public(b"bad", None).await.unwrap_err();
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

    let err = client.data_put_public(b"data", None).await.unwrap_err();
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
        .data_put_public(b"test", None)
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

    let result = client.prepare_upload("/tmp/test.bin").await.unwrap();
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

    let result = client.prepare_upload("/tmp/old.bin").await.unwrap();
    assert_eq!(result.upload_id, "up_old");
    assert_eq!(result.payment_type, "");
    assert_eq!(result.depth, None);
    assert!(result.pool_commitments.is_none());
    assert!(result.merkle_payment_timestamp.is_none());
    assert_eq!(result.payment_vault_address, "0xDP");
    assert_eq!(result.payments.len(), 1);
    assert_eq!(result.payments[0].quote_hash, "qh1");
}
