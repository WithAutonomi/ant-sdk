use antd_client::{Client, PaymentMode, DEFAULT_BASE_URL};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new(DEFAULT_BASE_URL);

    // Store private (encrypted) data
    let result = client
        .data_put(b"secret payload", PaymentMode::Auto)
        .await?;
    println!(
        "Private data stored (chunks: {}, mode: {})",
        result.chunks_stored, result.payment_mode_used
    );
    println!("Data map: {}", result.data_map);

    // Retrieve private data using the data map
    let data = client.data_get(&result.data_map).await?;
    println!("Decrypted: {}", String::from_utf8_lossy(&data));

    Ok(())
}
