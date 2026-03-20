use std::sync::Arc;
use std::time::Duration;

use axum::extract::{Path, State};
use axum::Json;
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;

use saorsa_node::ant_protocol::{
    ChunkGetRequest, ChunkGetResponse as ProtoGetResponse,
    ChunkMessage, ChunkMessageBody,
    ChunkPutRequest as ProtoPutRequest, ChunkPutResponse as ProtoPutResponse,
    ChunkQuoteRequest, ChunkQuoteResponse as ProtoQuoteResponse,
    MAX_CHUNK_SIZE,
};
use saorsa_node::client::compute_address;
use saorsa_node::payment::single_node::REQUIRED_QUOTES;
use saorsa_node::client::send_and_await_chunk_response;

use crate::error::AntdError;
use crate::state::AppState;
use crate::types::*;

/// Default timeout for chunk operations.
const CHUNK_TIMEOUT: Duration = Duration::from_secs(30);

/// Find a peer to route a chunk request to.
/// Tries connected peers first, falls back to reconnecting to a bootstrap peer.
async fn find_peer(
    state: &AppState,
) -> Result<(saorsa_node::core::PeerId, Vec<saorsa_node::core::MultiAddr>), AntdError> {
    if state.bootstrap_peers.is_empty() {
        return Err(AntdError::Network("no bootstrap peers available".into()));
    }

    // Try connected peers first
    let connected_peers = state.node.connected_peers().await;
    if let Some(peer_id) = connected_peers.first() {
        return Ok((peer_id.clone(), state.bootstrap_peers.clone()));
    }

    // No connected peers — reconnect to first bootstrap peer
    tracing::info!("no connected peers, reconnecting to bootstrap...");
    let peer_addr = &state.bootstrap_peers[0];
    match state.node.connect_peer(peer_addr).await {
        Ok(_channel_id) => {
            // Wait briefly for connection to register
            tokio::time::sleep(Duration::from_millis(200)).await;
            let peers = state.node.connected_peers().await;
            if let Some(peer_id) = peers.first() {
                Ok((peer_id.clone(), state.bootstrap_peers.clone()))
            } else {
                Err(AntdError::Network("connected but peer not yet registered".into()))
            }
        }
        Err(e) => Err(AntdError::Network(format!("failed to reconnect: {e}"))),
    }
}

pub async fn chunk_get(
    State(state): State<Arc<AppState>>,
    Path(addr): Path<String>,
) -> Result<Json<ChunkGetResponse>, AntdError> {
    let address_bytes = hex::decode(&addr)
        .map_err(|e| AntdError::BadRequest(format!("invalid hex address: {e}")))?;
    let address: [u8; 32] = address_bytes
        .try_into()
        .map_err(|_| AntdError::BadRequest("address must be 32 bytes".into()))?;

    let (peer_id, peer_addrs) = find_peer(&state).await?;
    let request_id = rand::random::<u64>();

    let msg = ChunkMessage {
        request_id,
        body: ChunkMessageBody::GetRequest(ChunkGetRequest::new(address)),
    };
    let msg_bytes = msg.encode().map_err(AntdError::from)?;

    let content: Vec<u8> = send_and_await_chunk_response(
        &state.node,
        &peer_id,
        msg_bytes,
        request_id,
        CHUNK_TIMEOUT,
        &peer_addrs,
        |body| match body {
            ChunkMessageBody::GetResponse(ProtoGetResponse::Success { content, .. }) => {
                Some(Ok(content))
            }
            ChunkMessageBody::GetResponse(ProtoGetResponse::NotFound { .. }) => {
                Some(Err(AntdError::NotFound("chunk not found".into())))
            }
            ChunkMessageBody::GetResponse(ProtoGetResponse::Error(e)) => {
                Some(Err(AntdError::from(e)))
            }
            _ => None,
        },
        |e| AntdError::Network(format!("failed to send get request: {e}")),
        || AntdError::Timeout("chunk get timed out".into()),
    )
    .await?;

    Ok(Json(ChunkGetResponse {
        data: BASE64.encode(&content),
    }))
}

pub async fn chunk_put(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ChunkPutRequest>,
) -> Result<Json<ChunkPutResponse>, AntdError> {
    let wallet = state.wallet.as_ref()
        .ok_or_else(|| AntdError::Payment("no EVM wallet configured — set AUTONOMI_WALLET_KEY".into()))?;

    let data = BASE64
        .decode(&req.data)
        .map_err(|e| AntdError::BadRequest(format!("invalid base64: {e}")))?;

    if data.len() > MAX_CHUNK_SIZE {
        return Err(AntdError::BadRequest(format!(
            "chunk size {} exceeds maximum {}",
            data.len(),
            MAX_CHUNK_SIZE
        )));
    }

    let address = compute_address(&data);

    // ── Step 1: Get quotes from 5 peers ──
    tracing::info!(addr = hex::encode(address), "requesting storage quotes from 5 peers...");

    let connected_peers = state.node.connected_peers().await;
    if connected_peers.len() < REQUIRED_QUOTES {
        // Try reconnecting
        for peer_addr in &state.bootstrap_peers {
            if state.node.connected_peers().await.len() >= REQUIRED_QUOTES {
                break;
            }
            let _ = state.node.connect_peer(peer_addr).await;
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    }

    let peers = state.node.connected_peers().await;
    if peers.len() < REQUIRED_QUOTES {
        return Err(AntdError::Network(format!(
            "need {} connected peers for payment, have {}",
            REQUIRED_QUOTES,
            peers.len()
        )));
    }

    let peer_addrs = state.bootstrap_peers.clone();
    let mut quotes_with_prices: Vec<(ant_evm::PaymentQuote, ant_evm::Amount)> = Vec::new();
    let mut quote_peer_ids: Vec<saorsa_node::core::PeerId> = Vec::new();

    for peer_id in peers.iter().take(REQUIRED_QUOTES) {
        let request_id = rand::random::<u64>();
        let msg = ChunkMessage {
            request_id,
            body: ChunkMessageBody::QuoteRequest(ChunkQuoteRequest::new(
                address,
                data.len() as u64,
            )),
        };
        let msg_bytes = msg.encode().map_err(AntdError::from)?;

        let (quote_bytes, already_stored): (Vec<u8>, bool) = send_and_await_chunk_response(
            &state.node,
            peer_id,
            msg_bytes,
            request_id,
            CHUNK_TIMEOUT,
            &peer_addrs,
            |body| match body {
                ChunkMessageBody::QuoteResponse(ProtoQuoteResponse::Success {
                    quote,
                    already_stored,
                }) => Some(Ok((quote, already_stored))),
                ChunkMessageBody::QuoteResponse(ProtoQuoteResponse::Error(e)) => {
                    Some(Err(AntdError::from(e)))
                }
                _ => None,
            },
            |e| AntdError::Network(format!("failed to send quote request: {e}")),
            || AntdError::Timeout("quote request timed out".into()),
        )
        .await?;

        if already_stored {
            tracing::info!(addr = hex::encode(address), "chunk already stored");
            return Ok(Json(ChunkPutResponse {
                cost: "0".to_string(),
                address: hex::encode(address),
            }));
        }

        let payment_quote: ant_evm::PaymentQuote = rmp_serde::from_slice(&quote_bytes)
            .map_err(|e| AntdError::Internal(format!("failed to deserialize quote: {e}")))?;

        let price = saorsa_node::payment::calculate_price(&payment_quote.quoting_metrics);
        quotes_with_prices.push((payment_quote, price));
        quote_peer_ids.push(peer_id.clone());
    }

    tracing::info!(addr = hex::encode(address), "got {} quotes", quotes_with_prices.len());

    // ── Step 2: Create SingleNode payment and pay on-chain ──
    // Save the original quote order before SingleNodePayment sorts them
    let original_quotes: Vec<ant_evm::PaymentQuote> = quotes_with_prices.iter().map(|(q, _)| q.clone()).collect();

    let single_payment = saorsa_node::payment::SingleNodePayment::from_quotes(quotes_with_prices)
        .map_err(|e| AntdError::Payment(format!("failed to create payment: {e}")))?;

    let cost = single_payment.total_amount();
    let cost_str = cost.to_string();
    tracing::info!(addr = hex::encode(address), cost = %cost_str, "paying on-chain...");

    let tx_hashes = single_payment.pay(wallet).await
        .map_err(|e| AntdError::Payment(format!("EVM payment failed: {e}")))?;

    tracing::info!(addr = hex::encode(address), cost = %cost_str, "payment submitted");

    // ── Step 3: Build proof and store chunk ──
    // Build ProofOfPayment with all 5 (peer_id, quote) pairs
    let mut peer_quotes = Vec::new();
    for (i, quote) in original_quotes.into_iter().enumerate() {
        let encoded_peer_id = saorsa_node::client::hex_node_id_to_encoded_peer_id(
            &quote_peer_ids[i].to_hex()
        ).map_err(|e| AntdError::Internal(format!("failed to encode peer ID: {e}")))?;
        peer_quotes.push((encoded_peer_id, quote));
    }

    let payment_proof = saorsa_node::payment::PaymentProof {
        proof_of_payment: ant_evm::ProofOfPayment { peer_quotes },
        tx_hashes,
    };
    let proof_bytes = rmp_serde::to_vec(&payment_proof)
        .map_err(|e| AntdError::Internal(format!("failed to serialize proof: {e}")))?;

    tracing::info!(addr = hex::encode(address), "storing chunk with payment proof...");

    // Send PUT to the first peer (who should be one of the 5 closest)
    let (put_peer_id, _) = find_peer(&state).await?;
    let put_request_id = rand::random::<u64>();
    let put_msg = ChunkMessage {
        request_id: put_request_id,
        body: ChunkMessageBody::PutRequest(ProtoPutRequest::with_payment(
            address,
            data,
            proof_bytes,
        )),
    };
    let put_msg_bytes = put_msg.encode().map_err(AntdError::from)?;

    let result_address: [u8; 32] = send_and_await_chunk_response(
        &state.node,
        &put_peer_id,
        put_msg_bytes,
        put_request_id,
        CHUNK_TIMEOUT,
        &peer_addrs,
        |body| match body {
            ChunkMessageBody::PutResponse(ProtoPutResponse::Success { address }) => {
                Some(Ok(address))
            }
            ChunkMessageBody::PutResponse(ProtoPutResponse::AlreadyExists { address }) => {
                Some(Ok(address))
            }
            ChunkMessageBody::PutResponse(ProtoPutResponse::PaymentRequired { message }) => {
                Some(Err(AntdError::Payment(message)))
            }
            ChunkMessageBody::PutResponse(ProtoPutResponse::Error(e)) => {
                Some(Err(AntdError::from(e)))
            }
            _ => None,
        },
        |e| AntdError::Network(format!("failed to send put request: {e}")),
        || AntdError::Timeout("chunk put timed out".into()),
    )
    .await?;

    tracing::info!(addr = hex::encode(result_address), cost = %cost_str, "chunk stored successfully");

    Ok(Json(ChunkPutResponse {
        cost: cost_str,
        address: hex::encode(result_address),
    }))
}
