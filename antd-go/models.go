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
// PaymentType is "wave_batch" or "merkle" — determines which fields are populated
// and which contract call the external signer must make.
type PrepareUploadResult struct {
	UploadID    string `json:"upload_id"`    // hex identifier
	PaymentType string `json:"payment_type"` // "wave_batch" or "merkle"

	// Wave-batch fields (present when PaymentType == "wave_batch")
	Payments []PaymentInfo `json:"payments,omitempty"` // per-quote payments for payForQuotes()

	// Merkle fields (present when PaymentType == "merkle")
	Depth                  int                   `json:"depth,omitempty"`                    // merkle tree depth (1-8)
	PoolCommitments        []PoolCommitmentEntry `json:"pool_commitments,omitempty"`         // for payForMerkleTree()
	MerklePaymentTimestamp uint64                `json:"merkle_payment_timestamp,omitempty"` // unix seconds

	// Common fields (always present)
	TotalAmount         string `json:"total_amount"`           // total atto tokens ("0" for merkle)
	PaymentVaultAddress string `json:"payment_vault_address,omitempty"` // payment vault contract address
	PaymentTokenAddress string `json:"payment_token_address"`  // token contract address
	RPCUrl              string `json:"rpc_url"`                // EVM RPC URL
}

// PoolCommitmentEntry describes a pool commitment for the merkle payment contract.
type PoolCommitmentEntry struct {
	PoolHash   string               `json:"pool_hash"`   // hex, 32 bytes with 0x prefix
	Candidates []CandidateNodeEntry `json:"candidates"`  // exactly 16 nodes
}

// CandidateNodeEntry describes a candidate node in a pool commitment.
type CandidateNodeEntry struct {
	RewardsAddress string `json:"rewards_address"` // hex with 0x prefix
	Amount         string `json:"amount"`          // node price as decimal string
}

// FinalizeUploadResult is the result of finalizing an externally-signed upload.
type FinalizeUploadResult struct {
	DataMap      string `json:"data_map"`                // hex-encoded serialized DataMap (always returned)
	Address      string `json:"address,omitempty"`        // network address (only when store_data_map=true)
	ChunksStored int64  `json:"chunks_stored"`           // number of chunks stored
}
