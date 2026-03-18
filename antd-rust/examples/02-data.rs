use antd_client::{Client, DEFAULT_BASE_URL};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new(DEFAULT_BASE_URL);

    // Store public data
    let result = client.data_put_public(b"Hello, Autonomi!").await?;
    println!("Stored at: {} (cost: {} atto)", result.address, result.cost);

    // Retrieve public data
    let data = client.data_get_public(&result.address).await?;
    println!("Retrieved: {}", String::from_utf8_lossy(&data));

    // Estimate cost before storing
    let cost = client.data_cost(b"Some data to estimate").await?;
    println!("Estimated cost: {} atto", cost);

    Ok(())
}
