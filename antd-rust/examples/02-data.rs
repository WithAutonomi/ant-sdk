use antd_client::{Client, DEFAULT_BASE_URL};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new(DEFAULT_BASE_URL);

    // Store public data
    let result = client.data_put_public(b"Hello, Autonomi!", None).await?;
    println!("Stored at: {} (cost: {} atto)", result.address, result.cost);

    // Retrieve public data
    let data = client.data_get_public(&result.address).await?;
    println!("Retrieved: {}", String::from_utf8_lossy(&data));

    // Estimate cost before storing
    let est = client.data_cost(b"Some data to estimate").await?;
    println!(
        "Estimate: {} bytes in {} chunks, storage {} atto, gas {} wei, mode {}",
        est.file_size, est.chunk_count, est.cost, est.estimated_gas_cost_wei, est.payment_mode
    );

    Ok(())
}
