use std::sync::Arc;

use crate::network::Network;
use crate::WalletError;

/// Wallet for paying for operations on the Autonomi network
#[derive(uniffi::Object)]
pub struct Wallet {
    pub(crate) inner: autonomi::Wallet,
}

#[uniffi::export(async_runtime = "tokio")]
impl Wallet {
    #[uniffi::constructor]
    pub fn new_from_private_key(
        network: Arc<Network>,
        private_key: String,
    ) -> Result<Arc<Self>, WalletError> {
        let wallet = autonomi::Wallet::new_from_private_key(network.inner.clone(), &private_key)
            .map_err(|e| WalletError::CreationFailed {
                reason: e.to_string(),
            })?;
        Ok(Arc::new(Self { inner: wallet }))
    }

    pub fn address(&self) -> String {
        self.inner.address().to_string()
    }

    pub async fn balance_of_tokens(&self) -> Result<String, WalletError> {
        let balance =
            self.inner
                .balance_of_tokens()
                .await
                .map_err(|e| WalletError::BalanceCheckFailed {
                    reason: e.to_string(),
                })?;
        Ok(balance.to_string())
    }
}

/// Payment option for paid operations
#[derive(uniffi::Enum)]
pub enum PaymentOption {
    WalletPayment { wallet_ref: Arc<Wallet> },
}
