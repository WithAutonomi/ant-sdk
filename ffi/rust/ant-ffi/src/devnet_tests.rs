//! Devnet-gated round trip for the external-signer flow — the real
//! `prepare → pay → finalize` path through the resumable ant-core finalize,
//! plus the lossless pre-checks against a real prepared session.
//!
//! Needs a running `ant-devnet --enable-evm` and its manifest:
//!
//! ```text
//! ANT_FFI_DEVNET_MANIFEST=~/.ant-dev/devnet-manifest.json \
//!   cargo test -p ant-ffi --locked -- --ignored devnet
//! ```
//!
//! A forced mid-finalize store shortfall is not reproducible on a healthy
//! devnet, so the `Partial → retained → resume` transition is covered by the
//! offline `session` unit tests; this test proves the `Prepared → Complete`
//! leg and the ignored-on-resume routing error paths.

use std::collections::HashMap;

use ant_core::data::{DevnetManifest, EvmAddress, Wallet as CoreWallet};
use ant_protocol::evm::{Amount, QuoteHash};

use crate::wallet::build_custom_network;
use crate::{Client, ClientError, PaymentType, Visibility};

/// Deterministic pseudo-random payload: incompressible enough to self-encrypt
/// into several fresh chunks, stable across runs (so a re-run hits the
/// already-stored preflight, which the test tolerates).
fn payload(len: usize, seed: u64) -> Vec<u8> {
    let mut x = seed | 1;
    (0..len)
        .map(|_| {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            (x >> 24) as u8
        })
        .collect()
}

fn hash32(hex_str: &str) -> [u8; 32] {
    let bytes = hex::decode(hex_str.trim_start_matches("0x")).expect("hex hash");
    bytes.try_into().expect("32-byte hash")
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a running ant-devnet; set ANT_FFI_DEVNET_MANIFEST"]
async fn devnet_external_signer_wave_round_trip() {
    let Ok(manifest_path) = std::env::var("ANT_FFI_DEVNET_MANIFEST") else {
        eprintln!("ANT_FFI_DEVNET_MANIFEST not set; skipping");
        return;
    };
    let manifest: DevnetManifest =
        serde_json::from_slice(&std::fs::read(&manifest_path).expect("read manifest"))
            .expect("parse manifest");
    let evm = manifest.evm.expect("devnet started with --enable-evm");

    let client = Client::connect_from_devnet_manifest_external_signer(manifest_path.clone(), None)
        .await
        .expect("connect external-signer client to devnet");

    // The "external wallet": the manifest's funded anvil key, paying exactly
    // the (quote_hash, rewards_address, amount) entries the SDK handed out.
    let network = build_custom_network(
        &evm.rpc_url,
        &evm.payment_token_address,
        &evm.payment_vault_address,
    )
    .expect("devnet EVM network");
    let payer =
        CoreWallet::new_from_private_key(network, &evm.wallet_private_key).expect("devnet wallet");

    // Unique per run so the preflight finds nothing already stored.
    let seed = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos() as u64;
    let data = payload(3 * 1024 * 1024, seed);

    let info = client
        .prepare_data_upload(data.clone(), Visibility::Private)
        .await
        .expect("prepare");
    assert_eq!(info.payment_type, PaymentType::WaveBatch);
    assert!(!info.already_stored, "fresh payload must need payment");
    assert!(
        !info.payments.is_empty(),
        "wave prepare yields per-quote payments"
    );
    let upload_id = info.upload_id.clone();

    // --- Lossless pre-checks against the real session -------------------

    // Wrong finalize method: refused without touching the session.
    let err = client
        .finalize_upload_merkle(upload_id.clone(), format!("0x{}", "11".repeat(32)))
        .await
        .unwrap_err();
    assert!(
        matches!(&err, ClientError::InvalidInput { reason } if reason.contains("call finalize_upload instead")),
        "wrong-method error, got {err:?}"
    );

    // Incomplete tx map (nothing paid yet): refused before ant-core can
    // consume the prepared upload.
    let err = client
        .finalize_upload(upload_id.clone(), HashMap::new())
        .await
        .unwrap_err();
    assert!(
        matches!(&err, ClientError::InvalidInput { reason } if reason.contains("missing the tx hash")),
        "incomplete-map error, got {err:?}"
    );

    // Both refusals left the session intact: calldata can still be built.
    let txs = client
        .payment_transactions(upload_id.clone())
        .await
        .expect("payment_transactions on an intact session");
    assert!(!txs.is_empty(), "approve + pay transactions expected");

    // --- Pay + finalize ----------------------------------------------------

    let quote_payments: Vec<(QuoteHash, EvmAddress, Amount)> = info
        .payments
        .iter()
        .map(|p| {
            (
                QuoteHash::from(hash32(&p.quote_hash)),
                p.rewards_address.parse().expect("rewards address"),
                p.amount.parse().expect("decimal amount"),
            )
        })
        .collect();
    let (tx_map, _gas) = payer
        .pay_for_quotes(quote_payments)
        .await
        .expect("devnet wallet pays the quotes");
    let tx_hashes: HashMap<String, String> = tx_map
        .iter()
        .map(|(q, t)| {
            (
                format!("0x{}", hex::encode(q)),
                format!("0x{}", hex::encode(t)),
            )
        })
        .collect();

    let result = client
        .finalize_upload(upload_id.clone(), tx_hashes.clone())
        .await
        .expect("finalize completes on a healthy devnet");
    assert!(result.chunks_stored > 0);
    assert_eq!(
        result.storage_cost_atto, info.total_amount,
        "finalize reports the paid intent total"
    );
    assert!(
        result.address.is_none(),
        "private upload has no public address"
    );

    // Complete removed the session: a repeat is "unknown", not a resume.
    let err = client
        .finalize_upload(upload_id.clone(), tx_hashes)
        .await
        .unwrap_err();
    assert!(
        matches!(&err, ClientError::InvalidInput { reason } if reason.contains("unknown or already-finalized")),
        "post-complete error, got {err:?}"
    );
    assert!(!client.cancel_upload(upload_id));

    // And the bytes are really there.
    let back = client
        .data_get_private(result.data_map)
        .await
        .expect("download by data map");
    assert_eq!(back, data, "round-tripped bytes differ");
}
