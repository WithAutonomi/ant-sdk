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

fn mock_graph_entry_put(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/graph")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"cost":"500","address":"ge1"}"#)
        .create()
}

fn mock_graph_entry_get(server: &mut ServerGuard) -> Mock {
    server
        .mock("GET", "/v1/graph/ge1")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{"owner":"owner1","parents":[],"content":"abc","descendants":[{"public_key":"pk1","content":"desc1"}]}"#,
        )
        .create()
}

fn mock_graph_entry_exists(server: &mut ServerGuard) -> Mock {
    server
        .mock("HEAD", "/v1/graph/ge1")
        .with_status(200)
        .create()
}

fn mock_graph_entry_cost(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/graph/cost")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"cost":"500"}"#)
        .create()
}

fn mock_file_upload_public(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/files/upload/public")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"cost":"1000","address":"file1"}"#)
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
        .with_body(r#"{"cost":"2000","address":"dir1"}"#)
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

fn mock_archive_get_public(server: &mut ServerGuard) -> Mock {
    server
        .mock("GET", "/v1/archives/public/arc1")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            r#"{"entries":[{"path":"test.txt","address":"abc","created":1000,"modified":2000,"size":42}]}"#,
        )
        .create()
}

fn mock_archive_put_public(server: &mut ServerGuard) -> Mock {
    server
        .mock("POST", "/v1/archives/public")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"cost":"50","address":"arc2"}"#)
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

    let result = client.data_put_public(b"hello").await.unwrap();
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

    let result = client.data_put_private(b"secret").await.unwrap();
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
async fn test_graph_entry_put() {
    let mut server = mock_server().await;
    let _m = mock_graph_entry_put(&mut server);
    let client = Client::new(&server.url());

    let result = client
        .graph_entry_put("sk1", &[], "abc", &[])
        .await
        .unwrap();
    assert_eq!(result.address, "ge1");
    assert_eq!(result.cost, "500");
}

#[tokio::test]
async fn test_graph_entry_get() {
    let mut server = mock_server().await;
    let _m = mock_graph_entry_get(&mut server);
    let client = Client::new(&server.url());

    let entry = client.graph_entry_get("ge1").await.unwrap();
    assert_eq!(entry.owner, "owner1");
    assert_eq!(entry.descendants.len(), 1);
    assert_eq!(entry.descendants[0].public_key, "pk1");
    assert_eq!(entry.descendants[0].content, "desc1");
}

#[tokio::test]
async fn test_graph_entry_exists() {
    let mut server = mock_server().await;
    let _m = mock_graph_entry_exists(&mut server);
    let client = Client::new(&server.url());

    let exists = client.graph_entry_exists("ge1").await.unwrap();
    assert!(exists);
}

#[tokio::test]
async fn test_graph_entry_cost() {
    let mut server = mock_server().await;
    let _m = mock_graph_entry_cost(&mut server);
    let client = Client::new(&server.url());

    let cost = client.graph_entry_cost("pk1").await.unwrap();
    assert_eq!(cost, "500");
}

#[tokio::test]
async fn test_file_upload_public() {
    let mut server = mock_server().await;
    let _m = mock_file_upload_public(&mut server);
    let client = Client::new(&server.url());

    let result = client.file_upload_public("/tmp/test.txt").await.unwrap();
    assert_eq!(result.address, "file1");
    assert_eq!(result.cost, "1000");
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

    let result = client.dir_upload_public("/tmp/mydir").await.unwrap();
    assert_eq!(result.address, "dir1");
    assert_eq!(result.cost, "2000");
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
async fn test_archive_get_public() {
    let mut server = mock_server().await;
    let _m = mock_archive_get_public(&mut server);
    let client = Client::new(&server.url());

    let archive = client.archive_get_public("arc1").await.unwrap();
    assert_eq!(archive.entries.len(), 1);
    assert_eq!(archive.entries[0].path, "test.txt");
    assert_eq!(archive.entries[0].address, "abc");
    assert_eq!(archive.entries[0].created, 1000);
    assert_eq!(archive.entries[0].modified, 2000);
    assert_eq!(archive.entries[0].size, 42);
}

#[tokio::test]
async fn test_archive_put_public() {
    let mut server = mock_server().await;
    let _m = mock_archive_put_public(&mut server);
    let client = Client::new(&server.url());

    let archive = Archive {
        entries: vec![ArchiveEntry {
            path: "test.txt".to_string(),
            address: "abc".to_string(),
            created: 1000,
            modified: 2000,
            size: 42,
        }],
    };
    let result = client.archive_put_public(&archive).await.unwrap();
    assert_eq!(result.address, "arc2");
    assert_eq!(result.cost, "50");
}

#[tokio::test]
async fn test_file_cost() {
    let mut server = mock_server().await;
    let _m = mock_file_cost(&mut server);
    let client = Client::new(&server.url());

    let cost = client
        .file_cost("/tmp/test.txt", true, false)
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

    let err = client.data_put_public(b"bad").await.unwrap_err();
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

    let err = client.data_put_public(b"data").await.unwrap_err();
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
        .mock("POST", "/v1/graph")
        .with_status(409)
        .with_header("content-type", "application/json")
        .with_body(r#"{"error":"already exists"}"#)
        .create();
    let client = Client::new(&server.url());

    let err = client
        .graph_entry_put("sk1", &[], "abc", &[])
        .await
        .unwrap_err();
    match err {
        AntdError::AlreadyExists(msg) => assert_eq!(msg, "already exists"),
        other => panic!("expected AlreadyExists, got: {other:?}"),
    }
}
