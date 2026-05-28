use std::sync::Arc;

use ant_core::data::{CustomNetwork, EvmAddress, EvmNetwork, Wallet as CoreWallet};
use zeroize::Zeroize;

use crate::WalletError;

/// EVM wallet for paying storage costs.
#[derive(uniffi::Object)]
pub struct Wallet {
    pub(crate) inner: CoreWallet,
}

#[uniffi::export(async_runtime = "tokio")]
impl Wallet {
    /// Create a wallet from an EVM private key.
    ///
    /// Uses the default Autonomi EVM network configuration.
    #[uniffi::constructor]
    pub fn from_private_key(
        mut private_key: String,
        rpc_url: String,
        payment_token_address: String,
        payment_vault_address: String,
    ) -> Result<Arc<Self>, WalletError> {
        let network = build_custom_network(&rpc_url, &payment_token_address, &payment_vault_address)?;
        let result = CoreWallet::new_from_private_key(network, &private_key);
        // Clear the private key from memory as soon as possible
        private_key.zeroize();
        let wallet = result.map_err(|e| WalletError::CreationFailed {
                reason: e.to_string(),
            })?;
        Ok(Arc::new(Self { inner: wallet }))
    }

    /// Get the wallet's public address (hex with 0x prefix).
    pub fn address(&self) -> String {
        format!("{:#x}", self.inner.address())
    }

    /// Get the wallet's token balance (atto tokens as decimal string).
    pub async fn balance_of_tokens(&self) -> Result<String, WalletError> {
        let balance = self
            .inner
            .balance_of_tokens()
            .await
            .map_err(|e| WalletError::OperationFailed {
                reason: e.to_string(),
            })?;
        Ok(balance.to_string())
    }

    /// Get the wallet's gas token balance (wei as decimal string).
    pub async fn balance_of_gas_tokens(&self) -> Result<String, WalletError> {
        let balance = self
            .inner
            .balance_of_gas_tokens()
            .await
            .map_err(|e| WalletError::OperationFailed {
                reason: e.to_string(),
            })?;
        Ok(balance.to_string())
    }
}

/// Build a custom EVM network from string-form addresses.
/// Shared by Wallet and the Client `connect_with_wallet` constructor.
pub(crate) fn build_custom_network(
    rpc_url: &str,
    payment_token_address: &str,
    payment_vault_address: &str,
) -> Result<EvmNetwork, WalletError> {
    let rpc_url: url::Url = rpc_url.parse().map_err(|e| {
        WalletError::CreationFailed { reason: format!("invalid RPC URL: {e}") }
    })?;
    let token_addr: EvmAddress = payment_token_address.parse().map_err(|e| {
        WalletError::CreationFailed { reason: format!("invalid token address: {e}") }
    })?;
    let vault_addr: EvmAddress = payment_vault_address.parse().map_err(|e| {
        WalletError::CreationFailed { reason: format!("invalid vault address: {e}") }
    })?;
    Ok(EvmNetwork::Custom(CustomNetwork {
        rpc_url_http: rpc_url,
        payment_token_address: token_addr,
        payment_vault_address: vault_addr,
    }))
}
