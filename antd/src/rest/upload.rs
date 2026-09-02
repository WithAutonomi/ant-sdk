use std::collections::HashMap;
use std::sync::Arc;

use axum::extract::State;
use axum::Json;

use crate::error::AntdError;
use crate::evm_defaults;
use crate::state::AppState;
use crate::types::*;

/// Build a [`PrepareUploadResponse`] from a prepared upload, matching on the
/// payment variant (wave-batch vs merkle) and serialising the appropriate fields.
///
/// The EVM addresses returned to the external signer are resolved through
/// [`evm_defaults::resolve`] using the daemon's configured network — the same
/// path that constructs the daemon's own internal-wallet client. Reading the
/// raw `EVM_RPC_URL` / `EVM_PAYMENT_TOKEN_ADDRESS` / `EVM_PAYMENT_VAULT_ADDRESS`
/// env vars here was a bug: an antd launched without those env vars (the
/// expected mainnet shape, where the preset alone is enough) returned an
/// empty token address and `http://127.0.0.1:8545` as the RPC URL, causing
/// external signers (e.g. indelible) to call ERC-20 `approve` against the
/// zero address and revert at gas estimation.
fn build_prepare_response(
    upload_id: String,
    prepared: &ant_core::data::PreparedUpload,
    network: &str,
) -> Result<PrepareUploadResponse, AntdError> {
    let evm_cfg = evm_defaults::resolve(network);
    let rpc_url = evm_cfg.rpc_url;
    let payment_token_address = evm_cfg.token_addr;
    let payment_vault_address = evm_cfg.vault_addr;

    // Already-stored preflight (added in antd 0.10.0): surface how many chunks
    // were skipped because they were already on-network, so external signers can
    // reconcile the (possibly cheaper) payment against the full file size.
    let total_chunks = prepared.total_chunks;
    let already_stored_count = prepared.already_stored_addresses.len();

    match &prepared.payment_info {
        ant_core::data::ExternalPaymentInfo::WaveBatch { payment_intent, .. } => {
            let payments: Vec<PaymentEntry> = payment_intent
                .payments
                .iter()
                .map(|(quote_hash, rewards_addr, amount)| PaymentEntry {
                    quote_hash: format!("{:#x}", quote_hash),
                    rewards_address: format!("{:#x}", rewards_addr),
                    amount: amount.to_string(),
                })
                .collect();

            Ok(PrepareUploadResponse {
                upload_id,
                payment_type: "wave_batch".into(),
                payments,
                depth: None,
                pool_commitments: None,
                merkle_payment_timestamp: None,
                merkle_batches: None,
                total_amount: payment_intent.total_amount.to_string(),
                payment_vault_address,
                payment_token_address,
                rpc_url,
                total_chunks,
                already_stored_count,
            })
        }
        ant_core::data::ExternalPaymentInfo::Merkle {
            prepared_batches, ..
        } => {
            let merkle_batches = merkle_batch_entries(prepared_batches);
            // The legacy singular fields mirror the single batch so
            // pre-multi-batch clients keep working when the upload fits one
            // merkle tree; multi-batch prepares omit them (a legacy client
            // cannot pay a fraction of the file).
            let (depth, pool_commitments, merkle_payment_timestamp) =
                match merkle_batches.as_slice() {
                    [single] => (
                        Some(single.depth),
                        Some(single.pool_commitments.clone()),
                        Some(single.merkle_payment_timestamp),
                    ),
                    _ => (None, None, None),
                };

            Ok(PrepareUploadResponse {
                upload_id,
                payment_type: "merkle".into(),
                payments: vec![],
                depth,
                pool_commitments,
                merkle_payment_timestamp,
                merkle_batches: Some(merkle_batches),
                total_amount: "0".into(),
                payment_vault_address,
                payment_token_address,
                rpc_url,
                total_chunks,
                already_stored_count,
            })
        }
    }
}

/// Map ant-core's prepared merkle batches to the wire shape — one entry per
/// `payForMerkleTree2()` call the signer must make (ADR-0003 splits uploads
/// larger than one merkle tree, 256 fresh chunks ≈ 1 GiB, into several
/// batches).
pub(crate) fn merkle_batch_entries(
    batches: &[ant_core::data::PreparedMerkleBatch],
) -> Vec<MerkleBatchEntry> {
    batches
        .iter()
        .map(|batch| MerkleBatchEntry {
            depth: batch.depth,
            pool_commitments: pool_commitment_entries(batch),
            merkle_payment_timestamp: batch.merkle_payment_timestamp,
        })
        .collect()
}

/// Serialize one batch's pool commitments for the JSON/proto response.
/// Each candidate has rewards_address + price (maps to the contract's amount).
pub(crate) fn pool_commitment_entries(
    batch: &ant_core::data::PreparedMerkleBatch,
) -> Vec<PoolCommitmentEntry> {
    batch
        .pool_commitments
        .iter()
        .map(|pc| PoolCommitmentEntry {
            pool_hash: format!("0x{}", hex::encode(pc.pool_hash)),
            candidates: pc
                .candidates
                .iter()
                .map(|c| CandidateNodeEntry {
                    rewards_address: format!("0x{}", hex::encode(c.rewards_address)),
                    amount: c.price.to_string(),
                })
                .collect(),
        })
        .collect()
}

/// Decode a 0x-prefixed (or bare) hex winner pool hash into 32 bytes.
fn decode_winner_pool_hash(hex_str: &str) -> Result<[u8; 32], AntdError> {
    hex::decode(hex_str.trim_start_matches("0x"))
        .map_err(|e| AntdError::BadRequest(format!("invalid winner_pool_hash {hex_str}: {e}")))?
        .try_into()
        .map_err(|_| AntdError::BadRequest("winner_pool_hash must be 32 bytes".into()))
}

/// Resolve the winner-hash input (legacy single `winner_pool_hash` vs the
/// index-aligned `winner_pool_hashes` list) into the `Vec<Option<[u8; 32]>>`
/// that ant-core's multi-batch finalize takes; `None` entries mark batches
/// the signer never paid. Pure validation — call this BEFORE consuming the
/// prepared upload, so a bad request (typo'd hash, miscounted list) leaves
/// the already-paid-for server-side state intact and retryable.
pub(crate) fn resolve_winner_pool_hashes(
    batch_count: usize,
    single: Option<&str>,
    list: Option<&[Option<String>]>,
) -> Result<Vec<Option<[u8; 32]>>, AntdError> {
    match (single, list) {
        (Some(_), Some(_)) => Err(AntdError::BadRequest(
            "pass either winner_pool_hash or winner_pool_hashes, not both".into(),
        )),
        (Some(hash), None) => {
            if batch_count != 1 {
                return Err(AntdError::BadRequest(format!(
                    "upload has {batch_count} merkle payment batches; pass winner_pool_hashes \
                     with one entry per batch (winner_pool_hash is single-batch only)"
                )));
            }
            Ok(vec![Some(decode_winner_pool_hash(hash)?)])
        }
        (None, Some(list)) => {
            if list.len() != batch_count {
                return Err(AntdError::BadRequest(format!(
                    "winner_pool_hashes has {} entries but the upload has {batch_count} merkle \
                     payment batches; entries are index-aligned with the prepare response's \
                     merkle_batches (null/empty = unpaid batch)",
                    list.len()
                )));
            }
            list.iter()
                .map(|entry| match entry.as_deref() {
                    None | Some("") => Ok(None),
                    Some(hash) => decode_winner_pool_hash(hash).map(Some),
                })
                .collect()
        }
        (None, None) => Err(AntdError::BadRequest(
            "winner_pool_hashes required for merkle upload (this upload used merkle payment)"
                .into(),
        )),
    }
}

/// Validate + parse the wave-batch `tx_hashes` map against the payments the
/// prepare reported. Pure validation — call this BEFORE consuming the
/// prepared upload, so a bad request leaves the server-side state intact and
/// retryable.
///
/// An empty map is valid exactly when prepare reported no payments (every
/// chunk already stored on the network — ant-sdk#233). Otherwise every
/// reported quote must have a receipt: ant-core rejects a missing one only
/// after the upload has been consumed, so catch it here. Extra entries for
/// unknown quotes are tolerated (ant-core ignores them).
pub(crate) fn resolve_wave_tx_hashes(
    expected_quotes: &[evmlib::common::QuoteHash],
    tx_hashes: &HashMap<String, String>,
) -> Result<HashMap<evmlib::common::QuoteHash, evmlib::common::TxHash>, AntdError> {
    if tx_hashes.is_empty() && !expected_quotes.is_empty() {
        return Err(AntdError::BadRequest(format!(
            "tx_hashes required for wave-batch upload: prepare reported {} payment(s); an empty \
             map is only valid when every chunk is already stored",
            expected_quotes.len()
        )));
    }

    let tx_hash_map: HashMap<evmlib::common::QuoteHash, evmlib::common::TxHash> = tx_hashes
        .iter()
        .map(|(quote_hex, tx_hex)| {
            let quote_bytes: [u8; 32] = hex::decode(quote_hex.trim_start_matches("0x"))
                .map_err(|e| AntdError::BadRequest(format!("invalid quote_hash {quote_hex}: {e}")))?
                .try_into()
                .map_err(|_| AntdError::BadRequest("quote_hash must be 32 bytes".into()))?;
            let tx_bytes: [u8; 32] = hex::decode(tx_hex.trim_start_matches("0x"))
                .map_err(|e| AntdError::BadRequest(format!("invalid tx_hash {tx_hex}: {e}")))?
                .try_into()
                .map_err(|_| AntdError::BadRequest("tx_hash must be 32 bytes".into()))?;
            Ok((quote_bytes.into(), tx_bytes.into()))
        })
        .collect::<Result<_, AntdError>>()?;

    if let Some(missing) = expected_quotes
        .iter()
        .find(|quote| !tx_hash_map.contains_key(*quote))
    {
        return Err(AntdError::BadRequest(format!(
            "tx_hashes is missing a receipt for quote {} (prepare reported a payment for it)",
            hex::encode(missing)
        )));
    }

    Ok(tx_hash_map)
}

/// Phase 1: Prepare a file upload for external signing.
///
/// Encrypts the file, collects storage quotes from the network, and returns
/// payment details with an upload_id. The caller signs and submits the EVM
/// payment transaction externally, then calls finalize with the result.
///
/// For files with < 64 chunks, returns `payment_type: "wave_batch"` with
/// per-quote payment entries for `payForQuotes()`.
///
/// For files with >= 64 chunks, returns `payment_type: "merkle"` with
/// depth, pool commitments, and timestamp for `payForMerkleTree2()`.
pub async fn prepare_upload(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PrepareUploadRequest>,
) -> Result<Json<PrepareUploadResponse>, AntdError> {
    let path = std::path::PathBuf::from(&req.path)
        .canonicalize()
        .map_err(|e| {
            tracing::warn!(path = %req.path, error = %e, "invalid prepare-upload path");
            AntdError::BadRequest("invalid path".into())
        })?;

    let visibility = parse_visibility(req.visibility.as_deref()).map_err(AntdError::BadRequest)?;

    let client = state.client.clone();
    let prepared = tokio::spawn(async move {
        client
            .file_prepare_upload_with_visibility(&path, visibility)
            .await
            .map_err(AntdError::from_core)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    // Generate a unique upload ID and store the prepared state
    let upload_id = hex::encode(rand::random::<[u8; 16]>());
    let response = build_prepare_response(upload_id.clone(), &prepared, &state.network)?;

    state.pending_uploads.lock().await.insert(
        upload_id,
        crate::state::TimestampedUpload {
            prepared,
            created_at: std::time::Instant::now(),
        },
    );

    Ok(Json(response))
}

/// Phase 1 (data): Prepare an in-memory data upload for external signing.
///
/// Same as prepare_upload but takes base64-encoded data instead of a file path.
pub async fn prepare_data_upload(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PrepareDataUploadRequest>,
) -> Result<Json<PrepareUploadResponse>, AntdError> {
    use base64::engine::general_purpose::STANDARD as BASE64;
    use base64::Engine;
    use bytes::Bytes;

    let visibility = parse_visibility(req.visibility.as_deref()).map_err(AntdError::BadRequest)?;

    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    let client = state.client.clone();
    let prepared = tokio::spawn(async move {
        client
            .data_prepare_upload_with_visibility(Bytes::from(data), visibility)
            .await
            .map_err(AntdError::from_core)
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    let upload_id = hex::encode(rand::random::<[u8; 16]>());
    let response = build_prepare_response(upload_id.clone(), &prepared, &state.network)?;

    state.pending_uploads.lock().await.insert(
        upload_id,
        crate::state::TimestampedUpload {
            prepared,
            created_at: std::time::Instant::now(),
        },
    );

    Ok(Json(response))
}

/// Phase 2: Finalize an upload after external payment.
///
/// For wave-batch uploads, takes `tx_hashes` (map of quote_hash → tx_hash).
/// When prepare reported no payments (every chunk already stored), an empty
/// map finalizes without any on-chain payment and returns the DataMap.
/// For merkle uploads, takes `winner_pool_hashes` — one `MerklePaymentMade`
/// winner hash per prepared batch, index-aligned with the prepare response's
/// `merkle_batches` (`winner_pool_hash` is still accepted for single-batch
/// uploads). Null/empty entries mark batches the signer never paid: paid
/// batches store and the unpaid chunks surface via the `PARTIAL_UPLOAD`
/// error.
///
/// The handler detects the payment type from the stored prepared upload and
/// validates the request against it BEFORE consuming the stored state, so a
/// bad request (typo'd hash, miscounted list) errors while the already
/// paid-for upload stays present and retryable.
pub async fn finalize_upload(
    State(state): State<Arc<AppState>>,
    Json(req): Json<FinalizeUploadRequest>,
) -> Result<Json<FinalizeUploadResponse>, AntdError> {
    enum PaymentShape {
        Wave {
            expected_quotes: Vec<evmlib::common::QuoteHash>,
        },
        Merkle {
            batch_count: usize,
        },
    }
    enum PaymentArtefacts {
        Wave(HashMap<evmlib::common::QuoteHash, evmlib::common::TxHash>),
        Merkle(Vec<Option<[u8; 32]>>),
    }
    let not_found = |id: &str| {
        AntdError::NotFound(format!(
            "upload_id {id} not found — it may have expired or already been finalized"
        ))
    };

    // Peek at the stored upload's payment shape without consuming it.
    let shape = {
        let pending = state.pending_uploads.lock().await;
        match &pending
            .get(&req.upload_id)
            .ok_or_else(|| not_found(&req.upload_id))?
            .prepared
            .payment_info
        {
            ant_core::data::ExternalPaymentInfo::WaveBatch { payment_intent, .. } => {
                PaymentShape::Wave {
                    expected_quotes: payment_intent
                        .payments
                        .iter()
                        .map(|(quote_hash, _, _)| *quote_hash)
                        .collect(),
                }
            }
            ant_core::data::ExternalPaymentInfo::Merkle {
                prepared_batches, ..
            } => PaymentShape::Merkle {
                batch_count: prepared_batches.len(),
            },
        }
    };

    // Validate + parse the payment artefacts against that shape.
    let artefacts = match shape {
        PaymentShape::Wave { expected_quotes } => {
            let tx_hashes_raw = req.tx_hashes.ok_or_else(|| {
                AntdError::BadRequest(
                    "tx_hashes required for wave-batch upload (this upload used wave_batch \
                     payment); pass an empty object when prepare reported no payments"
                        .into(),
                )
            })?;

            if req.winner_pool_hash.is_some() || req.winner_pool_hashes.is_some() {
                return Err(AntdError::BadRequest(
                    "winner_pool_hash(es) not applicable for wave-batch upload".into(),
                ));
            }

            PaymentArtefacts::Wave(resolve_wave_tx_hashes(&expected_quotes, &tx_hashes_raw)?)
        }
        PaymentShape::Merkle { batch_count } => {
            if req.tx_hashes.is_some() {
                return Err(AntdError::BadRequest(
                    "tx_hashes not applicable for merkle upload".into(),
                ));
            }
            PaymentArtefacts::Merkle(resolve_winner_pool_hashes(
                batch_count,
                req.winner_pool_hash.as_deref(),
                req.winner_pool_hashes.as_deref(),
            )?)
        }
    };

    // Input is known-good: consume the stored upload and finalize.
    let timestamped = state
        .pending_uploads
        .lock()
        .await
        .remove(&req.upload_id)
        .ok_or_else(|| not_found(&req.upload_id))?;
    let prepared = timestamped.prepared;
    let store_on_network = req.store_data_map;
    let client = state.client.clone();

    let (data_map_hex, address, data_map_address, chunks_stored) = tokio::spawn(async move {
        let result = match artefacts {
            PaymentArtefacts::Wave(tx_hash_map) => client
                .finalize_upload(prepared, &tx_hash_map)
                .await
                .map_err(AntdError::from_core)?,
            PaymentArtefacts::Merkle(winner_pool_hashes) => client
                .finalize_upload_merkle_multi(prepared, winner_pool_hashes)
                .await
                .map_err(AntdError::from_core)?,
        };

        let data_map_bytes = rmp_serde::to_vec(&result.data_map)
            .map_err(|e| AntdError::Internal(format!("serialize data map: {e}")))?;
        let data_map_hex = hex::encode(data_map_bytes);

        let address = if store_on_network {
            let addr = client
                .data_map_store(&result.data_map)
                .await
                .map_err(AntdError::from_core)?;
            Some(hex::encode(addr))
        } else {
            None
        };

        let data_map_address = result.data_map_address.map(hex::encode);

        Ok::<_, AntdError>((
            data_map_hex,
            address,
            data_map_address,
            result.chunks_stored,
        ))
    })
    .await
    .map_err(|e| AntdError::Internal(format!("task failed: {e}")))??;

    Ok(Json(FinalizeUploadResponse {
        data_map: data_map_hex,
        address,
        data_map_address,
        chunks_stored: chunks_stored as u64,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    const HASH_A: &str = "0x1111111111111111111111111111111111111111111111111111111111111111";
    const HASH_B: &str = "2222222222222222222222222222222222222222222222222222222222222222";

    #[test]
    fn legacy_single_hash_resolves_for_one_batch() {
        let winners = resolve_winner_pool_hashes(1, Some(HASH_A), None).unwrap();
        assert_eq!(winners, vec![Some([0x11u8; 32])]);
    }

    #[test]
    fn legacy_single_hash_rejected_for_multi_batch() {
        let err = resolve_winner_pool_hashes(3, Some(HASH_A), None).unwrap_err();
        assert!(matches!(err, AntdError::BadRequest(_)), "got {err:?}");
        assert!(err.to_string().contains("3 merkle payment batches"));
    }

    #[test]
    fn list_resolves_with_unpaid_markers() {
        // Null and "" both mark unpaid batches; bare (no-0x) hex accepted.
        let list = vec![
            Some(HASH_A.to_string()),
            None,
            Some(String::new()),
            Some(HASH_B.to_string()),
        ];
        let winners = resolve_winner_pool_hashes(4, None, Some(&list)).unwrap();
        assert_eq!(
            winners,
            vec![Some([0x11u8; 32]), None, None, Some([0x22u8; 32])]
        );
    }

    #[test]
    fn list_count_mismatch_rejected() {
        let list = vec![Some(HASH_A.to_string())];
        let err = resolve_winner_pool_hashes(2, None, Some(&list)).unwrap_err();
        assert!(matches!(err, AntdError::BadRequest(_)), "got {err:?}");
        assert!(err.to_string().contains("1 entries"));
    }

    #[test]
    fn both_inputs_rejected() {
        let list = vec![Some(HASH_A.to_string())];
        let err = resolve_winner_pool_hashes(1, Some(HASH_A), Some(&list)).unwrap_err();
        assert!(err.to_string().contains("not both"));
    }

    #[test]
    fn neither_input_rejected() {
        let err = resolve_winner_pool_hashes(1, None, None).unwrap_err();
        assert!(err.to_string().contains("winner_pool_hashes required"));
    }

    #[test]
    fn bad_hex_rejected_without_consuming_anything() {
        let err = resolve_winner_pool_hashes(1, Some("0xnothex"), None).unwrap_err();
        assert!(matches!(err, AntdError::BadRequest(_)), "got {err:?}");
        let err = resolve_winner_pool_hashes(1, Some("0x1111"), None).unwrap_err();
        assert!(err.to_string().contains("32 bytes"));
    }

    #[test]
    fn finalize_request_json_accepts_null_and_empty_entries() {
        let req: FinalizeUploadRequest =
            serde_json::from_str(r#"{"upload_id":"abc","winner_pool_hashes":["0x11",null,""]}"#)
                .unwrap();
        assert_eq!(
            req.winner_pool_hashes,
            Some(vec![Some("0x11".into()), None, Some(String::new())])
        );
        assert!(req.winner_pool_hash.is_none());
        assert!(req.tx_hashes.is_none());
    }

    // ── resolve_wave_tx_hashes (ant-sdk#233) ──

    fn quote(byte: u8) -> evmlib::common::QuoteHash {
        [byte; 32].into()
    }

    fn hashes(entries: &[(&str, &str)]) -> HashMap<String, String> {
        entries
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn empty_map_valid_when_no_payments_expected() {
        // The all-already-stored case: prepare reported zero payments, so an
        // empty map finalizes without any on-chain payment.
        let map = resolve_wave_tx_hashes(&[], &HashMap::new()).unwrap();
        assert!(map.is_empty());
    }

    #[test]
    fn empty_map_rejected_when_payments_expected() {
        let err = resolve_wave_tx_hashes(&[quote(0x11)], &HashMap::new()).unwrap_err();
        assert!(matches!(err, AntdError::BadRequest(_)), "got {err:?}");
        assert!(err.to_string().contains("1 payment"));
    }

    #[test]
    fn missing_receipt_rejected_before_consuming_upload() {
        // A map that covers only some reported payments would only fail
        // inside ant-core, after the upload_id had been consumed.
        let provided = hashes(&[(HASH_A, HASH_B)]);
        let err = resolve_wave_tx_hashes(&[quote(0x11), quote(0x33)], &provided).unwrap_err();
        assert!(matches!(err, AntdError::BadRequest(_)), "got {err:?}");
        assert!(err.to_string().contains(&hex::encode([0x33u8; 32])));
    }

    #[test]
    fn full_coverage_resolves_with_extra_entries_tolerated() {
        // 0x-prefixed and bare hex both accepted; unknown extras ignored by
        // ant-core, so they pass validation too.
        const HASH_C: &str = "0x3333333333333333333333333333333333333333333333333333333333333333";
        let provided = hashes(&[(HASH_A, HASH_B), (HASH_B, HASH_A), (HASH_C, HASH_A)]);
        let map = resolve_wave_tx_hashes(&[quote(0x11), quote(0x22)], &provided).unwrap();
        assert_eq!(map.len(), 3);
        assert_eq!(map.get(&quote(0x11)), Some(&[0x22u8; 32].into()));
    }

    #[test]
    fn bad_hex_rejected() {
        let err =
            resolve_wave_tx_hashes(&[quote(0x11)], &hashes(&[("nothex", HASH_B)])).unwrap_err();
        assert!(err.to_string().contains("invalid quote_hash"));
        let err =
            resolve_wave_tx_hashes(&[quote(0x11)], &hashes(&[(HASH_A, "0x1111")])).unwrap_err();
        assert!(err.to_string().contains("tx_hash must be 32 bytes"));
    }
}
