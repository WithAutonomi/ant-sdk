use std::sync::Arc;

use crate::WalletError;

/// EVM wallet for paying storage costs.
#[derive(uniffi::Object)]
pub struct Wallet {
    pub(crate) inner: evmlib::wallet::Wallet,
}

#[uniffi::export(async_runtime = "tokio")]
impl Wallet {
    /// Create a wallet from an EVM private key.
    ///
    /// Uses the default Autonomi EVM network configuration.
    #[uniffi::constructor]
    pub fn from_private_key(
        private_key: String,
        rpc_url: String,
        payment_token_address: String,
        data_payments_address: String,
    ) -> Result<Arc<Self>, WalletError> {
        let network = evmlib::Network::new_custom(
            &rpc_url,
            &payment_token_address,
            &data_payments_address,
            None,
        );
        let wallet = evmlib::wallet::Wallet::new_from_private_key(network, &private_key)
            .map_err(|e| WalletError::CreationFailed {
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
