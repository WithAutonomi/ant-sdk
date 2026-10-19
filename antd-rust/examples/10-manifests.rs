//! Example 10: Build a manifest of two files and read it back.
//!
//! A manifest (ADR-0006) is a `.ant` file, or an `ant://manifest/` link, that
//! lists a set of files: each with an optional path and size, and either an
//! embedded DataMap or a public DataMap address. The daemon builds and decodes
//! it, so nothing here re-implements the format.
//!
//! Environment:
//!
//! - `ANTD_BASE_URL`: daemon REST URL (default `DEFAULT_BASE_URL`).
//!
//! The two uploads pay; building and decoding the manifest upload and pay for
//! nothing.

use antd_client::{
    BuildManifestOptions, Client, ManifestEntryInput, PaymentMode, DEFAULT_BASE_URL,
};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let base_url = std::env::var("ANTD_BASE_URL").unwrap_or_else(|_| DEFAULT_BASE_URL.to_string());
    let client = Client::new(&base_url);

    println!("Note: the two uploads below pay; the manifest calls do not.");

    // Store two small pieces of public data (paid)
    let one = client
        .data_put_public(b"Manifest example, file one", PaymentMode::Auto)
        .await?;
    println!("Stored notes/one.txt at {}", one.address);
    let two = client
        .data_put_public(
            b"Manifest example, file two: a little longer",
            PaymentMode::Auto,
        )
        .await?;
    println!("Stored notes/two.txt at {}", two.address);

    // Build a manifest of both (free)
    let built = client
        .build_manifest_with_options(
            &[
                ManifestEntryInput::public(&one.address).with_path("notes/one.txt"),
                ManifestEntryInput::public(&two.address).with_path("notes/two.txt"),
            ],
            &BuildManifestOptions {
                name: Some("example".into()),
                ..Default::default()
            },
        )
        .await?;
    println!("Built a {}-byte manifest", built.manifest.len());
    for entry in &built.entries {
        println!(
            "  {} ({}) -> {}",
            entry.effective_name, entry.kind, entry.content_address
        );
    }

    // Decode it from its link, resolving each entry's exact size (free). A
    // manifest too big for a link (over 1,500 bytes) decodes from its bytes.
    let decoded = match &built.link {
        Some(link) => {
            println!("Link: {link}");
            client.decode_manifest_link(link, true).await?
        }
        None => {
            println!("Link: none (the manifest is too big for one); decoding the bytes");
            client.decode_manifest(&built.manifest, true).await?
        }
    };
    println!(
        "Decoded {} entries from the {} (name: {})",
        decoded.entries.len(),
        decoded.source,
        decoded.name.as_deref().unwrap_or("none")
    );
    for entry in &decoded.entries {
        match (entry.exact_size, &entry.error) {
            (Some(size), _) => println!("  {}: {size} bytes", entry.effective_name),
            (None, Some(error)) => println!("  {}: unresolved ({error})", entry.effective_name),
            (None, None) => println!("  {}: size unknown", entry.effective_name),
        }
    }

    println!("Manifest round-trip OK!");
    Ok(())
}
