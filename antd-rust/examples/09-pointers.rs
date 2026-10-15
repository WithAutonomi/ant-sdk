//! Example 09: Create, update and read a pointer.
//!
//! A pointer is a small, owner-signed, mutable reference. Its address is
//! derived from its owner's key and never changes; what it points at can be
//! updated by the owner. The daemon signs with owner keys it loaded at
//! startup (`antd --pointer-keys`), so writes name the pointer by its address.
//!
//! Set `ANTD_POINTER_OWNER` to the address of a pointer the daemon holds a key
//! for (see `pointer_keys`) and that has never been written. The example
//! creates that pointer, so each address can be used once.
//!
//! Every write pays, about the price of one chunk, and every attempt pays
//! again, so pointer writes are never retried automatically.

use antd_client::{Client, PaymentMode, PointerKind, DEFAULT_BASE_URL};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let owner = std::env::var("ANTD_POINTER_OWNER").map_err(|_| {
        "set ANTD_POINTER_OWNER to the address of an unwritten pointer the daemon holds a key for"
    })?;

    let client = Client::new(DEFAULT_BASE_URL);

    println!("Note: each pointer write below (create, update) pays about the price of one chunk.");

    // Store two pieces of public data for the pointer to point at
    let first = client
        .data_put_public(b"Pointer target, version 1", PaymentMode::Auto)
        .await?;
    println!("Stored first target at {}", first.address);
    let second = client
        .data_put_public(b"Pointer target, version 2", PaymentMode::Auto)
        .await?;
    println!("Stored second target at {}", second.address);

    // Create the pointer at the first target (paid)
    let created = client
        .pointer_create(&owner, &first.address, PointerKind::Chunk)
        .await?;
    println!(
        "Created pointer {} (counter: {})",
        created.address, created.counter
    );

    // Update it to the second target (paid)
    let updated = client
        .pointer_update(&owner, &second.address, PointerKind::Chunk)
        .await?;
    println!("Updated pointer (counter: {})", updated.counter);

    // Read the pointer back
    let record = client.pointer_get(&created.address).await?;
    println!(
        "Pointer: counter {}, {} target {}, final: {}",
        record.counter, record.kind, record.target, record.is_final
    );

    // Follow it to its target and fetch the data there
    let target = client.pointer_resolve(&created.address).await?;
    println!("Resolves to {} {}", target.kind, target.target);
    assert_eq!(
        target.target, second.address,
        "pointer should resolve to the second target"
    );
    let data = client.data_get_public(&target.target).await?;
    println!("Retrieved: {}", String::from_utf8_lossy(&data));

    // Ask the pointer's close group where it stands
    let finality = client.pointer_finality(&created.address).await?;
    println!(
        "Finality: {:?} ({}/{} peers answered)",
        finality.status, finality.answered, finality.group
    );

    println!("Pointer round-trip OK!");
    Ok(())
}
