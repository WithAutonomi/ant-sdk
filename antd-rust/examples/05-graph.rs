use antd_client::{Client, GraphDescendant, DEFAULT_BASE_URL};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new(DEFAULT_BASE_URL);

    // Create a graph entry (DAG node)
    let result = client
        .graph_entry_put(
            "your_secret_key_hex",
            &[],
            "content_hash_hex",
            &[GraphDescendant {
                public_key: "descendant_pk_hex".to_string(),
                content: "descendant_content_hex".to_string(),
            }],
        )
        .await?;
    println!("Graph entry at: {} (cost: {} atto)", result.address, result.cost);

    // Read the entry back
    let entry = client.graph_entry_get(&result.address).await?;
    println!("Owner: {}", entry.owner);
    println!("Descendants: {}", entry.descendants.len());

    // Check existence
    let exists = client.graph_entry_exists(&result.address).await?;
    println!("Exists: {}", exists);

    // Estimate cost
    let cost = client.graph_entry_cost("your_public_key_hex").await?;
    println!("Estimated cost: {} atto", cost);

    Ok(())
}
