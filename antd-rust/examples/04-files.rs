use antd_client::{Client, DEFAULT_BASE_URL};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new(DEFAULT_BASE_URL);

    // Upload a file
    let result = client.file_upload_public("/tmp/example.txt", None).await?;
    println!(
        "File uploaded at: {} (storage: {} atto, gas: {} wei, chunks: {}, mode: {})",
        result.address,
        result.storage_cost_atto,
        result.gas_cost_wei,
        result.chunks_stored,
        result.payment_mode_used,
    );

    // Download a file
    client
        .file_download_public(&result.address, "/tmp/downloaded.txt")
        .await?;
    println!("File downloaded");

    // Upload a directory
    let dir_result = client.dir_upload_public("/tmp/mydir", None).await?;
    println!(
        "Directory uploaded at: {} (storage: {} atto, gas: {} wei, chunks: {}, mode: {})",
        dir_result.address,
        dir_result.storage_cost_atto,
        dir_result.gas_cost_wei,
        dir_result.chunks_stored,
        dir_result.payment_mode_used,
    );

    // Download a directory
    client
        .dir_download_public(&dir_result.address, "/tmp/mydir-downloaded")
        .await?;
    println!("Directory downloaded");

    // Estimate file upload cost
    let cost = client.file_cost("/tmp/example.txt", true).await?;
    println!("Estimated cost: {} atto", cost);

    Ok(())
}
