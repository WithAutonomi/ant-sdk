//! gRPC `PointerService`: the REST `/v1/pointers` surface over
//! [`crate::pointers`], converted to the proto shapes.

use std::sync::Arc;

use tonic::{Request, Response, Status};

use super::service::{pb, to_pb_signed_quote};
use crate::error::AntdError;
use crate::pointers::{self, parse_address, parse_prepared_write, parse_target};
use crate::state::AppState;
use crate::types::{PointerFinalStateEntry, PointerFinalityResponse};

pub struct PointerServiceImpl {
    pub state: Arc<AppState>,
}

/// Proto3 strings have no null: an empty string means "not set".
fn non_empty(s: &str) -> Option<&str> {
    (!s.is_empty()).then_some(s)
}

fn to_pb_final_state(state: &PointerFinalStateEntry) -> pb::PointerFinalState {
    pb::PointerFinalState {
        state_id: state.state_id.clone(),
        kind: state.kind.clone(),
        kind_tag: u32::from(state.kind_tag),
        target: state.target.clone(),
        holders: state.holders,
        transferred_to: state.transferred_to.clone().unwrap_or_default(),
    }
}

fn to_pb_finality(finality: &PointerFinalityResponse) -> pb::PointerFinality {
    pb::PointerFinality {
        address: finality.address.clone(),
        group: finality.group,
        answered: finality.answered,
        status: finality.status.clone(),
        counter: finality.counter.clone().unwrap_or_default(),
        state: finality.state.as_ref().map(to_pb_final_state),
        states: finality.states.iter().map(to_pb_final_state).collect(),
        majority: finality.majority.as_ref().map(to_pb_final_state),
        transferred_to: finality.transferred_to.clone().unwrap_or_default(),
    }
}

fn to_pb_write(w: crate::types::PointerWriteResponse) -> pb::PointerWriteResponse {
    pb::PointerWriteResponse {
        address: w.address,
        state_id: w.state_id,
        counter: w.counter,
    }
}

#[tonic::async_trait]
impl pb::pointer_service_server::PointerService for PointerServiceImpl {
    async fn list_keys(
        &self,
        _request: Request<pb::ListPointerKeysRequest>,
    ) -> Result<Response<pb::ListPointerKeysResponse>, Status> {
        let keys = pointers::keys(&self.state)
            .keys
            .into_iter()
            .map(|k| pb::PointerKey { address: k.address })
            .collect();
        Ok(Response::new(pb::ListPointerKeysResponse { keys }))
    }

    async fn create(
        &self,
        request: Request<pb::PointerWriteRequest>,
    ) -> Result<Response<pb::PointerWriteResponse>, Status> {
        let req = request.into_inner();
        let owner = parse_address("owner", &req.owner)?;
        let target = parse_target(&req.target, non_empty(&req.kind))?;
        let written = pointers::create(&self.state, owner, target).await?;
        Ok(Response::new(to_pb_write(written)))
    }

    async fn update(
        &self,
        request: Request<pb::PointerWriteRequest>,
    ) -> Result<Response<pb::PointerWriteResponse>, Status> {
        let req = request.into_inner();
        let owner = parse_address("owner", &req.owner)?;
        let target = parse_target(&req.target, non_empty(&req.kind))?;
        let written = pointers::update(&self.state, owner, target).await?;
        Ok(Response::new(to_pb_write(written)))
    }

    async fn transfer(
        &self,
        request: Request<pb::PointerTransferRequest>,
    ) -> Result<Response<pb::PointerTransferResponse>, Status> {
        let req = request.into_inner();
        let owner = parse_address("owner", &req.owner)?;
        let recipient = parse_address("recipient", &req.recipient)?;
        let t = pointers::transfer(&self.state, owner, recipient).await?;
        Ok(Response::new(pb::PointerTransferResponse {
            address: t.address,
            state_id: t.state_id,
            finality: t.finality.as_ref().map(to_pb_finality),
            finality_error: t.finality_error.unwrap_or_default(),
        }))
    }

    async fn get(
        &self,
        request: Request<pb::GetPointerRequest>,
    ) -> Result<Response<pb::PointerRecord>, Status> {
        let address = parse_address("address", &request.into_inner().address)?;
        let r = pointers::get(&self.state, address).await?;
        Ok(Response::new(pb::PointerRecord {
            address: r.address,
            owner: r.owner,
            counter: r.counter,
            kind: r.kind,
            kind_tag: u32::from(r.kind_tag),
            target: r.target,
            state_id: r.state_id,
            is_final: r.is_final,
            transferred_to: r.transferred_to.unwrap_or_default(),
        }))
    }

    async fn resolve(
        &self,
        request: Request<pb::ResolvePointerRequest>,
    ) -> Result<Response<pb::PointerResolved>, Status> {
        let address = parse_address("address", &request.into_inner().address)?;
        let r = pointers::resolve(&self.state, address).await?;
        Ok(Response::new(pb::PointerResolved {
            kind: r.kind,
            kind_tag: u32::from(r.kind_tag),
            target: r.target,
        }))
    }

    async fn finality(
        &self,
        request: Request<pb::PointerFinalityRequest>,
    ) -> Result<Response<pb::PointerFinality>, Status> {
        let address = parse_address("address", &request.into_inner().address)?;
        let f = pointers::finality(&self.state, address).await?;
        Ok(Response::new(to_pb_finality(&f)))
    }

    async fn controller(
        &self,
        request: Request<pb::PointerControllerRequest>,
    ) -> Result<Response<pb::PointerController>, Status> {
        let address = parse_address("address", &request.into_inner().address)?;
        let c = pointers::controller(&self.state, address).await?;
        Ok(Response::new(pb::PointerController {
            pointer: c.pointer,
            transfers: c.transfers,
            frozen: c.frozen,
        }))
    }

    async fn prepare(
        &self,
        request: Request<pb::PreparePointerRequest>,
    ) -> Result<Response<pb::PreparePointerResponse>, Status> {
        let req = request.into_inner();
        let owner = parse_address("owner", &req.owner)?;
        let prepared = parse_prepared_write(
            &req.op,
            non_empty(&req.target),
            non_empty(&req.kind),
            non_empty(&req.recipient),
        )?;
        let p = pointers::prepare(&self.state, owner, prepared, req.include_signed_quotes).await?;
        let signed_quotes = p
            .signed_quotes
            .as_deref()
            .unwrap_or_default()
            .iter()
            .map(to_pb_signed_quote)
            .collect::<Result<Vec<_>, AntdError>>()?;
        Ok(Response::new(pb::PreparePointerResponse {
            upload_id: p.upload_id,
            op: p.op,
            address: p.address,
            state_id: p.state_id,
            counter: p.counter,
            payment_type: p.payment_type,
            payments: p
                .payments
                .into_iter()
                .map(|e| pb::PaymentEntry {
                    quote_hash: e.quote_hash,
                    rewards_address: e.rewards_address,
                    amount: e.amount,
                })
                .collect(),
            total_amount: p.total_amount,
            payment_vault_address: p.payment_vault_address,
            payment_token_address: p.payment_token_address,
            rpc_url: p.rpc_url,
            signed_quotes,
        }))
    }

    async fn finalize(
        &self,
        request: Request<pb::FinalizePointerRequest>,
    ) -> Result<Response<pb::FinalizePointerResponse>, Status> {
        let req = request.into_inner();
        let f = pointers::finalize(&self.state, &req.upload_id, &req.tx_hashes).await?;
        Ok(Response::new(pb::FinalizePointerResponse {
            address: f.address,
            state_id: f.state_id,
            counter: f.counter,
            finality: f.finality.as_ref().map(to_pb_finality),
        }))
    }
}
