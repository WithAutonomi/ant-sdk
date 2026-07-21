/// Re-export ant-core types used in FFI signatures.
pub use ant_core::data::{CostEstimateConfidence, PaymentMode as CorePaymentMode};

/// Result of a data upload operation (internal, not exposed via UniFFI).
pub struct DataUploadResult {
    pub data_map: ant_core::data::DataMap,
    pub chunks_stored: usize,
    pub payment_mode_used: CorePaymentMode,
}

/// Result of a file upload operation (internal, not exposed via UniFFI).
pub struct FileUploadResult {
    pub data_map: ant_core::data::DataMap,
    pub chunks_stored: usize,
    pub payment_mode_used: CorePaymentMode,
}

// Total conversions between the FFI-facing enums and ant-core's. Plain fns
// rather than `From` impls — the orphan rule forbids `impl From<Local> for
// ant_core::...`.

/// FFI [`crate::PaymentMode`] -> ant-core.
pub fn to_core_payment_mode(mode: crate::PaymentMode) -> CorePaymentMode {
    match mode {
        crate::PaymentMode::Auto => CorePaymentMode::Auto,
        crate::PaymentMode::Merkle => CorePaymentMode::Merkle,
        crate::PaymentMode::Single => CorePaymentMode::Single,
    }
}

/// ant-core payment mode -> FFI [`crate::PaymentMode`] (for results).
pub fn from_core_payment_mode(mode: CorePaymentMode) -> crate::PaymentMode {
    match mode {
        CorePaymentMode::Auto => crate::PaymentMode::Auto,
        CorePaymentMode::Merkle => crate::PaymentMode::Merkle,
        CorePaymentMode::Single => crate::PaymentMode::Single,
    }
}

/// FFI [`crate::Visibility`] -> ant-core.
pub fn to_core_visibility(visibility: crate::Visibility) -> ant_core::data::Visibility {
    match visibility {
        crate::Visibility::Public => ant_core::data::Visibility::Public,
        crate::Visibility::Private => ant_core::data::Visibility::Private,
    }
}

/// ant-core cost-estimate confidence -> FFI [`crate::CostConfidence`].
pub fn from_core_confidence(confidence: CostEstimateConfidence) -> crate::CostConfidence {
    match confidence {
        CostEstimateConfidence::PricedSample => crate::CostConfidence::PricedSample,
        CostEstimateConfidence::VerifiedAllAlreadyStored => {
            crate::CostConfidence::VerifiedAllAlreadyStored
        }
        CostEstimateConfidence::AllSamplesAlreadyStoredIncomplete => {
            crate::CostConfidence::AllSamplesAlreadyStoredIncomplete
        }
    }
}
