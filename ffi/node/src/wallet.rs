//! EVM wallet for paying storage costs (self-custody / private-key path).

use std::sync::Arc;

use napi::bindgen_prelude::*;
use napi_derive::napi;

use crate::convert::wallet_err;

#[napi]
pub struct Wallet {
    inner: Arc<ant_ffi::Wallet>,
}

#[napi]
impl Wallet {
    /// Create a wallet from an EVM private key on a custom network (RPC URL +
    /// token/vault contract addresses). The private key is zeroized inside the
    /// core as soon as the wallet is built.
    #[napi(factory)]
    pub fn from_private_key(
        private_key: String,
        rpc_url: String,
        payment_token_address: String,
        payment_vault_address: String,
    ) -> Result<Wallet> {
        let inner = ant_ffi::Wallet::from_private_key(
            private_key,
            rpc_url,
            payment_token_address,
            payment_vault_address,
        )
        .map_err(wallet_err)?;
        Ok(Wallet { inner })
    }

    /// The wallet's public address (0x-prefixed hex).
    #[napi]
    pub fn address(&self) -> String {
        self.inner.address()
    }

    /// Token balance in atto-tokens (base-10 string).
    #[napi]
    pub async fn balance_of_tokens(&self) -> Result<String> {
        let inner = self.inner.clone();
        inner.balance_of_tokens().await.map_err(wallet_err)
    }

    /// Gas-token balance in wei (base-10 string).
    #[napi]
    pub async fn balance_of_gas_tokens(&self) -> Result<String> {
        let inner = self.inner.clone();
        inner.balance_of_gas_tokens().await.map_err(wallet_err)
    }
}
