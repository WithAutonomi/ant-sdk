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

		// Graph
		case r.Method == "POST" && r.URL.Path == "/v1/graph":
			json.NewEncoder(w).Encode(map[string]any{"cost": "500", "address": "ge1"})
		case r.Method == "GET" && r.URL.Path == "/v1/graph/ge1":
			json.NewEncoder(w).Encode(map[string]any{
				"owner": "owner1", "parents": []any{}, "content": "abc",
				"descendants": []any{map[string]any{"public_key": "pk1", "content": "desc1"}},
			})
		case r.Method == "HEAD" && r.URL.Path == "/v1/graph/ge1":
			w.WriteHeader(200)
		case r.Method == "POST" && r.URL.Path == "/v1/graph/cost":
			json.NewEncoder(w).Encode(map[string]any{"cost": "500"})

		// Files
		case r.Method == "POST" && r.URL.Path == "/v1/files/upload/public":
			json.NewEncoder(w).Encode(map[string]any{"cost": "1000", "address": "file1"})
		case r.Method == "POST" && r.URL.Path == "/v1/files/download/public":
			w.WriteHeader(200)
		case r.Method == "POST" && r.URL.Path == "/v1/dirs/upload/public":
			json.NewEncoder(w).Encode(map[string]any{"cost": "2000", "address": "dir1"})
		case r.Method == "POST" && r.URL.Path == "/v1/dirs/download/public":
			w.WriteHeader(200)
		case r.Method == "GET" && r.URL.Path == "/v1/archives/public/arc1":
			json.NewEncoder(w).Encode(map[string]any{
				"entries": []any{map[string]any{
					"path": "test.txt", "address": "abc", "created": float64(1000), "modified": float64(2000), "size": float64(42),
				}},
			})
		case r.Method == "POST" && r.URL.Path == "/v1/archives/public":
			json.NewEncoder(w).Encode(map[string]any{"cost": "50", "address": "arc2"})
		case r.Method == "POST" && r.URL.Path == "/v1/cost/file":
			json.NewEncoder(w).Encode(map[string]any{"cost": "1000"})

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

func TestGraph(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	ctx := context.Background()

	put, err := c.GraphEntryPut(ctx, "sk1", []string{}, "abc", []GraphDescendant{})
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "ge1" {
		t.Fatalf("unexpected graph put: %+v", put)
	}

	ge, err := c.GraphEntryGet(ctx, "ge1")
	if err != nil {
		t.Fatal(err)
	}
	if ge.Owner != "owner1" || len(ge.Descendants) != 1 {
		t.Fatalf("unexpected graph entry: %+v", ge)
	}

	exists, err := c.GraphEntryExists(ctx, "ge1")
	if err != nil {
		t.Fatal(err)
	}
	if !exists {
		t.Fatal("expected graph entry to exist")
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

	arc, err := c.ArchiveGetPublic(ctx, "arc1")
	if err != nil {
		t.Fatal(err)
	}
	if len(arc.Entries) != 1 || arc.Entries[0].Path != "test.txt" {
		t.Fatalf("unexpected archive: %+v", arc)
	}

	arcPut, err := c.ArchivePutPublic(ctx, *arc)
	if err != nil {
		t.Fatal(err)
	}
	if arcPut.Address != "arc2" {
		t.Fatalf("unexpected archive put: %+v", arcPut)
	}

	cost, err := c.FileCost(ctx, "/tmp/test.txt", true, false)
	if err != nil {
		t.Fatal(err)
	}
	if cost != "1000" {
		t.Fatalf("unexpected file cost: %s", cost)
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
