use antd_client::{Client, PaymentMode, DEFAULT_BASE_URL};
use std::fs;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new(DEFAULT_BASE_URL);

    let tmp = std::env::temp_dir().join("antd-rust-04-files");
    let _ = fs::remove_dir_all(&tmp);
    fs::create_dir_all(&tmp)?;

    let file_content = "Hello from a file on Autonomi!";

    let src_file = tmp.join("hello.txt");
    fs::write(&src_file, file_content)?;

    let est = client
        .file_cost(src_file.to_str().unwrap(), true, PaymentMode::Auto)
        .await?;
    println!(
        "Estimate: {} bytes in {} chunks, storage {} atto, gas {} wei, mode {}",
        est.file_size, est.chunk_count, est.cost, est.estimated_gas_cost_wei, est.payment_mode
    );

    let result = client
        .file_put_public(src_file.to_str().unwrap(), PaymentMode::Auto)
        .await?;
    println!(
        "File uploaded at: {} (storage: {} atto, gas: {} wei, chunks: {}, mode: {})",
        result.address,
        result.storage_cost_atto,
        result.gas_cost_wei,
        result.chunks_stored,
        result.payment_mode_used,
    );

    let dst_file = tmp.join("hello.txt.downloaded");
    client
        .file_get_public(&result.address, dst_file.to_str().unwrap())
        .await?;
    println!("File downloaded to {}", dst_file.display());

    let got = fs::read_to_string(&dst_file)?;
    if got != file_content {
        fs::remove_dir_all(&tmp).ok();
        return Err(format!(
            "round-trip mismatch: wrote {} bytes, read {} bytes",
            file_content.len(),
            got.len()
        )
        .into());
    }

    fs::remove_dir_all(&tmp).ok();
    println!("File upload/download OK!");
    Ok(())
}
