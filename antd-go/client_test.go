package antd

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

// mockDaemon creates a test server that mimics antd REST responses.
func mockDaemon(t *testing.T) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		switch {
		// Health
		case r.Method == "GET" && r.URL.Path == "/health":
			json.NewEncoder(w).Encode(map[string]any{"status": "ok", "network": "local"})

		// Data put public
		case r.Method == "POST" && r.URL.Path == "/v1/data/public":
			json.NewEncoder(w).Encode(map[string]any{"cost": "100", "address": "abc123"})

		// Data get public
		case r.Method == "GET" && r.URL.Path == "/v1/data/public/abc123":
			json.NewEncoder(w).Encode(map[string]any{"data": base64.StdEncoding.EncodeToString([]byte("hello"))})

		// Data put private
		case r.Method == "POST" && r.URL.Path == "/v1/data/private":
			json.NewEncoder(w).Encode(map[string]any{"cost": "200", "data_map": "dm123"})

		// Data get private
		case r.Method == "GET" && r.URL.Path == "/v1/data/private":
			json.NewEncoder(w).Encode(map[string]any{"data": base64.StdEncoding.EncodeToString([]byte("secret"))})

		// Data cost
		case r.Method == "POST" && r.URL.Path == "/v1/data/cost":
			json.NewEncoder(w).Encode(map[string]any{"cost": "50"})

		// Chunks
		case r.Method == "POST" && r.URL.Path == "/v1/chunks":
			json.NewEncoder(w).Encode(map[string]any{"cost": "10", "address": "chunk1"})
		case r.Method == "GET" && r.URL.Path == "/v1/chunks/chunk1":
			json.NewEncoder(w).Encode(map[string]any{"data": base64.StdEncoding.EncodeToString([]byte("chunkdata"))})

		// Files
		case r.Method == "POST" && r.URL.Path == "/v1/files/upload/public":
			json.NewEncoder(w).Encode(map[string]any{
				"address":           "file1",
				"storage_cost_atto": "1000",
				"gas_cost_wei":      "42",
				"chunks_stored":     float64(3),
				"payment_mode_used": "auto",
			})
		case r.Method == "POST" && r.URL.Path == "/v1/files/download/public":
			w.WriteHeader(200)
		case r.Method == "POST" && r.URL.Path == "/v1/dirs/upload/public":
			json.NewEncoder(w).Encode(map[string]any{
				"address":           "dir1",
				"storage_cost_atto": "2000",
				"gas_cost_wei":      "100",
				"chunks_stored":     float64(5),
				"payment_mode_used": "merkle",
			})
		case r.Method == "POST" && r.URL.Path == "/v1/dirs/download/public":
			w.WriteHeader(200)
		case r.Method == "POST" && r.URL.Path == "/v1/cost/file":
			json.NewEncoder(w).Encode(map[string]any{"cost": "1000"})

		// Wallet address
		case r.Method == "GET" && r.URL.Path == "/v1/wallet/address":
			json.NewEncoder(w).Encode(map[string]any{"address": "0xabc123"})

		// Wallet balance
		case r.Method == "GET" && r.URL.Path == "/v1/wallet/balance":
			json.NewEncoder(w).Encode(map[string]any{"balance": "1000", "gas_balance": "500"})

		// Wallet approve
		case r.Method == "POST" && r.URL.Path == "/v1/wallet/approve":
			json.NewEncoder(w).Encode(map[string]any{"approved": true})

		// Prepare upload (file) — wave_batch
		case r.Method == "POST" && r.URL.Path == "/v1/upload/prepare":
			json.NewEncoder(w).Encode(map[string]any{
				"upload_id":              "up1",
				"payment_type":          "wave_batch",
				"payments":              []any{map[string]any{"quote_hash": "qh1", "rewards_address": "ra1", "amount": "100"}},
				"total_amount":          "100",
				"payment_vault_address": "dp1",
				"payment_token_address": "pt1",
				"rpc_url":              "http://localhost:8545",
			})

		// Prepare data upload — wave_batch
		case r.Method == "POST" && r.URL.Path == "/v1/data/prepare":
			json.NewEncoder(w).Encode(map[string]any{
				"upload_id":              "up2",
				"payment_type":          "wave_batch",
				"payments":              []any{map[string]any{"quote_hash": "qh1", "rewards_address": "ra1", "amount": "100"}},
				"total_amount":          "100",
				"payment_vault_address": "dp1",
				"payment_token_address": "pt1",
				"rpc_url":              "http://localhost:8545",
			})

		// Finalize upload
		case r.Method == "POST" && r.URL.Path == "/v1/upload/finalize":
			json.NewEncoder(w).Encode(map[string]any{"address": "fin1", "chunks_stored": float64(3)})

		// 404 for anything else
		default:
			w.WriteHeader(404)
			json.NewEncoder(w).Encode(map[string]any{"error": "not found"})
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
}

func TestDataPublic(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	ctx := context.Background()

	put, err := c.DataPutPublic(ctx, []byte("hello"))
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "abc123" || put.Cost != "100" {
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

	put, err := c.DataPutPrivate(ctx, []byte("secret"))
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "dm123" || put.Cost != "200" {
		t.Fatalf("unexpected put: %+v", put)
	}

	data, err := c.DataGetPrivate(ctx, "dm123")
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
	cost, err := c.DataCost(context.Background(), []byte("test"))
	if err != nil {
		t.Fatal(err)
	}
	if cost != "50" {
		t.Fatalf("unexpected cost: %s", cost)
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

	put, err := c.FileUploadPublic(ctx, "/tmp/test.txt")
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "file1" || put.StorageCostAtto != "1000" || put.GasCostWei != "42" || put.ChunksStored != 3 || put.PaymentModeUsed != "auto" {
		t.Fatalf("unexpected file upload: %+v", put)
	}

	dirRes, err := c.DirUploadPublic(ctx, "/tmp/mydir")
	if err != nil {
		t.Fatal(err)
	}
	if dirRes.Address != "dir1" || dirRes.StorageCostAtto != "2000" || dirRes.GasCostWei != "100" || dirRes.ChunksStored != 5 || dirRes.PaymentModeUsed != "merkle" {
		t.Fatalf("unexpected dir upload: %+v", dirRes)
	}

	err = c.FileDownloadPublic(ctx, "file1", "/tmp/out.txt")
	if err != nil {
		t.Fatal(err)
	}

	cost, err := c.FileCost(ctx, "/tmp/test.txt", true)
	if err != nil {
		t.Fatal(err)
	}
	if cost != "1000" {
		t.Fatalf("unexpected file cost: %s", cost)
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

func TestErrorMapping(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(404)
		json.NewEncoder(w).Encode(map[string]any{"error": "not found"})
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
			json.NewEncoder(w).Encode(map[string]any{
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
			json.NewEncoder(w).Encode(map[string]any{
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
			json.NewEncoder(w).Encode(map[string]any{
				"data_map":      "dm_merkle",
				"address":       "addr_merkle",
				"chunks_stored": float64(100),
			})

		default:
			w.WriteHeader(404)
			json.NewEncoder(w).Encode(map[string]any{"error": "not found"})
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
		json.NewEncoder(w).Encode(map[string]any{
			"upload_id":              "old1",
			"payments":              []any{map[string]any{"quote_hash": "qh1", "rewards_address": "ra1", "amount": "50"}},
			"total_amount":          "50",
			"payment_vault_address": "dp_old",
			"payment_token_address": "pt_old",
			"rpc_url":              "http://localhost:8545",
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
