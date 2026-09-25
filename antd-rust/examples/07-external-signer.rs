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
//! `finalize_with_retry` shows the bounded same-`upload_id` retry §6 of
//! that doc asks for when a finalize stores only part of the file, and
//! stops with the typed error whenever a retry is not known to be safe.

use std::collections::HashMap;
use std::fs;
use std::time::Duration;

use alloy::network::EthereumWallet;
use alloy::primitives::{Address, FixedBytes, U256};
use alloy::providers::ProviderBuilder;
use alloy::signers::local::PrivateKeySigner;
use alloy::sol;
use antd_client::{AntdError, Client, FinalizeUploadResult, DEFAULT_BASE_URL};

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

/// Upper bound on the finalize calls `finalize_with_retry` makes.
const MAX_FINALIZE_ATTEMPTS: u32 = 5;

/// Finalizes a wave-batch upload, retrying only while the daemon confirms it
/// kept the paid attempt (`AntdError::PartialUpload { retryable: true, .. }`,
/// antd >= 0.14.0). Each retry calls finalize again with the same `upload_id`
/// and `tx_hashes`, so the remainder is stored against the same payment.
/// Bounded: at most `MAX_FINALIZE_ATTEMPTS` calls with a linear backoff
/// (`backoff`, `2 * backoff`, ...), and it stops as soon as `chunks_failed`
/// stops shrinking.
///
/// It never re-prepares or pays. Whenever it stops short of success it
/// returns the daemon's original typed error, which survives boxing (a
/// caller can `downcast_ref::<AntdError>()` it):
///
/// - `PartialUpload { retryable: true, .. }`: attempts exhausted or stalled.
///   The paid attempt is still retained; retry later with the same
///   `upload_id` and `tx_hashes`, within the daemon's pending-upload TTL.
/// - `PartialUpload { retention_known: true, retryable: false, .. }`: the
///   daemon confirmed it kept nothing; re-prepare the same content, which
///   skips already-stored chunks and pays only for the remainder.
/// - `PartialUpload { retention_known: false, .. }`: retention is unknown and
///   the daemon may still hold the paid attempt. Keep `upload_id` and
///   `tx_hashes` and reconcile before re-preparing or paying again.
/// - Any other error, untouched.
async fn finalize_with_retry(
    client: &Client,
    upload_id: &str,
    tx_hashes: &HashMap<String, String>,
    backoff: Duration,
) -> Result<FinalizeUploadResult, AntdError> {
    let mut last_failed: Option<u64> = None;
    for attempt in 1..=MAX_FINALIZE_ATTEMPTS {
        let err = match client.finalize_upload(upload_id, tx_hashes).await {
            Ok(res) => return Ok(res), // every chunk stored
            Err(err) => err,
        };
        let (stored, failed, total, retryable, retention_known) = match &err {
            AntdError::PartialUpload {
                chunks_stored,
                chunks_failed,
                total_chunks,
                retryable,
                retention_known,
                ..
            } => (
                *chunks_stored,
                *chunks_failed,
                *total_chunks,
                *retryable,
                *retention_known,
            ),
            _ => return Err(err),
        };
        if !retention_known {
            eprintln!(
                "finalize stored {stored}/{total} chunks, but whether the daemon kept the \
                 paid attempt is unknown -- stopping without re-preparing or paying again; \
                 keep upload_id {upload_id} and its tx_hashes and reconcile first"
            );
            return Err(err);
        }
        if !retryable {
            eprintln!(
                "finalize stored {stored}/{total} chunks and the daemon kept nothing -- \
                 re-prepare the same content to pay only for the remaining {failed}"
            );
            return Err(err);
        }
        let stalled = last_failed.is_some_and(|prev| failed >= prev);
        if stalled || attempt == MAX_FINALIZE_ATTEMPTS {
            eprintln!(
                "finalize {} after {attempt} attempt(s): {stored}/{total} chunks stored, \
                 {failed} still unstored; the paid attempt stays retained under upload_id \
                 {upload_id} -- retry later with the same tx_hashes",
                if stalled { "stalled" } else { "gave up" },
            );
            return Err(err);
        }
        last_failed = Some(failed);
        println!(
            "finalize stored {stored}/{total} chunks, {failed} still unstored -- retrying \
             against the same payment (attempt {}/{MAX_FINALIZE_ATTEMPTS})",
            attempt + 1
        );
        tokio::time::sleep(backoff * attempt).await;
    }
    unreachable!("loop returns on success, a stop condition, or the attempt cap")
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
    let fin = finalize_with_retry(
        &client,
        &file_prep.upload_id,
        &tx_hashes,
        Duration::from_secs(2),
    )
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

#[cfg(test)]
mod tests {
    use super::*;

    const FINALIZE: &str = "/v1/upload/finalize";

    /// A daemon `PARTIAL_UPLOAD` body for a 10-chunk upload; `retryable: None`
    /// leaves the flag out, as antd < 0.14.0 does.
    fn partial_body(failed: u64, retryable: Option<bool>) -> String {
        let mut body = serde_json::json!({
            "error": format!("Partial upload: {}/10 chunks stored, {failed} failed", 10 - failed),
            "code": "PARTIAL_UPLOAD",
            "chunks_stored": 10 - failed,
            "chunks_failed": failed,
            "total_chunks": 10,
        });
        if let Some(retryable) = retryable {
            body["retryable"] = retryable.into();
        }
        body.to_string()
    }

    /// A finalize mock answering `hits` calls with a partial store.
    fn mock_partial(
        server: &mut mockito::ServerGuard,
        failed: u64,
        retryable: Option<bool>,
        hits: usize,
    ) -> mockito::Mock {
        server
            .mock("POST", FINALIZE)
            .with_status(502)
            .with_header("content-type", "application/json")
            .with_body(partial_body(failed, retryable))
            .expect(hits)
            .create()
    }

    async fn finalize(server: &mockito::ServerGuard) -> Result<FinalizeUploadResult, AntdError> {
        let client = Client::new(&server.url());
        let tx_hashes = HashMap::from([("0xq".to_string(), "0xt".to_string())]);
        finalize_with_retry(&client, "u1", &tx_hashes, Duration::ZERO).await
    }

    #[tokio::test]
    async fn unknown_retention_stops_after_one_call_with_the_typed_error() {
        let mut server = mockito::Server::new_async().await;
        let m = mock_partial(&mut server, 3, None, 1);
        let err = finalize(&server).await.unwrap_err();
        // Exactly one finalize: no retry, and the helper never re-prepares or pays.
        m.assert_async().await;
        assert!(
            matches!(
                err,
                AntdError::PartialUpload {
                    retention_known: false,
                    retryable: false,
                    chunks_failed: 3,
                    ..
                }
            ),
            "{err:?}"
        );
        // `main`'s `?` boxes the error; the typed variant survives the box.
        let boxed: Box<dyn std::error::Error> = err.into();
        assert!(matches!(
            boxed.downcast_ref::<AntdError>(),
            Some(AntdError::PartialUpload {
                retention_known: false,
                ..
            })
        ));
    }

    #[tokio::test]
    async fn confirmed_non_retention_stops_after_one_call() {
        let mut server = mockito::Server::new_async().await;
        let m = mock_partial(&mut server, 3, Some(false), 1);
        let err = finalize(&server).await.unwrap_err();
        m.assert_async().await;
        assert!(
            matches!(
                err,
                AntdError::PartialUpload {
                    retention_known: true,
                    retryable: false,
                    ..
                }
            ),
            "{err:?}"
        );
    }

    #[tokio::test]
    async fn retained_attempt_is_retried_until_complete() {
        let mut server = mockito::Server::new_async().await;
        let partial = mock_partial(&mut server, 3, Some(true), 1);
        let done = server
            .mock("POST", FINALIZE)
            .with_status(200)
            .with_header("content-type", "application/json")
            .with_body(r#"{"chunks_stored":10,"data_map_address":"ab"}"#)
            .expect(1)
            .create();
        let fin = finalize(&server).await.unwrap();
        partial.assert_async().await;
        done.assert_async().await;
        assert_eq!(fin.chunks_stored, 10);
        assert_eq!(fin.data_map_address, "ab");
    }

    #[tokio::test]
    async fn stalled_retry_returns_the_typed_error() {
        let mut server = mockito::Server::new_async().await;
        // `chunks_failed` does not shrink on the second call.
        let m = mock_partial(&mut server, 3, Some(true), 2);
        let err = finalize(&server).await.unwrap_err();
        m.assert_async().await;
        assert!(
            matches!(
                err,
                AntdError::PartialUpload {
                    retryable: true,
                    chunks_failed: 3,
                    ..
                }
            ),
            "{err:?}"
        );
    }

    #[tokio::test]
    async fn exhausted_retry_returns_the_typed_error() {
        let mut server = mockito::Server::new_async().await;
        // `chunks_failed` shrinks on every call but never reaches zero.
        let mocks: Vec<_> = (1..=u64::from(MAX_FINALIZE_ATTEMPTS))
            .map(|i| mock_partial(&mut server, 10 - i, Some(true), 1))
            .collect();
        let err = finalize(&server).await.unwrap_err();
        for m in &mocks {
            m.assert_async().await;
        }
        assert!(
            matches!(
                err,
                AntdError::PartialUpload {
                    retryable: true,
                    chunks_failed: 5,
                    ..
                }
            ),
            "{err:?}"
        );
    }
}
