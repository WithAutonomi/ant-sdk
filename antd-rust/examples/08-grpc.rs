use antd_client::GrpcClient;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = GrpcClient::auto_discover().await?;

    let health = client.health().await?;
    println!("Daemon healthy: {}", health.ok);
    println!("Network: {}", health.network);

    if !health.ok {
        eprintln!("ERROR: antd daemon is not healthy");
        std::process::exit(1);
    }

    let payload = b"Raw chunk content stored over gRPC";
    let put = client.chunk_put(payload).await?;
    println!("Chunk stored at: {}", put.address);

    let retrieved = client.chunk_get(&put.address).await?;
    assert_eq!(
        retrieved.as_slice(),
        payload,
        "chunk round-trip mismatch over gRPC"
    );
    println!("Retrieved {} bytes — gRPC round-trip OK!", retrieved.len());

    Ok(())
}
