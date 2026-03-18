use antd_client::{Client, DEFAULT_BASE_URL};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new(DEFAULT_BASE_URL);

    // Upload a file
    let result = client.file_upload_public("/tmp/example.txt").await?;
    println!("File uploaded at: {} (cost: {} atto)", result.address, result.cost);

    // Download a file
    client
        .file_download_public(&result.address, "/tmp/downloaded.txt")
        .await?;
    println!("File downloaded");

    // Upload a directory
    let dir_result = client.dir_upload_public("/tmp/mydir").await?;
    println!("Directory uploaded at: {}", dir_result.address);

    // Download a directory
    client
        .dir_download_public(&dir_result.address, "/tmp/mydir-downloaded")
        .await?;
    println!("Directory downloaded");

    // Estimate file upload cost
    let cost = client.file_cost("/tmp/example.txt", true, false).await?;
    println!("Estimated cost: {} atto", cost);

    Ok(())
}
