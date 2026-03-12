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
const DefaultBaseURL = "http://localhost:8080"

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

func num(m map[string]any, key string) int {
	if v, ok := m[key].(float64); ok {
		return int(v)
	}
	return 0
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

func mapAt(m map[string]any, key string) map[string]any {
	if v, ok := m[key].(map[string]any); ok {
		return v
	}
	return nil
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

// --- Data ---

// DataPutPublic stores public immutable data on the network.
func (c *Client) DataPutPublic(ctx context.Context, data []byte) (*PutResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/data/public", map[string]any{
		"data": b64Encode(data),
	})
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
func (c *Client) DataPutPrivate(ctx context.Context, data []byte) (*PutResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/data/private", map[string]any{
		"data": b64Encode(data),
	})
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

// --- Pointers ---

// PointerCreate creates a new mutable pointer.
func (c *Client) PointerCreate(ctx context.Context, ownerSecretKey string, target PointerTarget) (*PutResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/pointers", map[string]any{
		"owner_secret_key": ownerSecretKey,
		"target":           map[string]any{"kind": target.Kind, "address": target.Address},
	})
	if err != nil {
		return nil, err
	}
	return &PutResult{Cost: str(j, "cost"), Address: str(j, "address")}, nil
}

// PointerGet retrieves a pointer by address.
func (c *Client) PointerGet(ctx context.Context, address string) (*Pointer, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/pointers/"+address, nil)
	if err != nil {
		return nil, err
	}
	t := mapAt(j, "target")
	return &Pointer{
		Address: str(j, "address"),
		Owner:   str(j, "owner"),
		Counter: num(j, "counter"),
		Target:  PointerTarget{Kind: str(t, "kind"), Address: str(t, "address")},
	}, nil
}

// PointerExists checks if a pointer exists at the given address.
func (c *Client) PointerExists(ctx context.Context, address string) (bool, error) {
	code, err := c.doHead(ctx, "/v1/pointers/"+address)
	if err != nil {
		return false, err
	}
	if code == 404 {
		return false, nil
	}
	if code >= 300 {
		return false, errorForStatus(code, "pointer exists check failed")
	}
	return true, nil
}

// PointerUpdate updates an existing pointer's target.
func (c *Client) PointerUpdate(ctx context.Context, ownerSecretKey string, target PointerTarget) error {
	_, _, err := c.doJSON(ctx, http.MethodPut, "/v1/pointers/"+ownerSecretKey, map[string]any{
		"owner_secret_key": ownerSecretKey,
		"target":           map[string]any{"kind": target.Kind, "address": target.Address},
	})
	return err
}

// PointerCost estimates the cost of creating a pointer.
func (c *Client) PointerCost(ctx context.Context, publicKey string) (string, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/pointers/cost", map[string]any{
		"public_key": publicKey,
	})
	if err != nil {
		return "", err
	}
	return str(j, "cost"), nil
}

// --- Scratchpads ---

// ScratchpadCreate creates a new scratchpad with initial data.
func (c *Client) ScratchpadCreate(ctx context.Context, ownerSecretKey string, contentType int, data []byte) (*PutResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/scratchpads", map[string]any{
		"owner_secret_key": ownerSecretKey,
		"content_type":     contentType,
		"data":             b64Encode(data),
	})
	if err != nil {
		return nil, err
	}
	return &PutResult{Cost: str(j, "cost"), Address: str(j, "address")}, nil
}

// ScratchpadGet retrieves a scratchpad by address.
func (c *Client) ScratchpadGet(ctx context.Context, address string) (*Scratchpad, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/scratchpads/"+address, nil)
	if err != nil {
		return nil, err
	}
	rawData, err := b64Decode(str(j, "data"))
	if err != nil {
		return nil, fmt.Errorf("decode scratchpad data: %w", err)
	}
	return &Scratchpad{
		Address:      str(j, "address"),
		DataEncoding: num(j, "data_encoding"),
		Data:         rawData,
		Counter:      num(j, "counter"),
	}, nil
}

// ScratchpadExists checks if a scratchpad exists at the given address.
func (c *Client) ScratchpadExists(ctx context.Context, address string) (bool, error) {
	code, err := c.doHead(ctx, "/v1/scratchpads/"+address)
	if err != nil {
		return false, err
	}
	if code == 404 {
		return false, nil
	}
	if code >= 300 {
		return false, errorForStatus(code, "scratchpad exists check failed")
	}
	return true, nil
}

// ScratchpadUpdate updates an existing scratchpad.
func (c *Client) ScratchpadUpdate(ctx context.Context, ownerSecretKey string, contentType int, data []byte) error {
	_, _, err := c.doJSON(ctx, http.MethodPut, "/v1/scratchpads/"+ownerSecretKey, map[string]any{
		"owner_secret_key": ownerSecretKey,
		"content_type":     contentType,
		"data":             b64Encode(data),
	})
	return err
}

// ScratchpadCost estimates the cost of creating a scratchpad.
func (c *Client) ScratchpadCost(ctx context.Context, publicKey string) (string, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/scratchpads/cost", map[string]any{
		"public_key": publicKey,
	})
	if err != nil {
		return "", err
	}
	return str(j, "cost"), nil
}

// --- Graph ---

// GraphEntryPut creates a new graph entry (DAG node).
func (c *Client) GraphEntryPut(ctx context.Context, ownerSecretKey string, parents []string, content string, descendants []GraphDescendant) (*PutResult, error) {
	descs := make([]map[string]any, len(descendants))
	for i, d := range descendants {
		descs[i] = map[string]any{"public_key": d.PublicKey, "content": d.Content}
	}
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/graph", map[string]any{
		"owner_secret_key": ownerSecretKey,
		"parents":          parents,
		"content":          content,
		"descendants":      descs,
	})
	if err != nil {
		return nil, err
	}
	return &PutResult{Cost: str(j, "cost"), Address: str(j, "address")}, nil
}

// GraphEntryGet retrieves a graph entry by address.
func (c *Client) GraphEntryGet(ctx context.Context, address string) (*GraphEntry, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/graph/"+address, nil)
	if err != nil {
		return nil, err
	}
	var descs []GraphDescendant
	for _, d := range arrAt(j, "descendants") {
		if dm, ok := d.(map[string]any); ok {
			descs = append(descs, GraphDescendant{PublicKey: str(dm, "public_key"), Content: str(dm, "content")})
		}
	}
	return &GraphEntry{
		Owner:       str(j, "owner"),
		Parents:     strSlice(j, "parents"),
		Content:     str(j, "content"),
		Descendants: descs,
	}, nil
}

// GraphEntryExists checks if a graph entry exists at the given address.
func (c *Client) GraphEntryExists(ctx context.Context, address string) (bool, error) {
	code, err := c.doHead(ctx, "/v1/graph/"+address)
	if err != nil {
		return false, err
	}
	if code == 404 {
		return false, nil
	}
	if code >= 300 {
		return false, errorForStatus(code, "graph entry exists check failed")
	}
	return true, nil
}

// GraphEntryCost estimates the cost of creating a graph entry.
func (c *Client) GraphEntryCost(ctx context.Context, publicKey string) (string, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/graph/cost", map[string]any{
		"public_key": publicKey,
	})
	if err != nil {
		return "", err
	}
	return str(j, "cost"), nil
}

// --- Registers ---

// RegisterCreate creates a new register with an initial value.
func (c *Client) RegisterCreate(ctx context.Context, ownerSecretKey string, initialValue string) (*PutResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/registers", map[string]any{
		"owner_secret_key": ownerSecretKey,
		"initial_value":    initialValue,
	})
	if err != nil {
		return nil, err
	}
	return &PutResult{Cost: str(j, "cost"), Address: str(j, "address")}, nil
}

// RegisterGet retrieves a register by address.
func (c *Client) RegisterGet(ctx context.Context, address string) (*Register, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/registers/"+address, nil)
	if err != nil {
		return nil, err
	}
	return &Register{Value: str(j, "value")}, nil
}

// RegisterUpdate updates an existing register's value.
func (c *Client) RegisterUpdate(ctx context.Context, ownerSecretKey string, newValue string) (*PutResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPut, "/v1/registers/"+ownerSecretKey, map[string]any{
		"owner_secret_key": ownerSecretKey,
		"new_value":        newValue,
	})
	if err != nil {
		return nil, err
	}
	return &PutResult{Cost: str(j, "cost")}, nil
}

// RegisterCost estimates the cost of creating a register.
func (c *Client) RegisterCost(ctx context.Context, publicKey string) (string, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/registers/cost", map[string]any{
		"public_key": publicKey,
	})
	if err != nil {
		return "", err
	}
	return str(j, "cost"), nil
}

// --- Vaults ---

// VaultGet retrieves vault data using a secret key.
func (c *Client) VaultGet(ctx context.Context, secretKey string) (*Vault, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/vaults?secret_key="+url.QueryEscape(secretKey), nil)
	if err != nil {
		return nil, err
	}
	rawData, err := b64Decode(str(j, "data"))
	if err != nil {
		return nil, fmt.Errorf("decode vault data: %w", err)
	}
	return &Vault{Data: rawData, ContentType: num(j, "content_type")}, nil
}

// VaultPut stores data in a vault.
func (c *Client) VaultPut(ctx context.Context, secretKey string, data []byte, contentType int) (string, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/vaults", map[string]any{
		"secret_key":   secretKey,
		"data":         b64Encode(data),
		"content_type": contentType,
	})
	if err != nil {
		return "", err
	}
	return str(j, "cost"), nil
}

// VaultCost estimates the cost of storing vault data.
func (c *Client) VaultCost(ctx context.Context, secretKey string, maxSize int) (string, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/vaults/cost", map[string]any{
		"secret_key": secretKey,
		"max_size":   maxSize,
	})
	if err != nil {
		return "", err
	}
	return str(j, "cost"), nil
}

// --- Files ---

// FileUploadPublic uploads a local file to the network.
func (c *Client) FileUploadPublic(ctx context.Context, path string) (*PutResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/files/upload/public", map[string]any{
		"path": path,
	})
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
func (c *Client) DirUploadPublic(ctx context.Context, path string) (*PutResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/dirs/upload/public", map[string]any{
		"path": path,
	})
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

// ArchiveGetPublic retrieves an archive manifest by address.
func (c *Client) ArchiveGetPublic(ctx context.Context, address string) (*Archive, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/archives/public/"+address, nil)
	if err != nil {
		return nil, err
	}
	var entries []ArchiveEntry
	for _, e := range arrAt(j, "entries") {
		if em, ok := e.(map[string]any); ok {
			entries = append(entries, ArchiveEntry{
				Path:     str(em, "path"),
				Address:  str(em, "address"),
				Created:  num64(em, "created"),
				Modified: num64(em, "modified"),
				Size:     num64(em, "size"),
			})
		}
	}
	return &Archive{Entries: entries}, nil
}

// ArchivePutPublic creates an archive manifest on the network.
func (c *Client) ArchivePutPublic(ctx context.Context, archive Archive) (*PutResult, error) {
	entries := make([]map[string]any, len(archive.Entries))
	for i, e := range archive.Entries {
		entries[i] = map[string]any{
			"path": e.Path, "address": e.Address,
			"created": e.Created, "modified": e.Modified, "size": e.Size,
		}
	}
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/archives/public", map[string]any{
		"entries": entries,
	})
	if err != nil {
		return nil, err
	}
	return &PutResult{Cost: str(j, "cost"), Address: str(j, "address")}, nil
}

// FileCost estimates the cost of uploading a file.
func (c *Client) FileCost(ctx context.Context, path string, isPublic bool, includeArchive bool) (string, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/cost/file", map[string]any{
		"path":            path,
		"is_public":       isPublic,
		"include_archive": includeArchive,
	})
	if err != nil {
		return "", err
	}
	return str(j, "cost"), nil
}
