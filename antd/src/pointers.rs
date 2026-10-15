//! Pointer operations (ADR-0016 and ADR-0018 in `ant-node`), shared by the
//! REST and gRPC surfaces.
//!
//! Everything a pointer needs from the network is ant-core's: the quorums, the
//! merge order, chain resolution and finality. What lives here is the daemon's
//! side of it:
//!
//! - which loaded owner key signs (see [`crate::pointer_keys`]);
//! - one write per pointer at a time in this daemon, because two writes signed
//!   against the same served counter are both paid for and only one survives;
//! - the external-signer session between prepare and finalize, and a finalize
//!   that falls short after payment kept for a retry against the same payment;
//! - turning ant-core's answers into the wire shapes and error codes the SDKs
//!   see.
//!
//! Nothing here retries a paid write on its own. `pointer_put` pays for every
//! attempt, so a write is retried only by the caller repeating a finalize,
//! which reuses the proof it already paid for.

use std::collections::HashMap;
use std::time::Instant;

use ant_core::data::client::batch::ChunkPaymentPlan;
use ant_core::data::{
    FinalState, FinalityStatus, Pointer, PointerController, PointerFinality, PointerTarget,
    PointerTargetKind, XorName,
};

use crate::error::AntdError;
use crate::pointer_keys::PointerKey;
use crate::state::AppState;
use crate::types::{
    PaymentEntry, PointerControllerResponse, PointerFinalStateEntry, PointerFinalityResponse,
    PointerFinalizeResponse, PointerKeyEntry, PointerKeysResponse, PointerPrepareResponse,
    PointerRecordResponse, PointerResolveResponse, PointerTransferResponse, PointerWriteResponse,
    SignedQuoteEntry,
};

/// A pointer write an external signer is paying for, kept under its
/// `upload_id` between prepare and finalize.
pub struct PendingPointer {
    pub op: PointerOp,
    /// The signed state, at the counter it was prepared against.
    pub record: Pointer,
    /// The quote the signer pays. Kept after a first finalize too, so a
    /// repeat finalize can still describe what was paid.
    pub plan: ChunkPaymentPlan,
    /// The proof built from the signer's payment by the first finalize. A
    /// repeat finalize stores the state with it, against the same payment.
    pub proof: Option<Vec<u8>>,
    pub created_at: Instant,
}

/// The write a prepare signs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PointerOp {
    Create,
    Update,
    Transfer,
}

impl PointerOp {
    pub fn parse(op: &str) -> Result<Self, AntdError> {
        match op {
            "create" => Ok(Self::Create),
            "update" => Ok(Self::Update),
            "transfer" => Ok(Self::Transfer),
            other => Err(AntdError::BadRequest(format!(
                "unknown pointer op {other:?}: expected \"create\", \"update\" or \"transfer\""
            ))),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Create => "create",
            Self::Update => "update",
            Self::Transfer => "transfer",
        }
    }
}

/// What a prepare was asked to sign, already parsed.
pub enum PreparedWrite {
    Set {
        op: PointerOp,
        target: PointerTarget,
    },
    Transfer {
        recipient: XorName,
    },
}

// ── Parsing ──

/// Parse a 32-byte address given as 64 hex characters, with or without `0x`.
pub fn parse_address(field: &str, value: &str) -> Result<XorName, AntdError> {
    let hex_part = value.strip_prefix("0x").unwrap_or(value);
    if hex_part.len() != 64 {
        return Err(AntdError::BadRequest(format!(
            "{field} must be 64 hex characters (32 bytes)"
        )));
    }
    let bytes = hex::decode(hex_part)
        .map_err(|e| AntdError::BadRequest(format!("{field} is not valid hex: {e}")))?;
    bytes
        .try_into()
        .map_err(|_| AntdError::BadRequest(format!("{field} must be 32 bytes")))
}

/// Parse a target kind. Only the kinds this daemon can follow can be written.
pub fn parse_kind(kind: Option<&str>) -> Result<PointerTargetKind, AntdError> {
    match kind.unwrap_or("chunk") {
        "" | "chunk" => Ok(PointerTargetKind::Chunk),
        "pointer" => Ok(PointerTargetKind::Pointer),
        other => Err(AntdError::BadRequest(format!(
            "unknown pointer target kind {other:?}: expected \"chunk\" or \"pointer\""
        ))),
    }
}

/// Parse a write's target and kind.
pub fn parse_target(target: &str, kind: Option<&str>) -> Result<PointerTarget, AntdError> {
    Ok(PointerTarget::new(
        parse_kind(kind)?,
        parse_address("target", target)?,
    ))
}

/// Parse a prepare's operation and its arguments.
pub fn parse_prepared_write(
    op: &str,
    target: Option<&str>,
    kind: Option<&str>,
    recipient: Option<&str>,
) -> Result<PreparedWrite, AntdError> {
    match PointerOp::parse(op)? {
        PointerOp::Transfer => {
            let recipient = recipient
                .filter(|r| !r.is_empty())
                .ok_or_else(|| AntdError::BadRequest("op \"transfer\" needs a recipient".into()))?;
            Ok(PreparedWrite::Transfer {
                recipient: parse_address("recipient", recipient)?,
            })
        }
        op => {
            let target = target.filter(|t| !t.is_empty()).ok_or_else(|| {
                AntdError::BadRequest(format!("op {:?} needs a target", op.as_str()))
            })?;
            Ok(PreparedWrite::Set {
                op,
                target: parse_target(target, kind)?,
            })
        }
    }
}

// ── Errors ──

/// Map an ant-core error from a pointer operation.
///
/// Several pointer outcomes reach antd as `InvalidData` with only a message to
/// tell them apart. The ones a caller acts on differently are picked out by
/// the stable part of ant-core's wording; anything else keeps the general
/// mapping, so a reworded message degrades to 400 rather than to a wrong code.
pub fn map_core_error(e: ant_core::data::Error) -> AntdError {
    use ant_core::data::Error;
    match e {
        // `pointer_sign_create`: the pointer exists, so update it instead.
        Error::InvalidData(msg) if msg.contains("already exists") => AntdError::AlreadyExists(msg),
        // A write that lost to a newer state while it was in flight.
        Error::InvalidData(msg) if msg.contains("moved while this update was in flight") => {
            AntdError::Conflict(msg)
        }
        // `pointer_resolve`: a pointer on the chain does not exist.
        Error::InvalidData(msg) if msg.contains("chain breaks at") => AntdError::NotFound(msg),
        // Refused before paying: too few of the close group store pointers
        // yet (an upgrade in progress). Nothing was paid; try later.
        Error::InsufficientPeers(msg) => AntdError::ServiceUnavailable(msg),
        other => AntdError::from_core(other),
    }
}

/// Whether a write that failed after payment may land if the same proof is
/// sent again: a shortfall or an unreachable peer, not a refusal of the record.
fn worth_retrying(e: &ant_core::data::Error) -> bool {
    use ant_core::data::Error;
    matches!(
        e,
        Error::CloseGroupShortfall(_)
            | Error::Network(_)
            | Error::Timeout(_)
            | Error::InsufficientPeers(_)
            | Error::RemotePut { .. }
    )
}

// ── Views ──

fn kind_name(kind_tag: u8) -> &'static str {
    match PointerTargetKind::from_tag(kind_tag) {
        Some(PointerTargetKind::Chunk) => "chunk",
        Some(PointerTargetKind::Pointer) => "pointer",
        None => "unknown",
    }
}

fn record_view(record: &Pointer) -> PointerRecordResponse {
    let target = record.target();
    PointerRecordResponse {
        address: hex::encode(record.address()),
        owner: hex::encode(record.owner().to_bytes()),
        counter: record.counter().to_string(),
        kind: kind_name(target.kind_tag()).into(),
        kind_tag: target.kind_tag(),
        target: hex::encode(target.address),
        state_id: hex::encode(record.state_id()),
        is_final: record.is_terminal(),
        transferred_to: record.transferred_to().map(hex::encode),
    }
}

fn write_view(record: &Pointer) -> PointerWriteResponse {
    PointerWriteResponse {
        address: hex::encode(record.address()),
        state_id: hex::encode(record.state_id()),
        counter: record.counter().to_string(),
    }
}

fn final_state_view(state: &FinalState) -> PointerFinalStateEntry {
    PointerFinalStateEntry {
        state_id: hex::encode(state.state_id),
        kind: kind_name(state.kind_tag).into(),
        kind_tag: state.kind_tag,
        target: hex::encode(state.target),
        holders: saturate(state.holders),
        transferred_to: state.transferred_to().map(hex::encode),
    }
}

pub fn finality_view(finality: &PointerFinality) -> PointerFinalityResponse {
    let mut view = PointerFinalityResponse {
        address: hex::encode(finality.address),
        group: saturate(finality.group),
        answered: saturate(finality.answered),
        status: String::new(),
        counter: None,
        state: None,
        states: Vec::new(),
        majority: None,
        transferred_to: finality.transferred_to().map(hex::encode),
    };
    match &finality.status {
        FinalityStatus::Open { counter } => {
            view.status = "open".into();
            view.counter = counter.map(|c| c.to_string());
        }
        FinalityStatus::Settling(state) => {
            view.status = "settling".into();
            view.state = Some(final_state_view(state));
        }
        FinalityStatus::Unconfirmed(state) => {
            view.status = "unconfirmed".into();
            view.state = Some(final_state_view(state));
        }
        FinalityStatus::Final(state) => {
            view.status = "final".into();
            view.state = Some(final_state_view(state));
        }
        FinalityStatus::Forked { states, majority } => {
            view.status = "forked".into();
            view.states = states.iter().map(final_state_view).collect();
            view.majority = majority.as_ref().map(final_state_view);
        }
    }
    view
}

fn controller_view(controller: &PointerController) -> PointerControllerResponse {
    PointerControllerResponse {
        pointer: hex::encode(controller.pointer),
        transfers: controller.transfers.iter().map(hex::encode).collect(),
        frozen: controller.frozen,
    }
}

fn saturate(n: usize) -> u32 {
    u32::try_from(n).unwrap_or(u32::MAX)
}

// ── Keys and write admission ──

/// The loaded key for the pointer at `owner`.
fn owner_key<'a>(state: &'a AppState, owner: &XorName) -> Result<&'a PointerKey, AntdError> {
    state.pointer_keys.get(owner).ok_or_else(|| {
        let hint = if state.pointer_keys.is_empty() {
            "antd was started without --pointer-keys"
        } else {
            "see GET /v1/pointers/keys for the pointers this daemon can write"
        };
        AntdError::BadRequest(format!(
            "no owner key is loaded for pointer {}; {hint}",
            hex::encode(owner)
        ))
    })
}

/// Refuse a write to a pointer that has a prepared write awaiting payment.
///
/// The prepared state was signed one past the counter served at the time. A
/// write landing first moves the pointer past it, and the external signer's
/// payment would then buy a state the network refuses as stale.
async fn refuse_if_pending(state: &AppState, address: &XorName) -> Result<(), AntdError> {
    let pending = state.pending_pointers.lock().await;
    if let Some((upload_id, _)) = pending
        .iter()
        .find(|(_, session)| session.record.address() == *address)
    {
        return Err(AntdError::Conflict(format!(
            "pointer {} has a prepared write awaiting payment (upload_id {upload_id}); \
             finalize it, or wait for it to expire, before writing again",
            hex::encode(address)
        )));
    }
    Ok(())
}

fn require_wallet(state: &AppState) -> Result<(), AntdError> {
    if state.client.wallet().is_none() {
        return Err(AntdError::ServiceUnavailable(
            "wallet not configured — set AUTONOMI_WALLET_KEY, or pay with an external \
             signer through /v1/pointers/prepare and /v1/pointers/finalize"
                .into(),
        ));
    }
    Ok(())
}

// ── Operations ──

pub fn keys(state: &AppState) -> PointerKeysResponse {
    PointerKeysResponse {
        keys: state
            .pointer_keys
            .addresses()
            .map(|address| PointerKeyEntry {
                address: hex::encode(address),
            })
            .collect(),
    }
}

/// Create the pointer at `owner`, paid by the daemon wallet. Refused before
/// paying if it already exists.
pub async fn create(
    state: &AppState,
    owner: XorName,
    target: PointerTarget,
) -> Result<PointerWriteResponse, AntdError> {
    write(state, owner, PointerOp::Create, target).await
}

/// Point the pointer at `owner` at `target`, paid by the daemon wallet. A
/// pointer that does not exist yet is created.
pub async fn update(
    state: &AppState,
    owner: XorName,
    target: PointerTarget,
) -> Result<PointerWriteResponse, AntdError> {
    write(state, owner, PointerOp::Update, target).await
}

async fn write(
    state: &AppState,
    owner: XorName,
    op: PointerOp,
    target: PointerTarget,
) -> Result<PointerWriteResponse, AntdError> {
    let key = owner_key(state, &owner)?;
    require_wallet(state)?;
    let _writing = key.write_lock.lock().await;
    refuse_if_pending(state, &owner).await?;

    let client = &state.client;
    let record = sign_set(state, key, op, target).await?;
    client.pointer_put(&record).await.map_err(map_core_error)?;

    state.mark_store_ok();
    Ok(write_view(&record))
}

/// Sign a create or an update with `key`. ant-core reads the network first:
/// a create is refused if the pointer exists, an update if it is final.
async fn sign_set(
    state: &AppState,
    key: &PointerKey,
    op: PointerOp,
    target: PointerTarget,
) -> Result<Pointer, AntdError> {
    let client = &state.client;
    let signed = if op == PointerOp::Create {
        client
            .pointer_sign_create(&key.secret, &key.public, target)
            .await
    } else {
        client
            .pointer_sign_update(&key.secret, &key.public, target)
            .await
    };
    signed.map_err(map_core_error)
}

/// Hand the pointer at `owner` over to the pointer at `recipient`, for good,
/// paid by the daemon wallet.
pub async fn transfer(
    state: &AppState,
    owner: XorName,
    recipient: XorName,
) -> Result<PointerTransferResponse, AntdError> {
    let key = owner_key(state, &owner)?;
    require_wallet(state)?;
    let _writing = key.write_lock.lock().await;
    refuse_if_pending(state, &owner).await?;

    let transfer = state
        .client
        .pointer_transfer(&key.secret, &key.public, recipient)
        .await
        .map_err(map_core_error)?;

    state.mark_store_ok();
    let (finality, finality_error) = match &transfer.finality {
        Ok(finality) => (Some(finality_view(finality)), None),
        Err(e) => (None, Some(e.to_string())),
    };
    Ok(PointerTransferResponse {
        address: hex::encode(transfer.address),
        state_id: hex::encode(transfer.state_id),
        finality,
        finality_error,
    })
}

pub async fn get(state: &AppState, address: XorName) -> Result<PointerRecordResponse, AntdError> {
    let record = state
        .client
        .pointer_get(&address)
        .await
        .map_err(map_core_error)?
        .ok_or_else(|| AntdError::NotFound(format!("no pointer at {}", hex::encode(address))))?;
    Ok(record_view(&record))
}

pub async fn resolve(
    state: &AppState,
    address: XorName,
) -> Result<PointerResolveResponse, AntdError> {
    let target = state
        .client
        .pointer_resolve(&address)
        .await
        .map_err(map_core_error)?;
    Ok(PointerResolveResponse {
        kind: kind_name(target.kind_tag()).into(),
        kind_tag: target.kind_tag(),
        target: hex::encode(target.address),
    })
}

pub async fn finality(
    state: &AppState,
    address: XorName,
) -> Result<PointerFinalityResponse, AntdError> {
    let finality = state
        .client
        .pointer_finality(&address)
        .await
        .map_err(map_core_error)?;
    Ok(finality_view(&finality))
}

pub async fn controller(
    state: &AppState,
    address: XorName,
) -> Result<PointerControllerResponse, AntdError> {
    let controller = state
        .client
        .pointer_controller(&address)
        .await
        .map_err(map_core_error)?;
    Ok(controller_view(&controller))
}

/// Sign the write `prepared` asks for with the key loaded for `owner`, quote
/// it, and keep both under a fresh `upload_id` for an external signer to pay.
///
/// Every check ant-core makes before paying is made here: a create of a
/// pointer that exists, an update or transfer of a final one, and a transfer
/// to a recipient that does not exist or leads back are refused before
/// anything is quoted.
pub async fn prepare(
    state: &AppState,
    owner: XorName,
    prepared: PreparedWrite,
    include_signed_quotes: bool,
) -> Result<PointerPrepareResponse, AntdError> {
    let key = owner_key(state, &owner)?;
    let _writing = key.write_lock.lock().await;
    refuse_if_pending(state, &owner).await?;

    let client = &state.client;
    let (op, record) = match prepared {
        PreparedWrite::Set { op, target } => (op, sign_set(state, key, op, target).await?),
        PreparedWrite::Transfer { recipient } => {
            let record = client
                .pointer_sign_transfer(&key.secret, &key.public, recipient)
                .await
                .map_err(map_core_error)?;
            (PointerOp::Transfer, record)
        }
    };
    let plan = client
        .prepare_pointer_payment(&record)
        .await
        .map_err(map_core_error)?;

    let evm_cfg = crate::evm_defaults::resolve(&state.network);
    let paid = plan.payment.quotes.iter().filter(|q| !q.amount.is_zero());
    // Zero-amount quotes go into the proof but need no `payForQuotes` entry.
    let payments: Vec<PaymentEntry> = paid
        .clone()
        .map(|q| PaymentEntry {
            quote_hash: format!("{:#x}", q.quote_hash),
            rewards_address: format!("{:#x}", q.rewards_address),
            amount: q.amount.to_string(),
        })
        .collect();
    let signed_quotes: Option<Vec<SignedQuoteEntry>> = if include_signed_quotes {
        let paid_hashes = paid.map(|q| q.quote_hash).collect();
        Some(
            crate::signed_quotes::entries_for_quotes(
                plan.peer_quotes.iter().map(|(_, q)| q),
                &plan.commitment_sidecars,
                &paid_hashes,
            )
            .map_err(AntdError::Internal)?,
        )
    } else {
        None
    };

    let upload_id = hex::encode(rand::random::<[u8; 16]>());
    let response = PointerPrepareResponse {
        upload_id: upload_id.clone(),
        op: op.as_str().into(),
        address: hex::encode(record.address()),
        state_id: hex::encode(record.state_id()),
        counter: record.counter().to_string(),
        payment_type: "wave_batch".into(),
        payments,
        total_amount: plan.payment.total_amount().to_string(),
        payment_vault_address: evm_cfg.vault_addr,
        payment_token_address: evm_cfg.token_addr,
        rpc_url: evm_cfg.rpc_url,
        signed_quotes,
    };
    state.pending_pointers.lock().await.insert(
        upload_id,
        PendingPointer {
            op,
            record,
            plan,
            proof: None,
            created_at: Instant::now(),
        },
    );
    Ok(response)
}

/// Store a prepared write once its external signer has paid.
///
/// A write that falls short after payment is kept under the same `upload_id`
/// with the proof it paid for, and answers `CLOSE_GROUP_SHORTFALL` with
/// `retryable: true`: repeating the finalize sends the same proof again, so
/// the retry costs nothing. Any other failure ends the session.
pub async fn finalize(
    state: &AppState,
    upload_id: &str,
    tx_hashes: &HashMap<String, String>,
) -> Result<PointerFinalizeResponse, AntdError> {
    let not_found = || {
        AntdError::NotFound(format!(
            "upload_id {upload_id} not found — it may have expired or already been finalized"
        ))
    };
    // Take the pointer's write lock before taking the session out of the
    // pending map. While the session is in the map other writes are refused;
    // once it is out, they wait on the lock. A gap between the two would let
    // a write land first and leave the paid state stale.
    let address = state
        .pending_pointers
        .lock()
        .await
        .get(upload_id)
        .map(|session| session.record.address())
        .ok_or_else(not_found)?;
    // A key is loaded for every prepared write, and keys are never unloaded.
    let _writing = match state.pointer_keys.get(&address) {
        Some(key) => Some(key.write_lock.lock().await),
        None => None,
    };
    // A concurrent finalize of the same upload_id may have taken it meanwhile.
    let session = state
        .pending_pointers
        .lock()
        .await
        .remove(upload_id)
        .ok_or_else(not_found)?;

    let proof = match &session.proof {
        Some(proof) => proof.clone(),
        None => match parse_tx_hashes(tx_hashes).and_then(|txs| {
            session
                .plan
                .proof(&txs)
                .map_err(|e| AntdError::BadRequest(format!("cannot build payment proof: {e}")))
        }) {
            Ok(proof) => proof,
            Err(e) => {
                // Nothing has been sent yet: keep the session so the caller
                // can correct the hashes.
                state
                    .pending_pointers
                    .lock()
                    .await
                    .insert(upload_id.to_string(), session);
                return Err(e);
            }
        },
    };

    match state
        .client
        .pointer_put_paid(&session.record, proof.clone())
        .await
    {
        Ok(_) => {}
        Err(e) => {
            // A transfer whose acknowledgements were lost may have landed
            // anyway; the close group says whether it did. (ant-core's own
            // `pointer_transfer` makes the same check, but only for writes it
            // paid for itself.)
            if session.op == PointerOp::Transfer {
                if let Some(finality) = landed_transfer(state, &session.record).await? {
                    state.mark_store_ok();
                    return Ok(finalized(&session.record, Some(finality)));
                }
            }
            if worth_retrying(&e) {
                let reason = e.to_string();
                state.pending_pointers.lock().await.insert(
                    upload_id.to_string(),
                    PendingPointer {
                        proof: Some(proof),
                        created_at: Instant::now(),
                        ..session
                    },
                );
                return Err(AntdError::CloseGroupShortfall {
                    message: format!(
                        "{reason} (paid attempt retained: call finalize again with the same \
                         upload_id to store it against the same payment)"
                    ),
                    retryable: Some(true),
                });
            }
            return Err(map_core_error(e));
        }
    }

    state.mark_store_ok();
    let finality = if session.op == PointerOp::Transfer {
        state
            .client
            .pointer_finality(&address)
            .await
            .ok()
            .map(|f| finality_view(&f))
    } else {
        None
    };
    Ok(finalized(&session.record, finality))
}

fn finalized(
    record: &Pointer,
    finality: Option<PointerFinalityResponse>,
) -> PointerFinalizeResponse {
    PointerFinalizeResponse {
        address: hex::encode(record.address()),
        state_id: hex::encode(record.state_id()),
        counter: record.counter().to_string(),
        finality,
    }
}

/// Whether the final state `record`, whose write reported failure, is held by
/// a majority of the close group all the same. A rival final state is the
/// reason the write failed, and is reported as such.
async fn landed_transfer(
    state: &AppState,
    record: &Pointer,
) -> Result<Option<PointerFinalityResponse>, AntdError> {
    let Ok(finality) = state.client.pointer_finality(&record.address()).await else {
        return Ok(None);
    };
    let ours = record.state_id();
    match &finality.status {
        FinalityStatus::Final(held) | FinalityStatus::Unconfirmed(held)
            if held.state_id == ours =>
        {
            Ok(Some(finality_view(&finality)))
        }
        FinalityStatus::Settling(held)
        | FinalityStatus::Final(held)
        | FinalityStatus::Unconfirmed(held)
            if held.state_id != ours =>
        {
            Err(AntdError::PointerFinal(format!(
                "pointer {} is already final on state {}",
                hex::encode(record.address()),
                hex::encode(held.state_id)
            )))
        }
        FinalityStatus::Forked { states, .. } => Err(AntdError::PointerForked(format!(
            "pointer {} holds {} different final states",
            hex::encode(record.address()),
            states.len()
        ))),
        _ => Ok(None),
    }
}

fn parse_tx_hashes(
    tx_hashes: &HashMap<String, String>,
) -> Result<HashMap<evmlib::common::QuoteHash, evmlib::common::TxHash>, AntdError> {
    tx_hashes
        .iter()
        .map(|(quote_hex, tx_hex)| {
            let quote: [u8; 32] = hex::decode(quote_hex.trim_start_matches("0x"))
                .map_err(|e| AntdError::BadRequest(format!("invalid quote_hash {quote_hex}: {e}")))?
                .try_into()
                .map_err(|_| AntdError::BadRequest("quote_hash must be 32 bytes".into()))?;
            let tx: [u8; 32] = hex::decode(tx_hex.trim_start_matches("0x"))
                .map_err(|e| AntdError::BadRequest(format!("invalid tx_hash {tx_hex}: {e}")))?
                .try_into()
                .map_err(|_| AntdError::BadRequest("tx_hash must be 32 bytes".into()))?;
            Ok((quote.into(), tx.into()))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use ant_core::data::{ml_dsa_65, FINAL_COUNTER};

    fn signed(counter: u64, target: PointerTarget) -> Pointer {
        let (public, secret) = ml_dsa_65().generate_keypair_from_seed(&[3; 32]);
        Pointer::sign(&secret, &public, counter, target).unwrap()
    }

    fn final_state(target: [u8; 32], kind: PointerTargetKind, holders: usize) -> FinalState {
        FinalState {
            state_id: [9; 32],
            kind_tag: kind.tag(),
            target,
            holders,
        }
    }

    #[test]
    fn addresses_accept_bare_or_prefixed_hex_and_nothing_else() {
        let hex64 = "ab".repeat(32);
        assert_eq!(parse_address("owner", &hex64).unwrap(), [0xab; 32]);
        assert_eq!(
            parse_address("owner", &format!("0x{hex64}")).unwrap(),
            [0xab; 32]
        );
        assert!(parse_address("owner", "abcd").is_err());
        assert!(parse_address("owner", &"zz".repeat(32)).is_err());
    }

    #[test]
    fn kinds_default_to_chunk_and_refuse_the_unknown() {
        assert_eq!(parse_kind(None).unwrap(), PointerTargetKind::Chunk);
        assert_eq!(parse_kind(Some("")).unwrap(), PointerTargetKind::Chunk);
        assert_eq!(
            parse_kind(Some("pointer")).unwrap(),
            PointerTargetKind::Pointer
        );
        assert!(matches!(
            parse_kind(Some("scratchpad")),
            Err(AntdError::BadRequest(_))
        ));
    }

    #[test]
    fn a_prepare_needs_the_arguments_its_op_uses() {
        let addr = "11".repeat(32);
        assert!(matches!(
            parse_prepared_write("create", Some(&addr), None, None),
            Ok(PreparedWrite::Set {
                op: PointerOp::Create,
                ..
            })
        ));
        assert!(matches!(
            parse_prepared_write("transfer", None, None, Some(&addr)),
            Ok(PreparedWrite::Transfer { .. })
        ));
        assert!(parse_prepared_write("update", None, None, None).is_err());
        assert!(parse_prepared_write("transfer", Some(&addr), None, None).is_err());
        assert!(parse_prepared_write("delete", Some(&addr), None, None).is_err());
    }

    #[test]
    fn pointer_outcomes_map_to_the_codes_callers_act_on() {
        use ant_core::data::Error;
        let cases = [
            (
                Error::InvalidData(
                    "pointer ab already exists at counter 3; update it instead".into(),
                ),
                "ALREADY_EXISTS",
            ),
            (
                Error::InvalidData(
                    "the pointer ab moved while this update was in flight; the network now holds \
                     a newer state"
                        .into(),
                ),
                "CONFLICT",
            ),
            (
                Error::InvalidData("pointer chain breaks at ab".into()),
                "NOT_FOUND",
            ),
            (
                Error::InvalidData("pointer chain cycles back to ab".into()),
                "BAD_REQUEST",
            ),
            (Error::PointerFinal("final".into()), "POINTER_FINAL"),
            (Error::PointerForked("forked".into()), "POINTER_FORKED"),
            (
                Error::CloseGroupShortfall("only 3 of 7 answered".into()),
                "CLOSE_GROUP_SHORTFALL",
            ),
            (
                Error::InsufficientPeers("4 of 7 do not accept pointer writes".into()),
                "SERVICE_UNAVAILABLE",
            ),
        ];
        for (error, code) in cases {
            let shown = error.to_string();
            assert_eq!(map_core_error(error).code(), code, "{shown}");
        }
    }

    #[test]
    fn a_record_shows_its_counter_as_a_string_even_when_final() {
        let target = PointerTarget::new(PointerTargetKind::Pointer, [5; 32]);
        let record = signed(FINAL_COUNTER, target);

        let view = record_view(&record);

        assert_eq!(view.counter, u64::MAX.to_string());
        assert!(view.is_final);
        assert_eq!(view.kind, "pointer");
        assert_eq!(view.transferred_to, Some(hex::encode([5; 32])));
        assert_eq!(view.owner.len(), 2 * 1952);
        let json = serde_json::to_value(&view).unwrap();
        assert_eq!(json["final"], true);
        assert_eq!(json["counter"], "18446744073709551615");
    }

    #[test]
    fn an_open_record_names_its_target_and_no_transfer() {
        let record = signed(4, PointerTarget::new(PointerTargetKind::Chunk, [6; 32]));

        let view = record_view(&record);

        assert_eq!(view.counter, "4");
        assert!(!view.is_final);
        assert_eq!(view.kind, "chunk");
        assert_eq!(view.kind_tag, 0);
        assert_eq!(view.target, hex::encode([6; 32]));
        assert_eq!(view.transferred_to, None);
        assert_eq!(view.address, hex::encode(record.address()));
    }

    #[test]
    fn an_unknown_target_kind_is_named_unknown_with_its_tag() {
        let record = signed(1, PointerTarget::from_raw_tag(42, [7; 32]));

        let view = record_view(&record);

        assert_eq!(view.kind, "unknown");
        assert_eq!(view.kind_tag, 42);
    }

    #[test]
    fn finality_flattens_each_status() {
        let finality = |status| PointerFinality {
            address: [1; 32],
            group: 7,
            answered: 7,
            status,
        };

        let open = finality_view(&finality(FinalityStatus::Open { counter: Some(3) }));
        assert_eq!(open.status, "open");
        assert_eq!(open.counter.as_deref(), Some("3"));
        assert!(open.state.is_none() && open.states.is_empty());

        let handed_over = final_state([8; 32], PointerTargetKind::Pointer, 5);
        let done = finality_view(&finality(FinalityStatus::Final(handed_over.clone())));
        assert_eq!(done.status, "final");
        assert_eq!(done.transferred_to, Some(hex::encode([8; 32])));
        assert_eq!(done.state.as_ref().unwrap().holders, 5);

        // Not yet beyond dispute, so not reported as handed over.
        let unconfirmed = finality_view(&finality(FinalityStatus::Unconfirmed(handed_over)));
        assert_eq!(unconfirmed.status, "unconfirmed");
        assert_eq!(unconfirmed.transferred_to, None);

        let a = final_state([1; 32], PointerTargetKind::Pointer, 4);
        let b = final_state([2; 32], PointerTargetKind::Chunk, 2);
        let forked = finality_view(&finality(FinalityStatus::Forked {
            states: vec![a.clone(), b],
            majority: Some(a),
        }));
        assert_eq!(forked.status, "forked");
        assert_eq!(forked.states.len(), 2);
        assert_eq!(forked.states[1].kind, "chunk");
        assert_eq!(forked.majority.as_ref().unwrap().holders, 4);
        assert!(forked.state.is_none());
    }

    #[test]
    fn tx_hashes_must_be_32_bytes_each() {
        let ok: HashMap<String, String> =
            [(format!("0x{}", "aa".repeat(32)), "bb".repeat(32))].into();
        assert_eq!(parse_tx_hashes(&ok).unwrap().len(), 1);

        let short: HashMap<String, String> = [("aa".into(), "bb".repeat(32))].into();
        assert!(parse_tx_hashes(&short).is_err());
    }
}
