use antd_client::{Client, DEFAULT_BASE_URL};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new(DEFAULT_BASE_URL);

    // Store private (encrypted) data
    let result = client.data_put_private(b"secret payload", None).await?;
    println!("Private data stored (cost: {} atto)", result.cost);
    println!("Data map: {}", result.address);

    // Retrieve private data using the data map
    let data = client.data_get_private(&result.address).await?;
    println!("Decrypted: {}", String::from_utf8_lossy(&data));

    Ok(())
}
