use std::sync::Arc;

#[derive(Debug, uniffi::Error, thiserror::Error)]
pub enum NetworkError {
    #[error("Network creation failed: {reason}")]
    CreationFailed { reason: String },
}

#[derive(uniffi::Object)]
pub struct Network {
    pub(crate) inner: autonomi::Network,
}

#[uniffi::export]
impl Network {
    #[uniffi::constructor]
    pub fn new(is_local: bool) -> Result<Arc<Self>, NetworkError> {
        let network =
            autonomi::Network::new(is_local).map_err(|e| NetworkError::CreationFailed {
                reason: e.to_string(),
            })?;
        Ok(Arc::new(Self { inner: network }))
    }

    #[uniffi::constructor]
    pub fn custom(
        rpc_url: String,
        payment_token_address: String,
        data_payments_address: String,
        royalties_pk_hex: Option<String>,
    ) -> Arc<Self> {
        let network = autonomi::Network::new_custom(
            &rpc_url,
            &payment_token_address,
            &data_payments_address,
            royalties_pk_hex.as_deref(),
        );
        Arc::new(Self { inner: network })
    }
}
