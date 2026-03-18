use antd_client::{Client, DEFAULT_BASE_URL};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new(DEFAULT_BASE_URL);

    // Store a raw chunk
    let result = client.chunk_put(b"raw chunk data").await?;
    println!("Chunk stored at: {} (cost: {} atto)", result.address, result.cost);

    // Retrieve the chunk
    let data = client.chunk_get(&result.address).await?;
    println!("Chunk data: {} bytes", data.len());

    Ok(())
}
