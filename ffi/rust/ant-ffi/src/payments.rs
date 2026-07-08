//! External-signer payment plumbing: pure ABI calldata encoding + network
//! config lookup. These wrap evmlib (reached only via `ant_protocol::evm`, per
//! the single-version-pin rule) so the mobile apps can drop their hand-rolled
//! `EthCalldata` encoders and hardcoded contract addresses in favour of one
//! tested Rust implementation.

use ant_core::data::ExternalPaymentInfo;
use ant_core::data::PreparedUpload;
use ant_protocol::evm::contract::payment_vault::handler::PaymentVaultHandler;
use ant_protocol::evm::contract::payment_vault::MAX_TRANSFERS_PER_TRANSACTION;
use ant_protocol::evm::utils::http_provider;
use ant_protocol::evm::{Address, Network, U256};

use crate::{ClientError, NetworkInfo, TxReceipt, TxRequest};

/// ERC-20 `approve(address spender, uint256 value)` selector (keccak256 of the
/// signature, first 4 bytes). Standard and stable; asserted in tests.
const APPROVE_SELECTOR: [u8; 4] = [0x09, 0x5e, 0xa7, 0xb3];

/// `keccak256("MerklePaymentMade(bytes32,uint8,uint256,uint64)")` — topic0 of
/// the event whose indexed `winnerPoolHash` (topic1) the merkle finalize needs.
/// Asserted against evmlib's generated event signature in tests.
const MERKLE_PAYMENT_MADE_TOPIC0: &str =
    "0x89f0ad3859fec321e325bcc553fe234bcad374789a86f7ba932067f3f05affec";

/// Poll interval while waiting for a transaction receipt.
const RECEIPT_POLL_INTERVAL_MS: u64 = 1_500;

/// Look up the on-chain config for a known Autonomi EVM network by identifier,
/// so callers don't hardcode addresses or infer a chain id from an RPC URL.
///
/// `name` is `"arbitrum-one"` or `"arbitrum-sepolia-test"` (matching
/// `evmlib::Network::identifier()`; `"arbitrum"` / `"arbitrum-sepolia"` are
/// accepted aliases).
#[uniffi::export]
pub fn network_info(name: String) -> Result<NetworkInfo, ClientError> {
    // evmlib's `Network` enum carries the addresses + RPC but not the chain id,
    // so pair each with its known chain id here.
    let (network, chain_id): (Network, u32) = match name.as_str() {
        "arbitrum-one" | "arbitrum" => (Network::ArbitrumOne, 42161),
        "arbitrum-sepolia-test" | "arbitrum-sepolia" => (Network::ArbitrumSepoliaTest, 421614),
        other => {
            return Err(ClientError::InvalidInput {
                reason: format!(
                    "unknown network {other:?}; use \"arbitrum-one\" or \"arbitrum-sepolia-test\""
                ),
            });
        }
    };
    Ok(NetworkInfo {
        chain_id,
        token_address: format!("{:#x}", network.payment_token_address()),
        vault_address: format!("{:#x}", network.payment_vault_address()),
        rpc_url: network.rpc_url().to_string(),
    })
}

/// Build the ordered list of transactions the external wallet must sign to pay
/// for `prepared` on `network`: an ERC-20 `approve` followed by the vault
/// payment call(s). Wave-batch splits `payForQuotes` across multiple txs if it
/// exceeds `MAX_TRANSFERS_PER_TRANSACTION`. Returns an empty list when nothing
/// needs paying (everything was already stored).
pub(crate) fn build_payment_transactions(
    network: &Network,
    prepared: &PreparedUpload,
) -> Result<Vec<TxRequest>, ClientError> {
    let token = *network.payment_token_address();
    let vault = *network.payment_vault_address();

    match &prepared.payment_info {
        ExternalPaymentInfo::WaveBatch { payment_intent, .. } => {
            if payment_intent.payments.is_empty() {
                // Nothing to pay (already stored) — caller finalizes with an
                // empty tx-hash map.
                return Ok(Vec::new());
            }
            let mut txs = Vec::with_capacity(2);
            txs.push(TxRequest {
                to: format!("{token:#x}"),
                data: encode_approve(vault, payment_intent.total_amount),
                kind: "approve".into(),
                quote_hashes: Vec::new(),
            });
            // payForQuotes, batched exactly like evmlib::external_signer so a
            // batch never exceeds the contract's per-tx transfer cap.
            let handler = PaymentVaultHandler::new(vault, http_provider(network.rpc_url().clone()));
            for batch in payment_intent
                .payments
                .chunks(MAX_TRANSFERS_PER_TRANSACTION)
            {
                let (calldata, _to) =
                    handler
                        .pay_for_quotes_calldata(batch.to_vec())
                        .map_err(|e| ClientError::PaymentError {
                            reason: format!("payForQuotes calldata: {e}"),
                        })?;
                let quote_hashes = batch
                    .iter()
                    .map(|(qh, _, _)| format!("0x{}", hex::encode(qh)))
                    .collect();
                txs.push(TxRequest {
                    to: format!("{vault:#x}"),
                    data: format!("0x{}", hex::encode(&calldata)),
                    kind: "pay".into(),
                    quote_hashes,
                });
            }
            Ok(txs)
        }
        ExternalPaymentInfo::Merkle { prepared_batch, .. } => {
            // Approve a safe upper bound: the max candidate price across all
            // pools times 2^depth. The contract picks the winner pool on-chain
            // (median-of-16 ≤ max), so this never under-approves and avoids an
            // unlimited (U256::MAX) allowance in the wallet UI.
            let max_price = prepared_batch
                .pool_commitments
                .iter()
                .flat_map(|pc| pc.candidates.iter())
                .map(|c| c.price)
                .max()
                .unwrap_or(U256::ZERO);
            let approve_amount = max_price << (prepared_batch.depth as usize);

            let handler = PaymentVaultHandler::new(vault, http_provider(network.rpc_url().clone()));
            let (calldata, _to) = handler
                .pay_for_merkle_tree_calldata(
                    prepared_batch.depth,
                    prepared_batch.pool_commitments.clone(),
                    prepared_batch.merkle_payment_timestamp,
                )
                .map_err(|e| ClientError::PaymentError {
                    reason: format!("payForMerkleTree calldata: {e}"),
                })?;
            Ok(vec![
                TxRequest {
                    to: format!("{token:#x}"),
                    data: encode_approve(vault, approve_amount),
                    kind: "approve".into(),
                    quote_hashes: Vec::new(),
                },
                TxRequest {
                    to: format!("{vault:#x}"),
                    data: format!("0x{}", hex::encode(&calldata)),
                    kind: "pay".into(),
                    quote_hashes: Vec::new(),
                },
            ])
        }
    }
}

/// Encode `approve(address,uint256)` calldata (0x-prefixed hex).
fn encode_approve(spender: Address, value: U256) -> String {
    let mut out = Vec::with_capacity(4 + 32 + 32);
    out.extend_from_slice(&APPROVE_SELECTOR);
    // address → 32-byte word, left-padded with 12 zero bytes.
    let mut word = [0u8; 32];
    word[12..].copy_from_slice(spender.as_slice());
    out.extend_from_slice(&word);
    // uint256 → 32-byte big-endian word.
    out.extend_from_slice(&value.to_be_bytes::<32>());
    format!("0x{}", hex::encode(out))
}

/// Poll `rpc_url` for the receipt of `tx_hash`, returning once it's mined (or
/// erroring on revert / after `timeout_secs`). Moves the app's hand-rolled
/// `eth_getTransactionReceipt` polling loop into the SDK.
#[uniffi::export(async_runtime = "tokio")]
pub async fn wait_for_receipt(
    rpc_url: String,
    tx_hash: String,
    timeout_secs: u64,
) -> Result<TxReceipt, ClientError> {
    let client = reqwest::Client::new();
    let start = std::time::Instant::now();
    loop {
        let receipt = rpc_call(
            &client,
            &rpc_url,
            "eth_getTransactionReceipt",
            serde_json::json!([tx_hash]),
        )
        .await?;

        if !receipt.is_null() {
            let success = receipt.get("status").and_then(|s| s.as_str()) == Some("0x1");
            return Ok(TxReceipt {
                success,
                gas_used: hex_field_to_dec(&receipt, "gasUsed"),
                effective_gas_price: hex_field_to_dec(&receipt, "effectiveGasPrice"),
            });
        }

        if start.elapsed().as_secs() >= timeout_secs {
            return Err(ClientError::NetworkError {
                reason: format!("timed out waiting for receipt of {tx_hash} after {timeout_secs}s"),
            });
        }
        tokio::time::sleep(std::time::Duration::from_millis(RECEIPT_POLL_INTERVAL_MS)).await;
    }
}

/// Read the winning pool hash from a settled `payForMerkleTree` transaction, so
/// the caller can pass it to `finalize_upload_merkle`. Finds the
/// `MerklePaymentMade` log emitted by `vault_address` in the receipt and returns
/// its indexed `winnerPoolHash` (topic1), 0x-prefixed. Replaces the app's
/// hand-rolled log scan.
#[uniffi::export(async_runtime = "tokio")]
pub async fn merkle_winner_pool_hash(
    rpc_url: String,
    vault_address: String,
    tx_hash: String,
) -> Result<String, ClientError> {
    let client = reqwest::Client::new();
    let receipt = rpc_call(
        &client,
        &rpc_url,
        "eth_getTransactionReceipt",
        serde_json::json!([tx_hash]),
    )
    .await?;
    if receipt.is_null() {
        return Err(ClientError::NotFound {
            reason: format!("no receipt for {tx_hash}"),
        });
    }

    let vault = vault_address.to_lowercase();
    let logs = receipt
        .get("logs")
        .and_then(|l| l.as_array())
        .ok_or_else(|| ClientError::NetworkError {
            reason: "receipt has no logs array".into(),
        })?;

    for log in logs {
        let addr = log
            .get("address")
            .and_then(|a| a.as_str())
            .unwrap_or("")
            .to_lowercase();
        let topics = match log.get("topics").and_then(|t| t.as_array()) {
            Some(t) => t,
            None => continue,
        };
        let topic0 = topics.first().and_then(|t| t.as_str()).unwrap_or("");
        if addr == vault && topic0.eq_ignore_ascii_case(MERKLE_PAYMENT_MADE_TOPIC0) {
            // topics[1] is the indexed winnerPoolHash.
            if let Some(winner) = topics.get(1).and_then(|t| t.as_str()) {
                return Ok(winner.to_string());
            }
        }
    }
    Err(ClientError::NotFound {
        reason: format!("no MerklePaymentMade event from {vault_address} in {tx_hash}"),
    })
}

/// Minimal JSON-RPC POST returning the `result` value (or `Null` if absent).
async fn rpc_call(
    client: &reqwest::Client,
    url: &str,
    method: &str,
    params: serde_json::Value,
) -> Result<serde_json::Value, ClientError> {
    let body = serde_json::json!({ "jsonrpc": "2.0", "id": 1, "method": method, "params": params });
    let resp =
        client
            .post(url)
            .json(&body)
            .send()
            .await
            .map_err(|e| ClientError::NetworkError {
                reason: format!("RPC {method} request failed: {e}"),
            })?;
    let json: serde_json::Value = resp.json().await.map_err(|e| ClientError::NetworkError {
        reason: format!("RPC {method} decode failed: {e}"),
    })?;
    if let Some(err) = json.get("error") {
        if !err.is_null() {
            return Err(ClientError::NetworkError {
                reason: format!("RPC {method} error: {err}"),
            });
        }
    }
    Ok(json
        .get("result")
        .cloned()
        .unwrap_or(serde_json::Value::Null))
}

/// Read a `0x`-hex field off a JSON object as a base-10 decimal string.
fn hex_field_to_dec(obj: &serde_json::Value, field: &str) -> String {
    let hex = obj
        .get(field)
        .and_then(|v| v.as_str())
        .unwrap_or("0x0")
        .trim_start_matches("0x");
    U256::from_str_radix(hex, 16)
        .map(|n| n.to_string())
        .unwrap_or_else(|_| "0".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn network_info_known_networks() {
        let one = network_info("arbitrum-one".into()).unwrap();
        assert_eq!(one.chain_id, 42161);
        assert_eq!(
            one.token_address.to_lowercase(),
            "0xa78d8321b20c4ef90ecd72f2588aa985a4bdb684"
        );
        assert_eq!(
            one.vault_address.to_lowercase(),
            "0x9a3ecac693b699fc0b2b6a50b5549e50c2320a26"
        );
        assert!(one.rpc_url.starts_with("https://"));

        let sep = network_info("arbitrum-sepolia-test".into()).unwrap();
        assert_eq!(sep.chain_id, 421614);
        // Aliases resolve to the same networks.
        assert_eq!(network_info("arbitrum".into()).unwrap().chain_id, 42161);
        assert_eq!(
            network_info("arbitrum-sepolia".into()).unwrap().chain_id,
            421614
        );
        assert!(network_info("mainnet".into()).is_err());
    }

    #[test]
    fn approve_calldata_matches_known_vector() {
        // Byte-for-byte parity with the app's hand-rolled EthCalldata.approve,
        // which was verified against `cast calldata`. Selector 0x095ea7b3,
        // spender left-padded to 32 bytes, amount big-endian 32 bytes.
        let spender: Address = "0x9A3EcAc693b699Fc0B2B6A50B5549e50c2320A26"
            .parse()
            .unwrap();
        let data = encode_approve(spender, U256::from(0u64));
        assert_eq!(
            data,
            "0x095ea7b3\
             0000000000000000000000009a3ecac693b699fc0b2b6a50b5549e50c2320a26\
             0000000000000000000000000000000000000000000000000000000000000000"
        );

        // Non-zero amount encodes big-endian in the low bytes.
        let data = encode_approve(spender, U256::from(1_000_000u64));
        assert!(data.starts_with("0x095ea7b3"));
        assert!(data.ends_with("00000000000000000000000000000000000000000000000000000000000f4240"));
        // selector(4) + 2 words(64) = 68 bytes = 136 hex + "0x".
        assert_eq!(data.len(), 2 + 136);
    }

    #[test]
    fn merkle_topic0_is_keccak_of_event_signature() {
        // Prove the hardcoded topic0 from first principles rather than trusting
        // a copied constant: it must equal keccak256 of the canonical event
        // signature. If the event ABI ever changes, this fails loudly.
        use tiny_keccak::{Hasher, Keccak};
        let mut k = Keccak::v256();
        k.update(b"MerklePaymentMade(bytes32,uint8,uint256,uint64)");
        let mut out = [0u8; 32];
        k.finalize(&mut out);
        assert_eq!(
            format!("0x{}", hex::encode(out)),
            MERKLE_PAYMENT_MADE_TOPIC0
        );
    }

    #[test]
    fn hex_field_to_dec_parses_and_defaults() {
        let obj = serde_json::json!({ "gasUsed": "0xf4240", "zero": "0x0" });
        assert_eq!(hex_field_to_dec(&obj, "gasUsed"), "1000000");
        assert_eq!(hex_field_to_dec(&obj, "zero"), "0");
        assert_eq!(hex_field_to_dec(&obj, "missing"), "0");
    }
}
