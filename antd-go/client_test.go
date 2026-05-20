package antd

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// writeJSON serializes v as JSON to the test response writer. Errors are
// ignored because the only realistic failure mode is the client side dropping
// the connection mid-response, which surfaces as the test failing on the
// reading side rather than the writing side.
func writeJSON(w http.ResponseWriter, v any) {
	_ = json.NewEncoder(w).Encode(v)
}

// mockDaemon creates a test server that mimics antd REST responses.
func mockDaemon(t *testing.T) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		switch {
		// Health
		case r.Method == "GET" && r.URL.Path == "/health":
			writeJSON(w, map[string]any{
				"status":                "ok",
				"network":               "local",
				"version":               "0.4.0",
				"evm_network":           "local",
				"uptime_seconds":        42,
				"build_commit":          "abcdef123456",
				"payment_token_address": "0xtoken",
				"payment_vault_address": "0xvault",
			})

		// Data put public
		case r.Method == "POST" && r.URL.Path == "/v1/data/public":
			writeJSON(w, map[string]any{"address": "abc123", "chunks_stored": float64(3), "payment_mode_used": "auto"})

		// Data get public
		case r.Method == "GET" && r.URL.Path == "/v1/data/public/abc123":
			writeJSON(w, map[string]any{"data": base64.StdEncoding.EncodeToString([]byte("hello"))})

		// Data put private (POST /v1/data)
		case r.Method == "POST" && r.URL.Path == "/v1/data":
			writeJSON(w, map[string]any{"data_map": "dm123", "chunks_stored": float64(2), "payment_mode_used": "merkle"})

		// Data get private (POST /v1/data/get)
		case r.Method == "POST" && r.URL.Path == "/v1/data/get":
			writeJSON(w, map[string]any{"data": base64.StdEncoding.EncodeToString([]byte("secret"))})

		// Data cost
		case r.Method == "POST" && r.URL.Path == "/v1/data/cost":
			writeJSON(w, map[string]any{
				"cost":                   "50",
				"file_size":              float64(4),
				"chunk_count":            float64(3),
				"estimated_gas_cost_wei": "150000000000000",
				"payment_mode":           "single",
			})

		// Chunks
		case r.Method == "POST" && r.URL.Path == "/v1/chunks":
			writeJSON(w, map[string]any{"cost": "10", "address": "chunk1"})
		case r.Method == "GET" && r.URL.Path == "/v1/chunks/chunk1":
			writeJSON(w, map[string]any{"data": base64.StdEncoding.EncodeToString([]byte("chunkdata"))})

		// Files
		case r.Method == "POST" && r.URL.Path == "/v1/files":
			writeJSON(w, map[string]any{
				"data_map":          "filedm1",
				"storage_cost_atto": "500",
				"gas_cost_wei":      "21",
				"chunks_stored":     float64(2),
				"payment_mode_used": "single",
			})
		case r.Method == "POST" && r.URL.Path == "/v1/files/get":
			w.WriteHeader(200)
		case r.Method == "POST" && r.URL.Path == "/v1/files/public":
			writeJSON(w, map[string]any{
				"address":           "file1",
				"storage_cost_atto": "1000",
				"gas_cost_wei":      "42",
				"chunks_stored":     float64(3),
				"payment_mode_used": "auto",
			})
		case r.Method == "POST" && r.URL.Path == "/v1/files/public/get":
			w.WriteHeader(200)
		case r.Method == "POST" && r.URL.Path == "/v1/files/cost":
			writeJSON(w, map[string]any{
				"cost":                   "1000",
				"file_size":              float64(4096),
				"chunk_count":            float64(3),
				"estimated_gas_cost_wei": "150000000000000",
				"payment_mode":           "auto",
			})

		// Wallet address
		case r.Method == "GET" && r.URL.Path == "/v1/wallet/address":
			writeJSON(w, map[string]any{"address": "0xabc123"})

		// Wallet balance
		case r.Method == "GET" && r.URL.Path == "/v1/wallet/balance":
			writeJSON(w, map[string]any{"balance": "1000", "gas_balance": "500"})

		// Wallet approve
		case r.Method == "POST" && r.URL.Path == "/v1/wallet/approve":
			writeJSON(w, map[string]any{"approved": true})

		// Prepare upload (file) — wave_batch
		case r.Method == "POST" && r.URL.Path == "/v1/upload/prepare":
			writeJSON(w, map[string]any{
				"upload_id":             "up1",
				"payment_type":          "wave_batch",
				"payments":              []any{map[string]any{"quote_hash": "qh1", "rewards_address": "ra1", "amount": "100"}},
				"total_amount":          "100",
				"payment_vault_address": "dp1",
				"payment_token_address": "pt1",
				"rpc_url":               "http://localhost:8545",
			})

		// Prepare data upload — wave_batch
		case r.Method == "POST" && r.URL.Path == "/v1/data/prepare":
			writeJSON(w, map[string]any{
				"upload_id":             "up2",
				"payment_type":          "wave_batch",
				"payments":              []any{map[string]any{"quote_hash": "qh1", "rewards_address": "ra1", "amount": "100"}},
				"total_amount":          "100",
				"payment_vault_address": "dp1",
				"payment_token_address": "pt1",
				"rpc_url":               "http://localhost:8545",
			})

		// Finalize upload
		case r.Method == "POST" && r.URL.Path == "/v1/upload/finalize":
			writeJSON(w, map[string]any{"address": "fin1", "chunks_stored": float64(3)})

		// 404 for anything else
		default:
			w.WriteHeader(404)
			writeJSON(w, map[string]any{"error": "not found"})
		}
	}))
}

func TestHealth(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	h, err := c.Health(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !h.OK || h.Network != "local" {
		t.Fatalf("unexpected health: %+v", h)
	}
	if h.Version != "0.4.0" || h.EvmNetwork != "local" || h.UptimeSeconds != 42 {
		t.Fatalf("unexpected diagnostic fields: %+v", h)
	}
	if h.BuildCommit != "abcdef123456" || h.PaymentTokenAddress != "0xtoken" || h.PaymentVaultAddress != "0xvault" {
		t.Fatalf("unexpected build/payment fields: %+v", h)
	}
}

func TestDataPublic(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	ctx := context.Background()

	put, err := c.DataPutPublic(ctx, []byte("hello"), PaymentModeAuto)
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "abc123" || put.ChunksStored != 3 || put.PaymentModeUsed != "auto" {
		t.Fatalf("unexpected put: %+v", put)
	}

	data, err := c.DataGetPublic(ctx, "abc123")
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "hello" {
		t.Fatalf("unexpected data: %s", data)
	}
}

func TestDataPrivate(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	ctx := context.Background()

	put, err := c.DataPut(ctx, []byte("secret"), PaymentModeMerkle)
	if err != nil {
		t.Fatal(err)
	}
	if put.DataMap != "dm123" || put.ChunksStored != 2 || put.PaymentModeUsed != "merkle" {
		t.Fatalf("unexpected put: %+v", put)
	}

	data, err := c.DataGet(ctx, "dm123")
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "secret" {
		t.Fatalf("unexpected data: %s", data)
	}
}

func TestDataCost(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	est, err := c.DataCost(context.Background(), []byte("test"), PaymentModeSingle)
	if err != nil {
		t.Fatal(err)
	}
	if est.Cost != "50" || est.FileSize != 4 || est.ChunkCount != 3 ||
		est.EstimatedGasCostWei != "150000000000000" || est.PaymentMode != "single" {
		t.Fatalf("unexpected estimate: %+v", est)
	}
}

func TestFileCost(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	est, err := c.FileCost(context.Background(), "/tmp/file.bin", true, PaymentModeAuto)
	if err != nil {
		t.Fatal(err)
	}
	if est.Cost != "1000" || est.FileSize != 4096 || est.ChunkCount != 3 ||
		est.PaymentMode != "auto" {
		t.Fatalf("unexpected estimate: %+v", est)
	}
}

func TestChunks(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	ctx := context.Background()

	put, err := c.ChunkPut(ctx, []byte("chunkdata"))
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "chunk1" {
		t.Fatalf("unexpected chunk put: %+v", put)
	}

	data, err := c.ChunkGet(ctx, "chunk1")
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "chunkdata" {
		t.Fatalf("unexpected chunk data: %s", data)
	}
}

func TestFiles(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	ctx := context.Background()

	put, err := c.FilePutPublic(ctx, "/tmp/test.txt", PaymentModeAuto)
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "file1" || put.StorageCostAtto != "1000" || put.GasCostWei != "42" || put.ChunksStored != 3 || put.PaymentModeUsed != "auto" {
		t.Fatalf("unexpected file upload: %+v", put)
	}

	err = c.FileGetPublic(ctx, "file1", "/tmp/out.txt")
	if err != nil {
		t.Fatal(err)
	}

	privPut, err := c.FilePut(ctx, "/tmp/test.txt", PaymentModeSingle)
	if err != nil {
		t.Fatal(err)
	}
	if privPut.DataMap != "filedm1" || privPut.StorageCostAtto != "500" || privPut.ChunksStored != 2 || privPut.PaymentModeUsed != "single" {
		t.Fatalf("unexpected private file upload: %+v", privPut)
	}

	if err := c.FileGet(ctx, "filedm1", "/tmp/out.txt"); err != nil {
		t.Fatal(err)
	}

	est, err := c.FileCost(ctx, "/tmp/test.txt", true, PaymentModeAuto)
	if err != nil {
		t.Fatal(err)
	}
	if est.Cost != "1000" {
		t.Fatalf("unexpected file cost: %+v", est)
	}
}

func TestWalletAddress(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	wa, err := c.WalletAddress(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if wa.Address != "0xabc123" {
		t.Fatalf("unexpected address: %s", wa.Address)
	}
}

func TestWalletBalance(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	wb, err := c.WalletBalance(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if wb.Balance != "1000" || wb.GasBalance != "500" {
		t.Fatalf("unexpected balance: %+v", wb)
	}
}

func TestWalletApprove(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	err := c.WalletApprove(context.Background())
	if err != nil {
		t.Fatal(err)
	}
}

func TestPrepareUpload(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	res, err := c.PrepareUpload(context.Background(), "/tmp/test.txt")
	if err != nil {
		t.Fatal(err)
	}
	if res.UploadID != "up1" {
		t.Fatalf("unexpected upload_id: %s", res.UploadID)
	}
	if res.PaymentType != "wave_batch" {
		t.Fatalf("unexpected payment_type: %s", res.PaymentType)
	}
	if len(res.Payments) != 1 || res.Payments[0].QuoteHash != "qh1" {
		t.Fatalf("unexpected payments: %+v", res.Payments)
	}
	if res.TotalAmount != "100" {
		t.Fatalf("unexpected total_amount: %s", res.TotalAmount)
	}
	if res.PaymentVaultAddress != "dp1" {
		t.Fatalf("unexpected payment_vault_address: %s", res.PaymentVaultAddress)
	}
	if res.PaymentTokenAddress != "pt1" {
		t.Fatalf("unexpected payment_token_address: %s", res.PaymentTokenAddress)
	}
	if res.RPCUrl != "http://localhost:8545" {
		t.Fatalf("unexpected rpc_url: %s", res.RPCUrl)
	}
}

func TestPrepareDataUpload(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	res, err := c.PrepareDataUpload(context.Background(), []byte("testdata"))
	if err != nil {
		t.Fatal(err)
	}
	if res.UploadID != "up2" {
		t.Fatalf("unexpected upload_id: %s", res.UploadID)
	}
	if len(res.Payments) != 1 || res.Payments[0].RewardsAddress != "ra1" {
		t.Fatalf("unexpected payments: %+v", res.Payments)
	}
	if res.TotalAmount != "100" {
		t.Fatalf("unexpected total_amount: %s", res.TotalAmount)
	}
	if res.PaymentVaultAddress != "dp1" {
		t.Fatalf("unexpected payment_vault_address: %s", res.PaymentVaultAddress)
	}
	if res.PaymentTokenAddress != "pt1" {
		t.Fatalf("unexpected payment_token_address: %s", res.PaymentTokenAddress)
	}
	if res.RPCUrl != "http://localhost:8545" {
		t.Fatalf("unexpected rpc_url: %s", res.RPCUrl)
	}
}

func TestFinalizeUpload(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	txHashes := map[string]string{"qh1": "tx1"}
	res, err := c.FinalizeUpload(context.Background(), "up1", txHashes, true)
	if err != nil {
		t.Fatal(err)
	}
	if res.Address != "fin1" {
		t.Fatalf("unexpected address: %s", res.Address)
	}
	if res.ChunksStored != 3 {
		t.Fatalf("unexpected chunks_stored: %d", res.ChunksStored)
	}
}

// TestPaymentModeWiresIntoRequestBody verifies the PaymentMode argument
// reaches the REST `payment_mode` field on every put/cost endpoint. Captures
// the body of each request and asserts the serialized value.
func TestPaymentModeWiresIntoRequestBody(t *testing.T) {
	captured := map[string]string{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		if pm, ok := body["payment_mode"].(string); ok {
			captured[r.URL.Path] = pm
		}
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/v1/data":
			writeJSON(w, map[string]any{"data_map": "dm"})
		case "/v1/data/public":
			writeJSON(w, map[string]any{"address": "addr"})
		case "/v1/data/cost":
			writeJSON(w, map[string]any{})
		case "/v1/files":
			writeJSON(w, map[string]any{"data_map": "fdm"})
		case "/v1/files/public":
			writeJSON(w, map[string]any{"address": "faddr"})
		case "/v1/files/cost":
			writeJSON(w, map[string]any{})
		default:
			w.WriteHeader(404)
		}
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	ctx := context.Background()

	if _, err := c.DataPut(ctx, []byte("x"), PaymentModeMerkle); err != nil {
		t.Fatal(err)
	}
	if _, err := c.DataPutPublic(ctx, []byte("x"), PaymentModeSingle); err != nil {
		t.Fatal(err)
	}
	if _, err := c.DataCost(ctx, []byte("x"), PaymentModeAuto); err != nil {
		t.Fatal(err)
	}
	if _, err := c.FilePut(ctx, "/tmp/x", PaymentModeMerkle); err != nil {
		t.Fatal(err)
	}
	if _, err := c.FilePutPublic(ctx, "/tmp/x", PaymentModeSingle); err != nil {
		t.Fatal(err)
	}
	if _, err := c.FileCost(ctx, "/tmp/x", false, PaymentModeAuto); err != nil {
		t.Fatal(err)
	}

	want := map[string]string{
		"/v1/data":         "merkle",
		"/v1/data/public":  "single",
		"/v1/data/cost":    "auto",
		"/v1/files":        "merkle",
		"/v1/files/public": "single",
		"/v1/files/cost":   "auto",
	}
	for path, expected := range want {
		if got := captured[path]; got != expected {
			t.Errorf("%s: payment_mode = %q, want %q", path, got, expected)
		}
	}
}

func TestErrorMapping(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(404)
		writeJSON(w, map[string]any{"error": "not found"})
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	_, err := c.Health(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	var nf *NotFoundError
	if !errors.As(err, &nf) {
		t.Fatalf("expected NotFoundError, got %T: %v", err, err)
	}
	if nf.StatusCode != 404 {
		t.Fatalf("expected status 404, got %d", nf.StatusCode)
	}
}

// --- Merkle payment tests ---

// mockMerkleDaemon returns a test server that responds with merkle payment type.
func mockMerkleDaemon(t *testing.T) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		switch {
		case r.Method == "POST" && r.URL.Path == "/v1/upload/prepare":
			writeJSON(w, map[string]any{
				"upload_id":    "mup1",
				"payment_type": "merkle",
				"depth":        float64(5),
				"pool_commitments": []any{
					map[string]any{
						"pool_hash": "0xaabbccdd",
						"candidates": []any{
							map[string]any{"rewards_address": "0x1111", "amount": "500"},
							map[string]any{"rewards_address": "0x2222", "amount": "600"},
						},
					},
				},
				"merkle_payment_timestamp": float64(1712150400),
				"payment_vault_address":    "0xmerkle",
				"total_amount":             "0",
				"payment_token_address":    "0xtoken",
				"rpc_url":                  "http://localhost:8545",
			})

		case r.Method == "POST" && r.URL.Path == "/v1/data/prepare":
			writeJSON(w, map[string]any{
				"upload_id":    "mup2",
				"payment_type": "merkle",
				"depth":        float64(3),
				"pool_commitments": []any{
					map[string]any{
						"pool_hash":  "0xeeff",
						"candidates": []any{},
					},
				},
				"merkle_payment_timestamp": float64(1712150500),
				"payment_vault_address":    "0xmerkle2",
				"total_amount":             "0",
				"payment_token_address":    "0xtoken2",
				"rpc_url":                  "http://localhost:8546",
			})

		case r.Method == "POST" && r.URL.Path == "/v1/upload/finalize":
			writeJSON(w, map[string]any{
				"data_map":      "dm_merkle",
				"address":       "addr_merkle",
				"chunks_stored": float64(100),
			})

		default:
			w.WriteHeader(404)
			writeJSON(w, map[string]any{"error": "not found"})
		}
	}))
}

func TestPrepareUploadMerkle(t *testing.T) {
	srv := mockMerkleDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	res, err := c.PrepareUpload(context.Background(), "/tmp/bigfile.bin")
	if err != nil {
		t.Fatal(err)
	}
	if res.UploadID != "mup1" {
		t.Fatalf("unexpected upload_id: %s", res.UploadID)
	}
	if res.PaymentType != "merkle" {
		t.Fatalf("unexpected payment_type: %s", res.PaymentType)
	}
	if res.Depth != 5 {
		t.Fatalf("unexpected depth: %d", res.Depth)
	}
	if res.MerklePaymentTimestamp != 1712150400 {
		t.Fatalf("unexpected timestamp: %d", res.MerklePaymentTimestamp)
	}
	if res.PaymentVaultAddress != "0xmerkle" {
		t.Fatalf("unexpected payment_vault_address: %s", res.PaymentVaultAddress)
	}
	if len(res.PoolCommitments) != 1 {
		t.Fatalf("expected 1 pool commitment, got %d", len(res.PoolCommitments))
	}
	pc := res.PoolCommitments[0]
	if pc.PoolHash != "0xaabbccdd" {
		t.Fatalf("unexpected pool_hash: %s", pc.PoolHash)
	}
	if len(pc.Candidates) != 2 {
		t.Fatalf("expected 2 candidates, got %d", len(pc.Candidates))
	}
	if pc.Candidates[0].RewardsAddress != "0x1111" || pc.Candidates[0].Amount != "500" {
		t.Fatalf("unexpected candidate 0: %+v", pc.Candidates[0])
	}
	if pc.Candidates[1].RewardsAddress != "0x2222" || pc.Candidates[1].Amount != "600" {
		t.Fatalf("unexpected candidate 1: %+v", pc.Candidates[1])
	}
	// Wave-batch fields should be empty
	if len(res.Payments) != 0 {
		t.Fatalf("expected no payments for merkle, got %d", len(res.Payments))
	}
	if res.TotalAmount != "0" {
		t.Fatalf("expected total_amount 0 for merkle, got %s", res.TotalAmount)
	}
}

func TestPrepareDataUploadMerkle(t *testing.T) {
	srv := mockMerkleDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	res, err := c.PrepareDataUpload(context.Background(), []byte("bigdata"))
	if err != nil {
		t.Fatal(err)
	}
	if res.PaymentType != "merkle" {
		t.Fatalf("unexpected payment_type: %s", res.PaymentType)
	}
	if res.Depth != 3 {
		t.Fatalf("unexpected depth: %d", res.Depth)
	}
	if res.PaymentVaultAddress != "0xmerkle2" {
		t.Fatalf("unexpected payment_vault_address: %s", res.PaymentVaultAddress)
	}
}

func TestFinalizeMerkleUpload(t *testing.T) {
	srv := mockMerkleDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	res, err := c.FinalizeMerkleUpload(context.Background(), "mup1", "0xwinnerhash", false)
	if err != nil {
		t.Fatal(err)
	}
	if res.DataMap != "dm_merkle" {
		t.Fatalf("unexpected data_map: %s", res.DataMap)
	}
	if res.ChunksStored != 100 {
		t.Fatalf("unexpected chunks_stored: %d", res.ChunksStored)
	}
}

func TestPrepareUploadBackwardCompat(t *testing.T) {
	// Simulate an older daemon that doesn't send payment_type
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		writeJSON(w, map[string]any{
			"upload_id":             "old1",
			"payments":              []any{map[string]any{"quote_hash": "qh1", "rewards_address": "ra1", "amount": "50"}},
			"total_amount":          "50",
			"payment_vault_address": "dp_old",
			"payment_token_address": "pt_old",
			"rpc_url":               "http://localhost:8545",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	res, err := c.PrepareUpload(context.Background(), "/tmp/test.txt")
	if err != nil {
		t.Fatal(err)
	}
	// Should default to wave_batch when payment_type is missing
	if res.PaymentType != "wave_batch" {
		t.Fatalf("expected wave_batch default, got: %s", res.PaymentType)
	}
	if res.UploadID != "old1" {
		t.Fatalf("unexpected upload_id: %s", res.UploadID)
	}
	if len(res.Payments) != 1 {
		t.Fatalf("expected 1 payment, got %d", len(res.Payments))
	}
}

func TestPrepareUploadPublicSendsVisibility(t *testing.T) {
	var capturedBody map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost && r.URL.Path == "/v1/upload/prepare" {
			_ = json.NewDecoder(r.Body).Decode(&capturedBody)
			w.Header().Set("Content-Type", "application/json")
			writeJSON(w, map[string]any{
				"upload_id":             "up-pub-1",
				"payment_type":          "wave_batch",
				"payments":              []any{map[string]any{"quote_hash": "qh1", "rewards_address": "ra1", "amount": "100"}},
				"total_amount":          "100",
				"payment_vault_address": "dp1",
				"payment_token_address": "pt1",
				"rpc_url":               "http://localhost:8545",
			})
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	res, err := c.PrepareUploadPublic(context.Background(), "/tmp/test.txt")
	if err != nil {
		t.Fatal(err)
	}
	if got, want := capturedBody["visibility"], "public"; got != want {
		t.Fatalf("expected visibility=%q in request body, got %v", want, got)
	}
	if got, want := capturedBody["path"], "/tmp/test.txt"; got != want {
		t.Fatalf("expected path=%q in request body, got %v", want, got)
	}
	if res.UploadID != "up-pub-1" {
		t.Fatalf("unexpected upload_id: %s", res.UploadID)
	}
}

func TestFinalizeUploadSurfacesDataMapAddress(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost && r.URL.Path == "/v1/upload/finalize" {
			w.Header().Set("Content-Type", "application/json")
			writeJSON(w, map[string]any{
				"data_map":         "deadbeef",
				"data_map_address": "cafebabe",
				"chunks_stored":    float64(4),
			})
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	res, err := c.FinalizeUpload(context.Background(), "up1", map[string]string{"qh1": "tx1"}, false)
	if err != nil {
		t.Fatal(err)
	}
	if res.DataMapAddress != "cafebabe" {
		t.Fatalf("expected DataMapAddress=cafebabe, got %q", res.DataMapAddress)
	}
	if res.Address != "" {
		t.Fatalf("expected empty legacy Address, got %q", res.Address)
	}
	if res.DataMap != "deadbeef" {
		t.Fatalf("expected DataMap=deadbeef, got %q", res.DataMap)
	}
	if res.ChunksStored != 4 {
		t.Fatalf("expected ChunksStored=4, got %d", res.ChunksStored)
	}
}

func TestFinalizeUploadOmitsDataMapAddressForPrivate(t *testing.T) {
	// Old daemons (pre-0.6.1) don't return data_map_address; field defaults to "".
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost && r.URL.Path == "/v1/upload/finalize" {
			w.Header().Set("Content-Type", "application/json")
			writeJSON(w, map[string]any{
				"data_map":      "deadbeef",
				"chunks_stored": float64(2),
			})
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	res, err := c.FinalizeUpload(context.Background(), "up1", map[string]string{"qh1": "tx1"}, false)
	if err != nil {
		t.Fatal(err)
	}
	if res.DataMapAddress != "" {
		t.Fatalf("expected empty DataMapAddress for old daemon, got %q", res.DataMapAddress)
	}
	if res.DataMap != "deadbeef" {
		t.Fatalf("expected DataMap=deadbeef, got %q", res.DataMap)
	}
}

// ── Single-chunk external-signer (antd >= 0.7.0) ──

func TestPrepareChunkUploadEncodesPayloadAndParsesResponse(t *testing.T) {
	var capturedBody map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost && r.URL.Path == "/v1/chunks/prepare" {
			_ = json.NewDecoder(r.Body).Decode(&capturedBody)
			w.Header().Set("Content-Type", "application/json")
			writeJSON(w, map[string]any{
				"address":        "aa" + strings.Repeat("00", 31),
				"already_stored": false,
				"upload_id":      "chunk-1",
				"payment_type":   "wave_batch",
				"payments": []any{
					map[string]any{"quote_hash": "qh1", "rewards_address": "ra1", "amount": "100"},
					map[string]any{"quote_hash": "qh2", "rewards_address": "ra2", "amount": "100"},
				},
				"total_amount":          "200",
				"payment_vault_address": "0xvault",
				"payment_token_address": "0xtoken",
				"rpc_url":               "http://localhost:8545",
			})
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	res, err := c.PrepareChunkUpload(context.Background(), []byte("hello"))
	if err != nil {
		t.Fatal(err)
	}

	// Request: bytes must arrive base64-encoded under `data`.
	if got, want := capturedBody["data"], "aGVsbG8="; got != want {
		t.Fatalf("expected base64-encoded data %q, got %v", want, got)
	}

	if res.AlreadyStored {
		t.Fatal("expected AlreadyStored=false")
	}
	if res.UploadID != "chunk-1" {
		t.Fatalf("UploadID = %q, want chunk-1", res.UploadID)
	}
	if res.PaymentType != "wave_batch" {
		t.Fatalf("PaymentType = %q, want wave_batch", res.PaymentType)
	}
	if len(res.Payments) != 2 {
		t.Fatalf("expected 2 payments, got %d", len(res.Payments))
	}
	if res.Payments[0].QuoteHash != "qh1" || res.Payments[1].Amount != "100" {
		t.Fatalf("unexpected payment shape: %+v", res.Payments)
	}
	if res.TotalAmount != "200" {
		t.Fatalf("TotalAmount = %q, want 200", res.TotalAmount)
	}
	if res.PaymentVaultAddress != "0xvault" || res.RPCUrl != "http://localhost:8545" {
		t.Fatalf("EVM config not parsed: %+v", res)
	}
}

func TestPrepareChunkUploadAlreadyStoredOmitsPaymentFields(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost && r.URL.Path == "/v1/chunks/prepare" {
			w.Header().Set("Content-Type", "application/json")
			writeJSON(w, map[string]any{
				"address":        "bb" + strings.Repeat("11", 31),
				"already_stored": true,
				// no upload_id, no payments, no payment_type, etc.
			})
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	res, err := c.PrepareChunkUpload(context.Background(), []byte("already-on-network"))
	if err != nil {
		t.Fatal(err)
	}
	if !res.AlreadyStored {
		t.Fatal("expected AlreadyStored=true")
	}
	if res.Address == "" {
		t.Fatal("Address must still be populated for already-stored chunks")
	}
	if res.UploadID != "" {
		t.Fatalf("UploadID should be empty for already-stored, got %q", res.UploadID)
	}
	if len(res.Payments) != 0 {
		t.Fatalf("Payments should be empty for already-stored, got %d", len(res.Payments))
	}
	if res.TotalAmount != "" || res.PaymentType != "" {
		t.Fatalf("payment fields should be empty: %+v", res)
	}
}

func TestFinalizeChunkUploadReturnsAddress(t *testing.T) {
	var capturedBody map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost && r.URL.Path == "/v1/chunks/finalize" {
			_ = json.NewDecoder(r.Body).Decode(&capturedBody)
			w.Header().Set("Content-Type", "application/json")
			writeJSON(w, map[string]any{
				"address": "cc" + strings.Repeat("22", 31),
			})
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	addr, err := c.FinalizeChunkUpload(context.Background(), "chunk-1", map[string]string{
		"qh1": "tx1",
		"qh2": "tx2",
	})
	if err != nil {
		t.Fatal(err)
	}

	if capturedBody["upload_id"] != "chunk-1" {
		t.Fatalf("upload_id not sent: %v", capturedBody["upload_id"])
	}
	tx, ok := capturedBody["tx_hashes"].(map[string]any)
	if !ok || tx["qh1"] != "tx1" || tx["qh2"] != "tx2" {
		t.Fatalf("tx_hashes not sent correctly: %v", capturedBody["tx_hashes"])
	}
	if addr == "" || len(addr) != 64 {
		t.Fatalf("expected 64-char hex address, got %q", addr)
	}
}
