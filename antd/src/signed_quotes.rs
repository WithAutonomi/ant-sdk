//! Signed-quote exposure + offline verification (hosted payments, V2-854).
//!
//! Two halves:
//!
//! 1. **Exposure** — Prepare* responses can opt in (`include_signed_quotes`)
//!    to carrying the full signed [`PaymentQuote`]s and their ADR-0004
//!    commitment sidecars alongside the `payments[]` triples. The wave-batch
//!    prepare path already retains both in the pending-upload session state;
//!    this module only serializes them out. (Merkle candidate exposure is
//!    blocked upstream: `PreparedMerkleBatch` keeps its candidate pools
//!    private and ant-core deliberately discards resolved candidate
//!    commitments — see V2-854 open question 1.)
//!
//! 2. **Verification** — `/v1/verify/quotes` (and its gRPC twin) verifies a
//!    batch offline: quote-hash recomputation, ML-DSA-65 signature,
//!    paid-fields equality, and the ADR-0004 resolve-before-pay binding with
//!    exact on-curve pricing. This is a port of ant-core's client-side
//!    `quote_commitment_binding_is_valid` gate, run by "the party about to
//!    pay" — in hosted mode, the payment gateway via its own antd.
//!
//! Quotes and sidecars travel as opaque base64(msgpack) bytes end-to-end:
//! antd emits them at prepare time and antd parses them at verify time —
//! intermediate consumers never decode them.

use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use evmlib::common::{Address as RewardsAddress, Amount};
use evmlib::PaymentQuote;
use std::collections::{HashMap, HashSet};
use std::time::UNIX_EPOCH;

use ant_protocol::payment::commitment::MAX_COMMITMENT_SIDECAR_BYTES;
use ant_protocol::payment::{
    calculate_price, commitment_hash, verify_commitment_signature, verify_quote_signature,
    StorageCommitment, MAX_COMMITMENT_KEY_COUNT,
};

use crate::types::{SignedQuoteEntry, VerifyQuoteEntry, VerifyQuoteVerdict};

/// Upper bound on a serialized signed quote (ML-DSA-65 pubkey ≈ 2 KB +
/// signature ≈ 3.3 KB + fields). Real quotes are ~5.5 KB; anything larger is
/// rejected before deserialization work.
const MAX_SIGNED_QUOTE_BYTES: usize = 16 * 1024;

/// Cap on entries per VerifyQuotes call (REST and gRPC): a 256-chunk wave
/// batch (the ADR-0003 merkle threshold region) fits comfortably; anything
/// larger is likely abuse of a CPU-bound endpoint (each entry costs an
/// ML-DSA-65 verification or two).
pub(crate) const MAX_VERIFY_ENTRIES: usize = 1024;

/// The wave-batch paid amount is the signed quote price times this
/// multiplier: single-quote payments (V2-619) pay only the median quote of
/// the close group, at 3x, keeping per-chunk node economics equivalent to
/// paying the group. Mirrors ant-core's `SINGLE_NODE_PAYMENT_MULTIPLIER`
/// (`pub(crate)`, not importable) and the 3x documented on
/// `ant_protocol::payment::single_node::QuotePaymentInfo`. If the protocol
/// ever changes the multiplier, this verifier versions with the antd release
/// that adopts it.
const SINGLE_NODE_PAYMENT_MULTIPLIER: u64 = 3;

/// Build the opt-in `signed_quotes` response entries for one prepared quote
/// set, restricted to the quotes that are actually being paid: the network
/// quotes a whole close group per chunk (~7 peers) but the payment intent
/// selects a subset (one quote per chunk since single-quote payments, V2-619),
/// and `payments[]` carries only those. Emitting the unpaid quotes would hand
/// the verifier entries with no payment triple to check against.
///
/// `paid` is the set of quote hashes appearing in the `payments[]` triples.
/// `sidecars` is ant-core's *compacted* vector — baseline quotes contribute
/// nothing, so it is NOT index-aligned with the quotes. Association is by
/// `commitment_hash(sidecar) == quote.commitment_pin`, mirroring how the
/// sidecars were validated at prepare time.
pub(crate) fn entries_for_quotes<'a>(
    quotes: impl IntoIterator<Item = &'a PaymentQuote>,
    sidecars: &[Vec<u8>],
    paid: &HashSet<evmlib::common::QuoteHash>,
) -> Result<Vec<SignedQuoteEntry>, String> {
    let mut by_pin: HashMap<[u8; 32], String> = HashMap::new();
    for blob in sidecars {
        // Sidecars were already validated by ant-core at prepare time; a blob
        // that no longer parses would only orphan its quote's pin, which the
        // verify side reports as unresolvable — so skip, don't fail.
        if blob.len() > MAX_COMMITMENT_SIDECAR_BYTES {
            continue;
        }
        let Ok(commitment) = rmp_serde::from_slice::<StorageCommitment>(blob) else {
            continue;
        };
        if let Some(pin) = commitment_hash(&commitment) {
            by_pin.insert(pin, BASE64.encode(blob));
        }
    }

    let mut out = Vec::new();
    for quote in quotes {
        if !paid.contains(&quote.hash()) {
            continue;
        }
        let bytes =
            rmp_serde::to_vec(quote).map_err(|e| format!("serializing signed quote: {e}"))?;
        out.push(SignedQuoteEntry {
            quote_hash: format!("{:#x}", quote.hash()),
            quote: BASE64.encode(&bytes),
            commitment_sidecar: quote
                .commitment_pin
                .and_then(|pin| by_pin.get(&pin).cloned()),
        });
    }
    Ok(out)
}

/// Build `signed_quotes` entries for a whole wave-batch upload: one entry per
/// `payment_intent.payments` triple, sourced from the prepared chunks' full
/// quote sets (quote hashes are globally unique across chunks).
pub(crate) fn entries_for_prepared_chunks(
    chunks: &[ant_core::data::PreparedChunk],
    payment_intent: &ant_core::data::PaymentIntent,
) -> Result<Vec<SignedQuoteEntry>, String> {
    let paid: HashSet<evmlib::common::QuoteHash> = payment_intent
        .payments
        .iter()
        .map(|(quote_hash, _, _)| *quote_hash)
        .collect();
    let mut out = Vec::new();
    for chunk in chunks {
        out.extend(entries_for_quotes(
            chunk.peer_quotes.iter().map(|(_, q)| q),
            &chunk.commitment_sidecars,
            &paid,
        )?);
    }
    Ok(out)
}

/// Verify one `/pay`-shaped entry offline. Never panics on untrusted bytes;
/// the verdict carries the first failing rule by name, plus the fields the
/// gateway's policy layer needs (extracted as soon as the quote decodes, even
/// when a later check fails, so callers can see what the quote claimed).
pub(crate) fn verify_entry(entry: &VerifyQuoteEntry) -> VerifyQuoteVerdict {
    let mut verdict = VerifyQuoteVerdict {
        quote_hash: entry.quote_hash.clone(),
        valid: false,
        error: None,
        timestamp_unix_secs: None,
        content: None,
        price: None,
        rewards_address: None,
        committed_key_count: None,
        pinned: None,
    };
    match verify_inner(entry, &mut verdict) {
        Ok(()) => verdict.valid = true,
        Err(msg) => verdict.error = Some(msg),
    }
    verdict
}

fn verify_inner(entry: &VerifyQuoteEntry, verdict: &mut VerifyQuoteVerdict) -> Result<(), String> {
    // Decode the opaque quote. Cap before parsing: bound the deserialize work
    // a malicious caller can force.
    let bytes = BASE64
        .decode(&entry.signed_quote)
        .map_err(|e| format!("signed_quote is not valid base64: {e}"))?;
    if bytes.len() > MAX_SIGNED_QUOTE_BYTES {
        return Err(format!(
            "signed_quote is {} bytes, exceeds {MAX_SIGNED_QUOTE_BYTES}",
            bytes.len()
        ));
    }
    let quote: PaymentQuote = rmp_serde::from_slice(&bytes)
        .map_err(|e| format!("signed_quote did not deserialize as a PaymentQuote: {e}"))?;

    verdict.timestamp_unix_secs = quote
        .timestamp
        .duration_since(UNIX_EPOCH)
        .ok()
        .map(|d| d.as_secs());
    verdict.content = Some(hex::encode(quote.content.0));
    verdict.price = Some(quote.price.to_string());
    verdict.rewards_address = Some(format!("{:#x}", quote.rewards_address));
    verdict.committed_key_count = Some(quote.committed_key_count);
    verdict.pinned = Some(quote.commitment_pin.is_some());

    // 1. Hash recomputation — no paying for hashes tied to nothing.
    let requested = parse_hash32(&entry.quote_hash).map_err(|e| format!("quote_hash: {e}"))?;
    if quote.hash().as_slice() != requested {
        return Err("quote_hash does not equal hash(signed_quote) — the payment triple is not tied to this quote".into());
    }

    // 2. ML-DSA-65 signature over the paid fields.
    if !verify_quote_signature(&quote) {
        return Err("quote signature failed ML-DSA-65 verification".into());
    }

    // 3. Paid-fields equality — the triple must pay exactly what the quote
    // prescribes: the signed price times the single-node payment multiplier
    // (the median quote of the close group is paid at 3x, V2-619).
    let amount = Amount::from_str_radix(entry.amount.trim(), 10)
        .map_err(|e| format!("amount is not a decimal integer: {e}"))?;
    let expected_amount = quote
        .price
        .checked_mul(Amount::from(SINGLE_NODE_PAYMENT_MULTIPLIER))
        .ok_or_else(|| format!("signed price {} overflows the 3x multiplier", quote.price))?;
    if amount != expected_amount {
        return Err(format!(
            "amount {amount} does not equal {SINGLE_NODE_PAYMENT_MULTIPLIER}x the signed price {} (expected {expected_amount})",
            quote.price
        ));
    }
    let rewards: RewardsAddress = entry
        .rewards_address
        .trim()
        .parse()
        .map_err(|e| format!("rewards_address is not a valid address: {e}"))?;
    if rewards != quote.rewards_address {
        return Err(format!(
            "rewards_address {rewards:#x} does not equal the signed address {:#x}",
            quote.rewards_address
        ));
    }

    // 4. ADR-0004 resolve-before-pay binding with exact on-curve pricing.
    binding_is_valid(&quote, entry.commitment_sidecar.as_deref())
}

/// Port of ant-core's `quote_commitment_binding_is_valid` (the ADR-0004
/// client-side gate), with the peer identity derived from the quote's own
/// `pub_key` — offline verification has no independent peer id, and binding
/// the commitment to the quote's signing key is exactly the property the
/// gateway needs (one signer attests both artifacts).
fn binding_is_valid(quote: &PaymentQuote, sidecar_b64: Option<&str>) -> Result<(), String> {
    let count = quote.committed_key_count;
    let pin = quote.commitment_pin;
    match (count, pin.is_some()) {
        (0, false) | (1.., true) => {}
        (1.., false) => {
            return Err(format!(
                "committed_key_count={count} > 0 but commitment_pin is None (unauditable count)"
            ));
        }
        (0, true) => {
            return Err("committed_key_count=0 with a commitment_pin (incoherent baseline)".into());
        }
    }
    if count > MAX_COMMITMENT_KEY_COUNT {
        return Err(format!(
            "committed_key_count={count} exceeds MAX_COMMITMENT_KEY_COUNT={MAX_COMMITMENT_KEY_COUNT}"
        ));
    }
    // Forced price: exact recomputation, never inversion.
    let expected = calculate_price(count as usize);
    if quote.price != expected {
        return Err(format!(
            "price {} does not equal calculate_price(committed_key_count={count}) = {expected}",
            quote.price
        ));
    }

    // Baseline `(0, None)` pins nothing — fully resolved by the checks above.
    let Some(pin) = pin else {
        return Ok(());
    };

    // Bound quote: the commitment MUST be present and MUST resolve the pin.
    let Some(b64) = sidecar_b64 else {
        return Err(
            "bound quote (commitment_pin set) has no commitment_sidecar; the pin is unresolvable"
                .into(),
        );
    };
    let blob = BASE64
        .decode(b64)
        .map_err(|e| format!("commitment_sidecar is not valid base64: {e}"))?;
    if blob.len() > MAX_COMMITMENT_SIDECAR_BYTES {
        return Err(format!(
            "commitment_sidecar is {} bytes, exceeds MAX_COMMITMENT_SIDECAR_BYTES={MAX_COMMITMENT_SIDECAR_BYTES}",
            blob.len()
        ));
    }
    let commitment: StorageCommitment = rmp_serde::from_slice(&blob).map_err(|e| {
        format!("commitment_sidecar did not deserialize as a StorageCommitment: {e}")
    })?;

    // Key binding: the commitment must belong to the quote's signing key,
    // exactly as the storer derives a peer id (`BLAKE3(pub_key)`).
    let quote_peer = ant_core::data::compute_address(&quote.pub_key);
    if ant_core::data::compute_address(&commitment.sender_public_key) != quote_peer
        || commitment.sender_peer_id != quote_peer
    {
        return Err("commitment is not bound to the quote's signing key".into());
    }
    if !verify_commitment_signature(&commitment) {
        return Err("commitment has an invalid ML-DSA-65 signature".into());
    }
    if commitment_hash(&commitment) != Some(pin) {
        return Err("commitment does not hash to the quote's commitment_pin".into());
    }
    if commitment.key_count != count {
        return Err(format!(
            "commitment attests key_count={} but the quote claims {count}",
            commitment.key_count
        ));
    }
    Ok(())
}

/// Parse a 32-byte hex string (0x prefix optional).
fn parse_hash32(s: &str) -> Result<[u8; 32], String> {
    let stripped = s.trim().strip_prefix("0x").unwrap_or(s.trim());
    let bytes = hex::decode(stripped).map_err(|e| format!("invalid hex: {e}"))?;
    bytes
        .try_into()
        .map_err(|_| "expected 32 bytes".to_string())
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;
    use ant_protocol::pqc::api::ml_dsa_65;
    use std::time::{Duration, SystemTime};
    use xor_name::XorName;

    /// A genuinely-signed quote: fresh ML-DSA-65 keypair, signature over
    /// `bytes_for_sig()` — the same thing a node produces.
    fn signed_quote(
        committed_key_count: u32,
        commitment_pin: Option<[u8; 32]>,
        price: Amount,
    ) -> (
        PaymentQuote,
        Vec<u8>,
        ant_protocol::pqc::api::MlDsaSecretKey,
    ) {
        let (pk, sk) = ml_dsa_65().generate_keypair().unwrap();
        let pk_bytes = pk.to_bytes();
        let content = XorName([7u8; 32]);
        let timestamp = SystemTime::UNIX_EPOCH + Duration::from_secs(1_756_000_000);
        let rewards_address: RewardsAddress = "0x1111111111111111111111111111111111111111"
            .parse()
            .unwrap();
        let bytes = PaymentQuote::bytes_for_signing(
            content,
            timestamp,
            &price,
            &rewards_address,
            committed_key_count,
            &commitment_pin,
        );
        let sig = ml_dsa_65().sign(&sk, &bytes).unwrap();
        let quote = PaymentQuote {
            content,
            timestamp,
            price,
            rewards_address,
            pub_key: pk_bytes.clone(),
            signature: sig.to_bytes(),
            committed_key_count,
            commitment_pin,
        };
        (quote, pk_bytes, sk)
    }

    /// Replicates ant-protocol's private `commitment_signed_payload` layout so
    /// tests can produce a genuinely-signed commitment under the quote's key.
    /// If the layout ever drifts, `verify_commitment_signature` fails loudly
    /// here.
    fn commitment_payload(
        root: &[u8; 32],
        key_count: u32,
        peer_id: &[u8; 32],
        pk: &[u8],
    ) -> Vec<u8> {
        let mut v = Vec::new();
        v.extend_from_slice(root);
        v.extend_from_slice(&key_count.to_le_bytes());
        v.extend_from_slice(peer_id);
        v.extend_from_slice(&u32::try_from(pk.len()).unwrap().to_le_bytes());
        v.extend_from_slice(pk);
        v
    }

    fn signed_commitment(
        key_count: u32,
        pk_bytes: &[u8],
        sk: &ant_protocol::pqc::api::MlDsaSecretKey,
    ) -> StorageCommitment {
        let root = [3u8; 32];
        let peer_id = ant_core::data::compute_address(pk_bytes);
        let payload = commitment_payload(&root, key_count, &peer_id, pk_bytes);
        let sig = ml_dsa_65()
            .sign_with_context(
                sk,
                &payload,
                ant_protocol::payment::commitment::DOMAIN_COMMITMENT,
            )
            .unwrap();
        StorageCommitment {
            root,
            key_count,
            sender_peer_id: peer_id,
            sender_public_key: pk_bytes.to_vec(),
            signature: sig.to_bytes(),
        }
    }

    fn entry_for(quote: &PaymentQuote, sidecar: Option<&StorageCommitment>) -> VerifyQuoteEntry {
        VerifyQuoteEntry {
            quote_hash: format!("{:#x}", quote.hash()),
            rewards_address: format!("{:#x}", quote.rewards_address),
            amount: (quote.price * Amount::from(SINGLE_NODE_PAYMENT_MULTIPLIER)).to_string(),
            signed_quote: BASE64.encode(rmp_serde::to_vec(quote).unwrap()),
            commitment_sidecar: sidecar.map(|c| BASE64.encode(rmp_serde::to_vec(c).unwrap())),
        }
    }

    #[test]
    fn baseline_quote_verifies() {
        let (quote, _, _) = signed_quote(0, None, calculate_price(0));
        let verdict = verify_entry(&entry_for(&quote, None));
        assert!(verdict.valid, "error: {:?}", verdict.error);
        assert_eq!(verdict.committed_key_count, Some(0));
        assert_eq!(verdict.pinned, Some(false));
        assert_eq!(verdict.price, Some(calculate_price(0).to_string()));
        assert_eq!(verdict.timestamp_unix_secs, Some(1_756_000_000));
    }

    #[test]
    fn pinned_quote_with_matching_commitment_verifies() {
        // Build the commitment first: the quote must pin its hash.
        let (pk, sk) = ml_dsa_65().generate_keypair().unwrap();
        let pk_bytes = pk.to_bytes();
        let count = 4242u32;
        let commitment = {
            let root = [3u8; 32];
            let peer_id = ant_core::data::compute_address(&pk_bytes);
            let payload = commitment_payload(&root, count, &peer_id, &pk_bytes);
            let sig = ml_dsa_65()
                .sign_with_context(
                    &sk,
                    &payload,
                    ant_protocol::payment::commitment::DOMAIN_COMMITMENT,
                )
                .unwrap();
            StorageCommitment {
                root,
                key_count: count,
                sender_peer_id: peer_id,
                sender_public_key: pk_bytes.clone(),
                signature: sig.to_bytes(),
            }
        };
        let pin = commitment_hash(&commitment).unwrap();

        // Quote signed by the same key, pinning that commitment, priced on-curve.
        let content = XorName([7u8; 32]);
        let timestamp = SystemTime::UNIX_EPOCH + Duration::from_secs(1_756_000_000);
        let rewards_address: RewardsAddress = "0x1111111111111111111111111111111111111111"
            .parse()
            .unwrap();
        let price = calculate_price(count as usize);
        let bytes = PaymentQuote::bytes_for_signing(
            content,
            timestamp,
            &price,
            &rewards_address,
            count,
            &Some(pin),
        );
        let sig = ml_dsa_65().sign(&sk, &bytes).unwrap();
        let quote = PaymentQuote {
            content,
            timestamp,
            price,
            rewards_address,
            pub_key: pk_bytes,
            signature: sig.to_bytes(),
            committed_key_count: count,
            commitment_pin: Some(pin),
        };

        let verdict = verify_entry(&entry_for(&quote, Some(&commitment)));
        assert!(verdict.valid, "error: {:?}", verdict.error);
        assert_eq!(verdict.pinned, Some(true));
        assert_eq!(verdict.committed_key_count, Some(count));
    }

    #[test]
    fn tampered_amount_is_rejected() {
        let (quote, _, _) = signed_quote(0, None, calculate_price(0));
        let mut entry = entry_for(&quote, None);
        entry.amount = (calculate_price(0) * Amount::from(SINGLE_NODE_PAYMENT_MULTIPLIER)
            + Amount::from(1))
        .to_string();
        let verdict = verify_entry(&entry);
        assert!(!verdict.valid);
        assert!(verdict
            .error
            .unwrap()
            .contains("does not equal 3x the signed price"));
    }

    #[test]
    fn wrong_quote_hash_is_rejected() {
        let (quote, _, _) = signed_quote(0, None, calculate_price(0));
        let mut entry = entry_for(&quote, None);
        entry.quote_hash = format!("0x{}", hex::encode([9u8; 32]));
        let verdict = verify_entry(&entry);
        assert!(!verdict.valid);
        assert!(verdict.error.unwrap().contains("not tied to this quote"));
        // Extracted fields still populated so the caller sees the claim.
        assert!(verdict.price.is_some());
    }

    #[test]
    fn off_curve_price_is_rejected() {
        let off = calculate_price(0) + Amount::from(1);
        let (quote, _, _) = signed_quote(0, None, off);
        let verdict = verify_entry(&entry_for(&quote, None));
        assert!(!verdict.valid);
        assert!(verdict.error.unwrap().contains("calculate_price"));
    }

    #[test]
    fn pinned_quote_without_sidecar_is_rejected() {
        let (pk, sk) = ml_dsa_65().generate_keypair().unwrap();
        let commitment = signed_commitment(7, &pk.to_bytes(), &sk);
        let pin = commitment_hash(&commitment).unwrap();
        // Quote pins the commitment but the entry ships no sidecar.
        let content = XorName([7u8; 32]);
        let timestamp = SystemTime::UNIX_EPOCH + Duration::from_secs(1_756_000_000);
        let rewards_address: RewardsAddress = "0x1111111111111111111111111111111111111111"
            .parse()
            .unwrap();
        let price = calculate_price(7);
        let bytes = PaymentQuote::bytes_for_signing(
            content,
            timestamp,
            &price,
            &rewards_address,
            7,
            &Some(pin),
        );
        let sig = ml_dsa_65().sign(&sk, &bytes).unwrap();
        let quote = PaymentQuote {
            content,
            timestamp,
            price,
            rewards_address,
            pub_key: pk.to_bytes(),
            signature: sig.to_bytes(),
            committed_key_count: 7,
            commitment_pin: Some(pin),
        };
        let verdict = verify_entry(&entry_for(&quote, None));
        assert!(!verdict.valid);
        assert!(verdict.error.unwrap().contains("unresolvable"));
    }

    #[test]
    fn forged_signature_is_rejected() {
        let (mut quote, _, _) = signed_quote(0, None, calculate_price(0));
        quote.signature[0] ^= 0xff;
        let verdict = verify_entry(&entry_for(&quote, None));
        assert!(!verdict.valid);
        assert!(verdict.error.unwrap().contains("ML-DSA-65"));
    }

    #[test]
    fn entries_builder_emits_only_paid_quotes_and_attaches_sidecar_by_pin() {
        let (pk, sk) = ml_dsa_65().generate_keypair().unwrap();
        let pk_bytes = pk.to_bytes();
        let count = 12u32;
        let commitment = signed_commitment(count, &pk_bytes, &sk);
        let pin = commitment_hash(&commitment).unwrap();

        let content = XorName([7u8; 32]);
        let timestamp = SystemTime::UNIX_EPOCH + Duration::from_secs(1_756_000_000);
        let rewards_address: RewardsAddress = "0x1111111111111111111111111111111111111111"
            .parse()
            .unwrap();
        let price = calculate_price(count as usize);
        let bytes = PaymentQuote::bytes_for_signing(
            content,
            timestamp,
            &price,
            &rewards_address,
            count,
            &Some(pin),
        );
        let sig = ml_dsa_65().sign(&sk, &bytes).unwrap();
        let pinned_quote = PaymentQuote {
            content,
            timestamp,
            price,
            rewards_address,
            pub_key: pk_bytes,
            signature: sig.to_bytes(),
            committed_key_count: count,
            commitment_pin: Some(pin),
        };
        // A validly-priced quote that the payment intent did NOT select (the
        // network quotes a whole close group; only a subset is paid).
        let (unpaid_quote, _, _) = signed_quote(0, None, calculate_price(0));

        let sidecar_blob = rmp_serde::to_vec(&commitment).unwrap();
        let paid: HashSet<evmlib::common::QuoteHash> = [pinned_quote.hash()].into_iter().collect();
        let entries = entries_for_quotes(
            [&pinned_quote, &unpaid_quote],
            std::slice::from_ref(&sidecar_blob),
            &paid,
        )
        .unwrap();
        assert_eq!(entries.len(), 1, "unpaid quote must be skipped");
        assert_eq!(entries[0].quote_hash, format!("{:#x}", pinned_quote.hash()));
        assert_eq!(
            entries[0].commitment_sidecar,
            Some(BASE64.encode(&sidecar_blob))
        );

        // Round-trip: the emitted entry verifies.
        let verdict = verify_entry(&VerifyQuoteEntry {
            quote_hash: entries[0].quote_hash.clone(),
            rewards_address: format!("{:#x}", pinned_quote.rewards_address),
            amount: (pinned_quote.price * Amount::from(SINGLE_NODE_PAYMENT_MULTIPLIER)).to_string(),
            signed_quote: entries[0].quote.clone(),
            commitment_sidecar: entries[0].commitment_sidecar.clone(),
        });
        assert!(verdict.valid, "error: {:?}", verdict.error);
    }
}
