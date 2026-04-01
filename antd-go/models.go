package antd

// HealthStatus is the result of a health check.
type HealthStatus struct {
	OK      bool   `json:"ok"`
	Network string `json:"network"`
}

// PutResult is the result of a put/create operation.
type PutResult struct {
	Cost    string `json:"cost"`    // atto tokens as string
	Address string `json:"address"` // hex
}

// ArchiveEntry is a single entry in a file archive.
type ArchiveEntry struct {
	Path     string `json:"path"`
	Address  string `json:"address"`
	Created  int64  `json:"created"`
	Modified int64  `json:"modified"`
	Size     int64  `json:"size"`
}

// Archive is a collection of archive entries.
type Archive struct {
	Entries []ArchiveEntry `json:"entries"`
}

// WalletAddress is the result of a wallet address query.
type WalletAddress struct {
	Address string `json:"address"` // hex with 0x prefix
}

// WalletBalance is the result of a wallet balance query.
type WalletBalance struct {
	Balance    string `json:"balance"`     // token balance in atto
	GasBalance string `json:"gas_balance"` // gas balance in wei
}

// PaymentInfo describes a single payment required for an upload.
type PaymentInfo struct {
	QuoteHash      string `json:"quote_hash"`      // hex
	RewardsAddress string `json:"rewards_address"` // hex
	Amount         string `json:"amount"`          // atto tokens as string
}

// PrepareUploadResult is the result of preparing an upload for external signing.
type PrepareUploadResult struct {
	UploadID            string        `json:"upload_id"`             // hex identifier
	Payments            []PaymentInfo `json:"payments"`              // payments to sign
	TotalAmount         string        `json:"total_amount"`          // total atto tokens
	DataPaymentsAddress string        `json:"data_payments_address"` // contract address
	PaymentTokenAddress string        `json:"payment_token_address"` // token contract address
	RPCUrl              string        `json:"rpc_url"`               // EVM RPC URL
}

// FinalizeUploadResult is the result of finalizing an externally-signed upload.
type FinalizeUploadResult struct {
	DataMap      string `json:"data_map"`                // hex-encoded serialized DataMap (always returned)
	Address      string `json:"address,omitempty"`        // network address (only when store_data_map=true)
	ChunksStored int64  `json:"chunks_stored"`           // number of chunks stored
}
