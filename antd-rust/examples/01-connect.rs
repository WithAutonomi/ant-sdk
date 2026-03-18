use antd_client::{Client, DEFAULT_BASE_URL};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new(DEFAULT_BASE_URL);

    let health = client.health().await?;
    println!("Daemon healthy: {}", health.ok);
    println!("Network: {}", health.network);

    Ok(())
}
