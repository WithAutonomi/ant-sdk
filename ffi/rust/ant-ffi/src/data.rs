/// Re-export ant-core types used in FFI signatures.
pub use ant_core::data::{CostEstimateConfidence, PaymentMode};

/// Result of a data upload operation (internal, not exposed via UniFFI).
pub struct DataUploadResult {
    pub data_map: ant_core::data::DataMap,
    pub chunks_stored: usize,
    pub payment_mode_used: PaymentMode,
}

/// Result of a file upload operation (internal, not exposed via UniFFI).
pub struct FileUploadResult {
    pub data_map: ant_core::data::DataMap,
    pub chunks_stored: usize,
    pub payment_mode_used: PaymentMode,
}

/// Parse a payment mode string into ant-core's PaymentMode.
pub fn parse_payment_mode(mode: &str) -> Result<PaymentMode, String> {
    match mode {
        "auto" => Ok(PaymentMode::Auto),
        "merkle" => Ok(PaymentMode::Merkle),
        "single" => Ok(PaymentMode::Single),
        other => Err(format!(
            "invalid payment_mode: {other:?}. Use \"auto\", \"merkle\", or \"single\""
        )),
    }
}

/// Format a PaymentMode for FFI results.
pub fn format_payment_mode(mode: PaymentMode) -> String {
    match mode {
        PaymentMode::Auto => "auto".into(),
        PaymentMode::Merkle => "merkle".into(),
        PaymentMode::Single => "single".into(),
    }
}

/// Format a cost-estimate confidence for FFI results. Strings match ant-core's
/// serde `snake_case` names so callers can rely on a stable vocabulary.
pub fn format_cost_confidence(confidence: CostEstimateConfidence) -> String {
    match confidence {
        CostEstimateConfidence::PricedSample => "priced_sample".into(),
        CostEstimateConfidence::VerifiedAllAlreadyStored => "verified_all_already_stored".into(),
        CostEstimateConfidence::AllSamplesAlreadyStoredIncomplete => {
            "all_samples_already_stored_incomplete".into()
        }
    }
}
