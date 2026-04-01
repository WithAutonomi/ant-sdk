package antd

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
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

func (c *Client) doHead(ctx context.Context, path string) (int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, c.url(path), nil)
	if err != nil {
		return 0, fmt.Errorf("create request: %w", err)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return 0, fmt.Errorf("http request: %w", err)
	}
	resp.Body.Close()
	return resp.StatusCode, nil
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

func strSlice(m map[string]any, key string) []string {
	arr, ok := m[key].([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(arr))
	for _, v := range arr {
		if s, ok := v.(string); ok {
			out = append(out, s)
		}
	}
	return out
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
		OK:      str(j, "status") == "ok",
		Network: str(j, "network"),
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

// DataPutPublic stores public immutable data on the network.
func (c *Client) DataPutPublic(ctx context.Context, data []byte, paymentMode ...PaymentMode) (*PutResult, error) {
	body := map[string]any{
		"data": b64Encode(data),
	}
	if len(paymentMode) > 0 && paymentMode[0] != "" {
		body["payment_mode"] = string(paymentMode[0])
	}
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/data/public", body)
	if err != nil {
		return nil, err
	}
	return &PutResult{Cost: str(j, "cost"), Address: str(j, "address")}, nil
}

// DataGetPublic retrieves public data by address.
func (c *Client) DataGetPublic(ctx context.Context, address string) ([]byte, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/data/public/"+address, nil)
	if err != nil {
		return nil, err
	}
	return b64Decode(str(j, "data"))
}

// DataPutPrivate stores private encrypted data on the network.
func (c *Client) DataPutPrivate(ctx context.Context, data []byte, paymentMode ...PaymentMode) (*PutResult, error) {
	body := map[string]any{
		"data": b64Encode(data),
	}
	if len(paymentMode) > 0 && paymentMode[0] != "" {
		body["payment_mode"] = string(paymentMode[0])
	}
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/data/private", body)
	if err != nil {
		return nil, err
	}
	return &PutResult{Cost: str(j, "cost"), Address: str(j, "data_map")}, nil
}

// DataGetPrivate retrieves private data using a data map.
func (c *Client) DataGetPrivate(ctx context.Context, dataMap string) ([]byte, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/data/private?data_map="+url.QueryEscape(dataMap), nil)
	if err != nil {
		return nil, err
	}
	return b64Decode(str(j, "data"))
}

// DataCost estimates the cost of storing data.
func (c *Client) DataCost(ctx context.Context, data []byte) (string, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/data/cost", map[string]any{
		"data": b64Encode(data),
	})
	if err != nil {
		return "", err
	}
	return str(j, "cost"), nil
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

// --- Files ---

// FileUploadPublic uploads a local file to the network.
func (c *Client) FileUploadPublic(ctx context.Context, path string, paymentMode ...PaymentMode) (*PutResult, error) {
	body := map[string]any{
		"path": path,
	}
	if len(paymentMode) > 0 && paymentMode[0] != "" {
		body["payment_mode"] = string(paymentMode[0])
	}
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/files/upload/public", body)
	if err != nil {
		return nil, err
	}
	return &PutResult{Cost: str(j, "cost"), Address: str(j, "address")}, nil
}

// FileDownloadPublic downloads a file from the network to a local path.
func (c *Client) FileDownloadPublic(ctx context.Context, address, destPath string) error {
	_, _, err := c.doJSON(ctx, http.MethodPost, "/v1/files/download/public", map[string]any{
		"address":   address,
		"dest_path": destPath,
	})
	return err
}

// DirUploadPublic uploads a local directory to the network.
func (c *Client) DirUploadPublic(ctx context.Context, path string, paymentMode ...PaymentMode) (*PutResult, error) {
	body := map[string]any{
		"path": path,
	}
	if len(paymentMode) > 0 && paymentMode[0] != "" {
		body["payment_mode"] = string(paymentMode[0])
	}
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/dirs/upload/public", body)
	if err != nil {
		return nil, err
	}
	return &PutResult{Cost: str(j, "cost"), Address: str(j, "address")}, nil
}

// DirDownloadPublic downloads a directory from the network to a local path.
func (c *Client) DirDownloadPublic(ctx context.Context, address, destPath string) error {
	_, _, err := c.doJSON(ctx, http.MethodPost, "/v1/dirs/download/public", map[string]any{
		"address":   address,
		"dest_path": destPath,
	})
	return err
}

// FileCost estimates the cost of uploading a file.
func (c *Client) FileCost(ctx context.Context, path string, isPublic bool) (string, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/cost/file", map[string]any{
		"path":      path,
		"is_public": isPublic,
	})
	if err != nil {
		return "", err
	}
	return str(j, "cost"), nil
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

// PrepareUpload prepares a file upload for external signing.
// Returns payment details that an external signer must process before calling FinalizeUpload.
func (c *Client) PrepareUpload(ctx context.Context, path string) (*PrepareUploadResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/upload/prepare", map[string]any{
		"path": path,
	})
	if err != nil {
		return nil, err
	}
	var payments []PaymentInfo
	for _, p := range arrAt(j, "payments") {
		if pm, ok := p.(map[string]any); ok {
			payments = append(payments, PaymentInfo{
				QuoteHash:      str(pm, "quote_hash"),
				RewardsAddress: str(pm, "rewards_address"),
				Amount:         str(pm, "amount"),
			})
		}
	}
	return &PrepareUploadResult{
		UploadID:            str(j, "upload_id"),
		Payments:            payments,
		TotalAmount:         str(j, "total_amount"),
		DataPaymentsAddress: str(j, "data_payments_address"),
		PaymentTokenAddress: str(j, "payment_token_address"),
		RPCUrl:              str(j, "rpc_url"),
	}, nil
}

// PrepareDataUpload prepares a data upload for external signing.
// Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
// Returns payment details that an external signer must process before calling FinalizeUpload.
func (c *Client) PrepareDataUpload(ctx context.Context, data []byte) (*PrepareUploadResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/data/prepare", map[string]any{
		"data": b64Encode(data),
	})
	if err != nil {
		return nil, err
	}
	var payments []PaymentInfo
	for _, p := range arrAt(j, "payments") {
		if pm, ok := p.(map[string]any); ok {
			payments = append(payments, PaymentInfo{
				QuoteHash:      str(pm, "quote_hash"),
				RewardsAddress: str(pm, "rewards_address"),
				Amount:         str(pm, "amount"),
			})
		}
	}
	return &PrepareUploadResult{
		UploadID:            str(j, "upload_id"),
		Payments:            payments,
		TotalAmount:         str(j, "total_amount"),
		DataPaymentsAddress: str(j, "data_payments_address"),
		PaymentTokenAddress: str(j, "payment_token_address"),
		RPCUrl:              str(j, "rpc_url"),
	}, nil
}

// FinalizeUpload finalizes an upload after an external signer has submitted payment transactions.
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
		DataMap:      str(j, "data_map"),
		Address:      str(j, "address"),
		ChunksStored: num64(j, "chunks_stored"),
	}, nil
}
