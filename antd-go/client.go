package antd

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// DefaultBaseURL is the default address of the antd daemon.
const DefaultBaseURL = "http://localhost:8082"

// DefaultTimeout is the default request timeout.
const DefaultTimeout = 5 * time.Minute

// Option configures a Client.
type Option func(*Client)

// WithTimeout sets the HTTP request timeout.
func WithTimeout(d time.Duration) Option {
	return func(c *Client) { c.timeout = d }
}

// WithHTTPClient sets a custom http.Client.
func WithHTTPClient(hc *http.Client) Option {
	return func(c *Client) { c.http = hc }
}

// Client is a REST client for the antd daemon.
type Client struct {
	baseURL string
	timeout time.Duration
	http    *http.Client
}

// NewClientAutoDiscover creates a client that discovers the daemon URL automatically.
// It reads the port file written by antd on startup, falling back to DefaultBaseURL.
// Returns the client and the resolved URL.
func NewClientAutoDiscover(opts ...Option) (*Client, string) {
	url := DiscoverDaemonURL()
	if url == "" {
		url = DefaultBaseURL
	}
	return NewClient(url, opts...), url
}

// NewClient creates a new antd REST client.
func NewClient(baseURL string, opts ...Option) *Client {
	c := &Client{
		baseURL: strings.TrimRight(baseURL, "/"),
		timeout: DefaultTimeout,
	}
	for _, o := range opts {
		o(c)
	}
	if c.http == nil {
		c.http = &http.Client{Timeout: c.timeout}
	}
	return c
}

// --- internal helpers ---

func b64Encode(data []byte) string {
	return base64.StdEncoding.EncodeToString(data)
}

func b64Decode(s string) ([]byte, error) {
	return base64.StdEncoding.DecodeString(s)
}

func (c *Client) url(path string) string {
	return c.baseURL + path
}

func (c *Client) doJSON(ctx context.Context, method, path string, body any) (map[string]any, int, error) {
	var reqBody io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return nil, 0, fmt.Errorf("marshal request: %w", err)
		}
		reqBody = bytes.NewReader(b)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.url(path), reqBody)
	if err != nil {
		return nil, 0, fmt.Errorf("create request: %w", err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("http request: %w", err)
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, resp.StatusCode, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		msg := string(respBytes)
		var parsed map[string]any
		if json.Unmarshal(respBytes, &parsed) == nil {
			if e, ok := parsed["error"].(string); ok {
				msg = e
			}
		}
		return nil, resp.StatusCode, errorForStatus(resp.StatusCode, msg)
	}

	if len(respBytes) == 0 {
		return nil, resp.StatusCode, nil
	}

	var result map[string]any
	if err := json.Unmarshal(respBytes, &result); err != nil {
		return nil, resp.StatusCode, fmt.Errorf("unmarshal response: %w", err)
	}
	return result, resp.StatusCode, nil
}

// doStream issues a request and, on a 2xx status, returns the raw response body
// for the caller to read incrementally (constant memory). On a non-2xx status
// it reads and parses the JSON error body and returns an error. The caller MUST
// Close the returned ReadCloser.
//
// Note: a client-level http.Client.Timeout also bounds body reads, so for very
// large streams configure the client without a Timeout (via WithHTTPClient) and
// rely on ctx for cancellation.
func (c *Client) doStream(ctx context.Context, method, path string, body any) (io.ReadCloser, error) {
	var reqBody io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("marshal request: %w", err)
		}
		reqBody = bytes.NewReader(b)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.url(path), reqBody)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("http request: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		defer resp.Body.Close()
		respBytes, _ := io.ReadAll(resp.Body)
		msg := string(respBytes)
		var parsed map[string]any
		if json.Unmarshal(respBytes, &parsed) == nil {
			if e, ok := parsed["error"].(string); ok {
				msg = e
			}
		}
		return nil, errorForStatus(resp.StatusCode, msg)
	}

	return resp.Body, nil
}

func str(m map[string]any, key string) string {
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}

func num64(m map[string]any, key string) int64 {
	if v, ok := m[key].(float64); ok {
		return int64(v)
	}
	return 0
}

func unum64(m map[string]any, key string) uint64 {
	if v, ok := m[key].(float64); ok {
		return uint64(v)
	}
	return 0
}

func boolField(m map[string]any, key string) bool {
	if v, ok := m[key].(bool); ok {
		return v
	}
	return false
}

func arrAt(m map[string]any, key string) []any {
	if v, ok := m[key].([]any); ok {
		return v
	}
	return nil
}

// --- Health ---

// Health checks the antd daemon status.
func (c *Client) Health(ctx context.Context) (*HealthStatus, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/health", nil)
	if err != nil {
		return nil, err
	}
	return &HealthStatus{
		OK:                  str(j, "status") == "ok",
		Network:             str(j, "network"),
		Version:             str(j, "version"),
		EvmNetwork:          str(j, "evm_network"),
		UptimeSeconds:       unum64(j, "uptime_seconds"),
		BuildCommit:         str(j, "build_commit"),
		PaymentTokenAddress: str(j, "payment_token_address"),
		PaymentVaultAddress: str(j, "payment_vault_address"),
	}, nil
}

// PaymentMode controls how payments are made for storage operations.
type PaymentMode string

const (
	// PaymentModeAuto lets the server choose the best payment strategy.
	PaymentModeAuto PaymentMode = "auto"
	// PaymentModeMerkle uses Merkle-based batch payments.
	PaymentModeMerkle PaymentMode = "merkle"
	// PaymentModeSingle uses individual payment per chunk.
	PaymentModeSingle PaymentMode = "single"
)

// --- Data ---

// DataPut stores private encrypted data on the network and returns the
// caller-held DataMap (hex). The DataMap is NOT stored on-network — the caller
// keeps it as the only retrieval handle.
func (c *Client) DataPut(ctx context.Context, data []byte, paymentMode PaymentMode) (*DataPutResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/data", map[string]any{
		"data":         b64Encode(data),
		"payment_mode": string(paymentMode),
	})
	if err != nil {
		return nil, err
	}
	return &DataPutResult{
		DataMap:         str(j, "data_map"),
		ChunksStored:    unum64(j, "chunks_stored"),
		PaymentModeUsed: str(j, "payment_mode_used"),
	}, nil
}

// DataGet retrieves private data from a caller-held DataMap (hex).
func (c *Client) DataGet(ctx context.Context, dataMap string) ([]byte, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/data/get", map[string]any{
		"data_map": dataMap,
	})
	if err != nil {
		return nil, err
	}
	return b64Decode(str(j, "data"))
}

// DataPutPublic stores public immutable data on the network. The DataMap is
// stored on-network as an extra chunk; the returned address is the shareable
// retrieval handle.
func (c *Client) DataPutPublic(ctx context.Context, data []byte, paymentMode PaymentMode) (*DataPutPublicResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/data/public", map[string]any{
		"data":         b64Encode(data),
		"payment_mode": string(paymentMode),
	})
	if err != nil {
		return nil, err
	}
	return &DataPutPublicResult{
		Address:         str(j, "address"),
		ChunksStored:    unum64(j, "chunks_stored"),
		PaymentModeUsed: str(j, "payment_mode_used"),
	}, nil
}

// DataGetPublic retrieves public data by address.
func (c *Client) DataGetPublic(ctx context.Context, address string) ([]byte, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/data/public/"+address, nil)
	if err != nil {
		return nil, err
	}
	return b64Decode(str(j, "data"))
}

// DataStream streams private data from a caller-held DataMap (hex) instead of
// buffering the whole object in memory. It is the streaming counterpart to
// DataGet, suitable for large blobs or piping straight to a writer. The caller
// reads the returned stream and MUST Close it. The response carries a
// Content-Length, so a stream that ends short signals a failed download.
func (c *Client) DataStream(ctx context.Context, dataMap string) (io.ReadCloser, error) {
	return c.doStream(ctx, http.MethodPost, "/v1/data/stream", map[string]any{
		"data_map": dataMap,
	})
}

// DataStreamPublic streams public data by address — the streaming counterpart
// to DataGetPublic. The caller reads the returned stream and MUST Close it.
func (c *Client) DataStreamPublic(ctx context.Context, address string) (io.ReadCloser, error) {
	return c.doStream(ctx, http.MethodGet, "/v1/data/public/"+address+"/stream", nil)
}

// DataCost returns a pre-upload cost breakdown for the given bytes.
//
// The server samples a small number of chunk addresses and extrapolates —
// much faster than quoting every chunk on slow networks. Gas is advisory.
func (c *Client) DataCost(ctx context.Context, data []byte, paymentMode PaymentMode) (*UploadCostEstimate, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/data/cost", map[string]any{
		"data":         b64Encode(data),
		"payment_mode": string(paymentMode),
	})
	if err != nil {
		return nil, err
	}
	return &UploadCostEstimate{
		Cost:                str(j, "cost"),
		FileSize:            unum64(j, "file_size"),
		ChunkCount:          uint32(unum64(j, "chunk_count")),
		EstimatedGasCostWei: str(j, "estimated_gas_cost_wei"),
		PaymentMode:         str(j, "payment_mode"),
	}, nil
}

// --- Chunks ---

// ChunkPut stores a raw chunk on the network.
func (c *Client) ChunkPut(ctx context.Context, data []byte) (*PutResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/chunks", map[string]any{
		"data": b64Encode(data),
	})
	if err != nil {
		return nil, err
	}
	return &PutResult{Cost: str(j, "cost"), Address: str(j, "address")}, nil
}

// ChunkGet retrieves a chunk by address.
func (c *Client) ChunkGet(ctx context.Context, address string) ([]byte, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/chunks/"+address, nil)
	if err != nil {
		return nil, err
	}
	return b64Decode(str(j, "data"))
}

// PrepareChunkUpload prepares a single chunk for external-signer publish via
// POST /v1/chunks/prepare.
//
// The daemon collects storage quotes from the close group, stashes the
// prepared state, and returns either:
//
//   - AlreadyStored = true and Address set, if the chunk is already on-network.
//     No payment or finalize call is needed.
//   - AlreadyStored = false with UploadID + Payments + TotalAmount populated,
//     in which case the caller signs and submits payForQuotes() externally,
//     then calls FinalizeChunkUpload with the resulting tx hashes.
//
// Unlike ChunkPut, this method does NOT require the daemon to have a wallet —
// all funds flow through the external signer.
//
// Requires antd >= 0.7.0.
func (c *Client) PrepareChunkUpload(ctx context.Context, content []byte) (*PrepareChunkResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/chunks/prepare", map[string]any{
		"data": b64Encode(content),
	})
	if err != nil {
		return nil, err
	}

	r := &PrepareChunkResult{
		Address:             str(j, "address"),
		AlreadyStored:       boolField(j, "already_stored"),
		UploadID:            str(j, "upload_id"),
		PaymentType:         str(j, "payment_type"),
		TotalAmount:         str(j, "total_amount"),
		PaymentVaultAddress: str(j, "payment_vault_address"),
		PaymentTokenAddress: str(j, "payment_token_address"),
		RPCUrl:              str(j, "rpc_url"),
	}
	if payments, ok := j["payments"].([]any); ok {
		for _, p := range payments {
			pm, ok := p.(map[string]any)
			if !ok {
				continue
			}
			r.Payments = append(r.Payments, PaymentInfo{
				QuoteHash:      str(pm, "quote_hash"),
				RewardsAddress: str(pm, "rewards_address"),
				Amount:         str(pm, "amount"),
			})
		}
	}
	return r, nil
}

// FinalizeChunkUpload submits a single chunk to the network after the external
// signer has paid via POST /v1/chunks/finalize.
//
// txHashes maps each non-zero quote_hash from PrepareChunkUpload's Payments to
// the corresponding tx_hash returned by payForQuotes(). Returns the hex-encoded
// network address of the stored chunk (matches PrepareChunkResult.Address).
//
// Requires antd >= 0.7.0.
func (c *Client) FinalizeChunkUpload(ctx context.Context, uploadID string, txHashes map[string]string) (string, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/chunks/finalize", map[string]any{
		"upload_id": uploadID,
		"tx_hashes": txHashes,
	})
	if err != nil {
		return "", err
	}
	return str(j, "address"), nil
}

// --- Files ---

// FilePut uploads a local file as a private upload and returns the caller-held
// DataMap (hex). The DataMap is NOT stored on-network.
func (c *Client) FilePut(ctx context.Context, path string, paymentMode PaymentMode) (*FilePutResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/files", map[string]any{
		"path":         path,
		"payment_mode": string(paymentMode),
	})
	if err != nil {
		return nil, err
	}
	return &FilePutResult{
		DataMap:         str(j, "data_map"),
		StorageCostAtto: str(j, "storage_cost_atto"),
		GasCostWei:      str(j, "gas_cost_wei"),
		ChunksStored:    unum64(j, "chunks_stored"),
		PaymentModeUsed: str(j, "payment_mode_used"),
	}, nil
}

// FileGet downloads a private file from a caller-held DataMap (hex) into destPath.
func (c *Client) FileGet(ctx context.Context, dataMap, destPath string) error {
	_, _, err := c.doJSON(ctx, http.MethodPost, "/v1/files/get", map[string]any{
		"data_map":  dataMap,
		"dest_path": destPath,
	})
	return err
}

// FilePutPublic uploads a local file as a public upload. The DataMap is stored
// on-network as an extra chunk; the returned address is the shareable handle.
func (c *Client) FilePutPublic(ctx context.Context, path string, paymentMode PaymentMode) (*FilePutPublicResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/files/public", map[string]any{
		"path":         path,
		"payment_mode": string(paymentMode),
	})
	if err != nil {
		return nil, err
	}
	return &FilePutPublicResult{
		Address:         str(j, "address"),
		StorageCostAtto: str(j, "storage_cost_atto"),
		GasCostWei:      str(j, "gas_cost_wei"),
		ChunksStored:    unum64(j, "chunks_stored"),
		PaymentModeUsed: str(j, "payment_mode_used"),
	}, nil
}

// FileGetPublic downloads a public file from an on-network DataMap address into destPath.
func (c *Client) FileGetPublic(ctx context.Context, address, destPath string) error {
	_, _, err := c.doJSON(ctx, http.MethodPost, "/v1/files/public/get", map[string]any{
		"address":   address,
		"dest_path": destPath,
	})
	return err
}

// FileCost returns a pre-upload cost breakdown for the file at path.
//
// The server samples a small number of chunk addresses and extrapolates —
// much faster than quoting every chunk on slow networks. Gas is advisory.
func (c *Client) FileCost(ctx context.Context, path string, isPublic bool, paymentMode PaymentMode) (*UploadCostEstimate, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/files/cost", map[string]any{
		"path":         path,
		"is_public":    isPublic,
		"payment_mode": string(paymentMode),
	})
	if err != nil {
		return nil, err
	}
	return &UploadCostEstimate{
		Cost:                str(j, "cost"),
		FileSize:            unum64(j, "file_size"),
		ChunkCount:          uint32(unum64(j, "chunk_count")),
		EstimatedGasCostWei: str(j, "estimated_gas_cost_wei"),
		PaymentMode:         str(j, "payment_mode"),
	}, nil
}

// --- Wallet ---

// WalletAddress returns the wallet's public address.
func (c *Client) WalletAddress(ctx context.Context) (*WalletAddress, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/wallet/address", nil)
	if err != nil {
		return nil, err
	}
	return &WalletAddress{Address: str(j, "address")}, nil
}

// WalletBalance returns the wallet's token and gas balances.
func (c *Client) WalletBalance(ctx context.Context) (*WalletBalance, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/wallet/balance", nil)
	if err != nil {
		return nil, err
	}
	return &WalletBalance{
		Balance:    str(j, "balance"),
		GasBalance: str(j, "gas_balance"),
	}, nil
}

// WalletApprove approves the wallet to spend tokens on payment contracts.
// This is a one-time operation required before any storage operations.
func (c *Client) WalletApprove(ctx context.Context) error {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/wallet/approve", map[string]any{})
	if err != nil {
		return err
	}
	_ = j
	return nil
}

// --- External Signer (Two-Phase Upload) ---

// parsePrepareResponse parses a prepare-upload JSON response into PrepareUploadResult.
// Handles both wave_batch and merkle payment types.
func parsePrepareResponse(j map[string]any) *PrepareUploadResult {
	result := &PrepareUploadResult{
		UploadID:            str(j, "upload_id"),
		PaymentType:         str(j, "payment_type"),
		TotalAmount:         str(j, "total_amount"),
		PaymentVaultAddress: str(j, "payment_vault_address"),
		PaymentTokenAddress: str(j, "payment_token_address"),
		RPCUrl:              str(j, "rpc_url"),
		TotalChunks:         int(num64(j, "total_chunks")),
		AlreadyStoredCount:  int(num64(j, "already_stored_count")),
	}

	// Default to wave_batch for backward compatibility with older daemons
	if result.PaymentType == "" {
		result.PaymentType = "wave_batch"
	}

	// Parse wave-batch payments
	for _, p := range arrAt(j, "payments") {
		if pm, ok := p.(map[string]any); ok {
			result.Payments = append(result.Payments, PaymentInfo{
				QuoteHash:      str(pm, "quote_hash"),
				RewardsAddress: str(pm, "rewards_address"),
				Amount:         str(pm, "amount"),
			})
		}
	}

	// Parse merkle fields
	if result.PaymentType == "merkle" {
		result.Depth = int(num64(j, "depth"))
		result.MerklePaymentTimestamp = uint64(num64(j, "merkle_payment_timestamp"))

		for _, pc := range arrAt(j, "pool_commitments") {
			if pcm, ok := pc.(map[string]any); ok {
				entry := PoolCommitmentEntry{
					PoolHash: str(pcm, "pool_hash"),
				}
				for _, c := range arrAt(pcm, "candidates") {
					if cm, ok := c.(map[string]any); ok {
						entry.Candidates = append(entry.Candidates, CandidateNodeEntry{
							RewardsAddress: str(cm, "rewards_address"),
							Amount:         str(cm, "amount"),
						})
					}
				}
				result.PoolCommitments = append(result.PoolCommitments, entry)
			}
		}
	}

	return result
}

// PrepareUpload prepares a private file upload for external signing.
// Returns payment details that an external signer must process before calling
// FinalizeUpload (wave_batch) or FinalizeMerkleUpload (merkle).
func (c *Client) PrepareUpload(ctx context.Context, path string) (*PrepareUploadResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/upload/prepare", map[string]any{
		"path": path,
	})
	if err != nil {
		return nil, err
	}
	return parsePrepareResponse(j), nil
}

// PrepareUploadPublic prepares a public file upload for external signing.
// In addition to the data chunks, the daemon bundles the serialized DataMap
// chunk into the same payment batch — so the external signer signs ONE EVM
// transaction covering chunks + DataMap. After FinalizeUpload, the result's
// DataMapAddress is the shareable retrieval handle.
//
// Requires antd >= 0.6.1.
func (c *Client) PrepareUploadPublic(ctx context.Context, path string) (*PrepareUploadResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/upload/prepare", map[string]any{
		"path":       path,
		"visibility": "public",
	})
	if err != nil {
		return nil, err
	}
	return parsePrepareResponse(j), nil
}

// PrepareDataUpload prepares a private data upload for external signing.
// Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
// Returns payment details that an external signer must process before calling
// FinalizeUpload (wave_batch) or FinalizeMerkleUpload (merkle).
//
// The public variant of this endpoint is not yet available — the daemon
// returns 501 for visibility:"public" until upstream ant-core exposes
// data_prepare_upload_with_visibility. Use PrepareUploadPublic with a file
// path instead.
func (c *Client) PrepareDataUpload(ctx context.Context, data []byte) (*PrepareUploadResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/data/prepare", map[string]any{
		"data": b64Encode(data),
	})
	if err != nil {
		return nil, err
	}
	return parsePrepareResponse(j), nil
}

// FinalizeUpload finalizes a wave-batch upload after an external signer has submitted payment transactions.
// txHashes maps quote_hash to tx_hash for each payment.
// If storeDataMap is true, the DataMap is also stored on-network and Address is returned (requires a daemon wallet).
func (c *Client) FinalizeUpload(ctx context.Context, uploadID string, txHashes map[string]string, storeDataMap bool) (*FinalizeUploadResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/upload/finalize", map[string]any{
		"upload_id":      uploadID,
		"tx_hashes":      txHashes,
		"store_data_map": storeDataMap,
	})
	if err != nil {
		return nil, err
	}
	return &FinalizeUploadResult{
		DataMap:        str(j, "data_map"),
		Address:        str(j, "address"),
		DataMapAddress: str(j, "data_map_address"),
		ChunksStored:   num64(j, "chunks_stored"),
	}, nil
}

// FinalizeMerkleUpload finalizes a merkle upload after the external signer has submitted
// the payForMerkleTree transaction. winnerPoolHash is the bytes32 value from the
// MerklePaymentMade event (hex with 0x prefix).
func (c *Client) FinalizeMerkleUpload(ctx context.Context, uploadID string, winnerPoolHash string, storeDataMap bool) (*FinalizeUploadResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/upload/finalize", map[string]any{
		"upload_id":        uploadID,
		"winner_pool_hash": winnerPoolHash,
		"store_data_map":   storeDataMap,
	})
	if err != nil {
		return nil, err
	}
	return &FinalizeUploadResult{
		DataMap:        str(j, "data_map"),
		Address:        str(j, "address"),
		DataMapAddress: str(j, "data_map_address"),
		ChunksStored:   num64(j, "chunks_stored"),
	}, nil
}
