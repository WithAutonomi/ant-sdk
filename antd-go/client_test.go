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
			json.NewEncoder(w).Encode(map[string]any{"cost": "1000", "address": "file1"})
		case r.Method == "POST" && r.URL.Path == "/v1/files/download/public":
			w.WriteHeader(200)
		case r.Method == "POST" && r.URL.Path == "/v1/dirs/upload/public":
			json.NewEncoder(w).Encode(map[string]any{"cost": "2000", "address": "dir1"})
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

		// Prepare upload (file)
		case r.Method == "POST" && r.URL.Path == "/v1/upload/prepare":
			json.NewEncoder(w).Encode(map[string]any{
				"upload_id":              "up1",
				"payments":              []any{map[string]any{"quote_hash": "qh1", "rewards_address": "ra1", "amount": "100"}},
				"total_amount":          "100",
				"data_payments_address": "dp1",
				"payment_token_address": "pt1",
				"rpc_url":              "http://localhost:8545",
			})

		// Prepare data upload
		case r.Method == "POST" && r.URL.Path == "/v1/data/prepare":
			json.NewEncoder(w).Encode(map[string]any{
				"upload_id":              "up2",
				"payments":              []any{map[string]any{"quote_hash": "qh1", "rewards_address": "ra1", "amount": "100"}},
				"total_amount":          "100",
				"data_payments_address": "dp1",
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
	if put.Address != "file1" {
		t.Fatalf("unexpected file upload: %+v", put)
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
	if len(res.Payments) != 1 || res.Payments[0].QuoteHash != "qh1" {
		t.Fatalf("unexpected payments: %+v", res.Payments)
	}
	if res.TotalAmount != "100" {
		t.Fatalf("unexpected total_amount: %s", res.TotalAmount)
	}
	if res.DataPaymentsAddress != "dp1" {
		t.Fatalf("unexpected data_payments_address: %s", res.DataPaymentsAddress)
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
	if res.DataPaymentsAddress != "dp1" {
		t.Fatalf("unexpected data_payments_address: %s", res.DataPaymentsAddress)
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
