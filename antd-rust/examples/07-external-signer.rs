//! Example 07: External-signer flow — public file + single-chunk publish.
//!
//! PR #90 added `prepare_upload_public` / `finalize_upload` and
//! `prepare_chunk_upload` / `finalize_chunk_upload` so the wallet key
//! never has to live in the antd daemon. This example uses anvil
//! deterministic account #0 as the external signer and exercises both
//! round-trips end-to-end.
//!
//! See `docs/external-signer-flow.md` for the full reference; the
//! `IPaymentVault` contract bindings are baked in via alloy's `sol!`
//! macro from the JSON ABI committed at `docs/abi/IPaymentVault.json`.

use std::collections::HashMap;
use std::fs;

use alloy::network::EthereumWallet;
use alloy::primitives::{Address, FixedBytes, U256};
use alloy::providers::ProviderBuilder;
use alloy::signers::local::PrivateKeySigner;
use alloy::sol;
use antd_client::{Client, DEFAULT_BASE_URL};

// Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
// (storage payment) by `ant dev start --enable-evm` devnet genesis. Never
// use this key anywhere except a throw-away local devnet.
const ANVIL_KEY: &str = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

sol! {
    #[allow(missing_docs)]
    #[sol(rpc)]
    contract IERC20 {
        function approve(address spender, uint256 value) external returns (bool);
    }

    #[allow(missing_docs)]
    #[sol(rpc)]
    contract IPaymentVault {
        struct DataPayment {
            address rewardsAddress;
            uint256 amount;
            bytes32 quoteHash;
        }
        function payForQuotes(DataPayment[] memory payments) external;
    }
}

/// Run approve + payForQuotes on-chain for a daemon prepare response.
/// Returns the `quote_hash -> tx_hash` map the daemon's `finalize_*`
/// methods expect. Every entry maps to the same `payForQuotes` tx
/// because every quote in the wave is paid in one batched call.
async fn external_signer_pay(
    rpc_url: &str,
    vault_addr: Address,
    token_addr: Address,
    payments: &[antd_client::PaymentInfo],
    signer: &PrivateKeySigner,
) -> Result<HashMap<String, String>, Box<dyn std::error::Error>> {
    // No on-chain work when every quoted chunk is already on-network.
    if payments.is_empty() {
        return Ok(HashMap::new());
    }

    let wallet = EthereumWallet::from(signer.clone());
    let provider = ProviderBuilder::new()
        .wallet(wallet)
        .connect_http(rpc_url.parse()?);

    // approve(vault, MAX) -- idempotent and cheap; example uses MAX so
    // subsequent flows in this run skip a fresh approval.
    let token = IERC20::new(token_addr, provider.clone());
    let approve_receipt = token
        .approve(vault_addr, U256::MAX)
        .send()
        .await?
        .get_receipt()
        .await?;
    if !approve_receipt.status() {
        return Err(format!("approve reverted: {approve_receipt:?}").into());
    }

    // payForQuotes -- one tx covering every quote in this wave.
    let vault = IPaymentVault::new(vault_addr, provider.clone());
    let data_payments: Vec<IPaymentVault::DataPayment> = payments
        .iter()
        .map(|p| -> Result<_, Box<dyn std::error::Error>> {
            let rewards_address: Address = p.rewards_address.parse()?;
            let amount: U256 = p.amount.parse()?;
            let qh_hex = p.quote_hash.strip_prefix("0x").unwrap_or(&p.quote_hash);
            let qh = FixedBytes::<32>::from_slice(&hex::decode(qh_hex)?);
            Ok(IPaymentVault::DataPayment {
                rewardsAddress: rewards_address,
                amount,
                quoteHash: qh,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    let pay_receipt = vault
        .payForQuotes(data_payments)
        .send()
        .await?
        .get_receipt()
        .await?;
    if !pay_receipt.status() {
        return Err(format!("payForQuotes reverted: {pay_receipt:?}").into());
    }
    let pay_tx_hash = format!("{:#x}", pay_receipt.transaction_hash);

    // Every quote in this wave was paid in the same call.
    let mut tx_hashes = HashMap::new();
    for p in payments {
        tx_hashes.insert(p.quote_hash.clone(), pay_tx_hash.clone());
    }
    Ok(tx_hashes)
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new(DEFAULT_BASE_URL);
    let signer: PrivateKeySigner = ANVIL_KEY.parse()?;

    let tmp = std::env::temp_dir().join("antd-rust-07-external-signer");
    let _ = fs::remove_dir_all(&tmp);
    fs::create_dir_all(&tmp)?;

    // --- 1. file upload via external signer -------------------------------
    let src = tmp.join("file.bin");
    let file_content = "hello external signer from rust (file)\n".repeat(16); // ~624 bytes
    fs::write(&src, &file_content)?;

    let file_prep = client.prepare_upload_public(src.to_str().unwrap()).await?;
    println!(
        "File prepare: upload_id={}..., payment_type={}, payments={}, total_amount={}",
        &file_prep.upload_id[..16],
        file_prep.payment_type,
        file_prep.payments.len(),
        file_prep.total_amount,
    );

    let tx_hashes = external_signer_pay(
        &file_prep.rpc_url,
        file_prep.payment_vault_address.parse()?,
        file_prep.payment_token_address.parse()?,
        &file_prep.payments,
        &signer,
    )
    .await?;
    let fin = client
        .finalize_upload(&file_prep.upload_id, &tx_hashes)
        .await?;
    println!(
        "File finalize: data_map_address={}, chunks_stored={}",
        fin.data_map_address, fin.chunks_stored,
    );

    let dst = tmp.join("file.bin.downloaded");
    client
        .file_get_public(&fin.data_map_address, dst.to_str().unwrap())
        .await?;
    let got = fs::read(&dst)?;
    if got != file_content.as_bytes() {
        return Err("file round-trip mismatch".into());
    }
    println!("File round-trip OK!");

    // --- 2. single-chunk publish via external signer ----------------------
    let chunk_data = "hello external signer from rust (chunk)\n"
        .repeat(8)
        .into_bytes();
    let chunk_prep = client.prepare_chunk_upload(&chunk_data).await?;
    if chunk_prep.already_stored {
        println!(
            "Chunk prepare: already_stored, address={}",
            chunk_prep.address
        );
    } else {
        println!(
            "Chunk prepare: upload_id={}..., address={}, payments={}, total_amount={}",
            &chunk_prep.upload_id[..16],
            chunk_prep.address,
            chunk_prep.payments.len(),
            chunk_prep.total_amount,
        );
        let tx_hashes = external_signer_pay(
            &chunk_prep.rpc_url,
            chunk_prep.payment_vault_address.parse()?,
            chunk_prep.payment_token_address.parse()?,
            &chunk_prep.payments,
            &signer,
        )
        .await?;
        let addr = client
            .finalize_chunk_upload(&chunk_prep.upload_id, &tx_hashes)
            .await?;
        if addr != chunk_prep.address {
            return Err(
                format!("chunk address mismatch: {} != {}", addr, chunk_prep.address).into(),
            );
        }
        println!("Chunk finalize: address={addr}");
    }

    let got = client.chunk_get(&chunk_prep.address).await?;
    if got != chunk_data {
        return Err("chunk round-trip mismatch".into());
    }
    println!("Chunk round-trip OK!");

    fs::remove_dir_all(&tmp).ok();
    println!("\n07-external-signer OK!");
    Ok(())
}
