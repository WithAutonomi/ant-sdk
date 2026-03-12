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

		// Pointers
		case r.Method == "POST" && r.URL.Path == "/v1/pointers":
			json.NewEncoder(w).Encode(map[string]any{"cost": "300", "address": "ptr1"})
		case r.Method == "GET" && r.URL.Path == "/v1/pointers/ptr1":
			json.NewEncoder(w).Encode(map[string]any{
				"address": "ptr1", "owner": "owner1", "counter": float64(1),
				"target": map[string]any{"kind": "chunk", "address": "abc123"},
			})
		case r.Method == "HEAD" && r.URL.Path == "/v1/pointers/ptr1":
			w.WriteHeader(200)
		case r.Method == "HEAD" && r.URL.Path == "/v1/pointers/missing":
			w.WriteHeader(404)
		case r.Method == "PUT" && r.URL.Path == "/v1/pointers/sk1":
			w.WriteHeader(200)
		case r.Method == "POST" && r.URL.Path == "/v1/pointers/cost":
			json.NewEncoder(w).Encode(map[string]any{"cost": "300"})

		// Scratchpads
		case r.Method == "POST" && r.URL.Path == "/v1/scratchpads":
			json.NewEncoder(w).Encode(map[string]any{"cost": "400", "address": "sp1"})
		case r.Method == "GET" && r.URL.Path == "/v1/scratchpads/sp1":
			json.NewEncoder(w).Encode(map[string]any{
				"address": "sp1", "data_encoding": float64(1),
				"data": base64.StdEncoding.EncodeToString([]byte("paddata")), "counter": float64(2),
			})
		case r.Method == "HEAD" && r.URL.Path == "/v1/scratchpads/sp1":
			w.WriteHeader(200)
		case r.Method == "PUT" && r.URL.Path == "/v1/scratchpads/sk1":
			w.WriteHeader(200)
		case r.Method == "POST" && r.URL.Path == "/v1/scratchpads/cost":
			json.NewEncoder(w).Encode(map[string]any{"cost": "400"})

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

		// Registers
		case r.Method == "POST" && r.URL.Path == "/v1/registers":
			json.NewEncoder(w).Encode(map[string]any{"cost": "150", "address": "reg1"})
		case r.Method == "GET" && r.URL.Path == "/v1/registers/reg1":
			json.NewEncoder(w).Encode(map[string]any{"value": "00" + "00000000000000000000000000000000000000000000000000000000000000"})
		case r.Method == "PUT" && r.URL.Path == "/v1/registers/sk1":
			json.NewEncoder(w).Encode(map[string]any{"cost": "0"})
		case r.Method == "POST" && r.URL.Path == "/v1/registers/cost":
			json.NewEncoder(w).Encode(map[string]any{"cost": "150"})

		// Vaults
		case r.Method == "GET" && r.URL.Path == "/v1/vaults":
			json.NewEncoder(w).Encode(map[string]any{
				"data": base64.StdEncoding.EncodeToString([]byte("vaultdata")), "content_type": float64(42),
			})
		case r.Method == "POST" && r.URL.Path == "/v1/vaults":
			json.NewEncoder(w).Encode(map[string]any{"cost": "600"})
		case r.Method == "POST" && r.URL.Path == "/v1/vaults/cost":
			json.NewEncoder(w).Encode(map[string]any{"cost": "600"})

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

func TestPointers(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	ctx := context.Background()

	target := PointerTarget{Kind: "chunk", Address: "abc123"}
	put, err := c.PointerCreate(ctx, "sk1", target)
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "ptr1" {
		t.Fatalf("unexpected pointer create: %+v", put)
	}

	ptr, err := c.PointerGet(ctx, "ptr1")
	if err != nil {
		t.Fatal(err)
	}
	if ptr.Target.Kind != "chunk" || ptr.Counter != 1 {
		t.Fatalf("unexpected pointer: %+v", ptr)
	}

	exists, err := c.PointerExists(ctx, "ptr1")
	if err != nil {
		t.Fatal(err)
	}
	if !exists {
		t.Fatal("expected pointer to exist")
	}

	exists, err = c.PointerExists(ctx, "missing")
	if err != nil {
		t.Fatal(err)
	}
	if exists {
		t.Fatal("expected pointer to not exist")
	}

	err = c.PointerUpdate(ctx, "sk1", PointerTarget{Kind: "chunk", Address: "def456"})
	if err != nil {
		t.Fatal(err)
	}
}

func TestScratchpads(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	ctx := context.Background()

	put, err := c.ScratchpadCreate(ctx, "sk1", 1, []byte("paddata"))
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "sp1" {
		t.Fatalf("unexpected scratchpad create: %+v", put)
	}

	sp, err := c.ScratchpadGet(ctx, "sp1")
	if err != nil {
		t.Fatal(err)
	}
	if string(sp.Data) != "paddata" || sp.Counter != 2 {
		t.Fatalf("unexpected scratchpad: %+v", sp)
	}

	exists, err := c.ScratchpadExists(ctx, "sp1")
	if err != nil {
		t.Fatal(err)
	}
	if !exists {
		t.Fatal("expected scratchpad to exist")
	}

	err = c.ScratchpadUpdate(ctx, "sk1", 1, []byte("newdata"))
	if err != nil {
		t.Fatal(err)
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

func TestRegisters(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	ctx := context.Background()

	put, err := c.RegisterCreate(ctx, "sk1", "0000000000000000000000000000000000000000000000000000000000000000")
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "reg1" {
		t.Fatalf("unexpected register create: %+v", put)
	}

	reg, err := c.RegisterGet(ctx, "reg1")
	if err != nil {
		t.Fatal(err)
	}
	if reg.Value == "" {
		t.Fatal("expected register value")
	}

	_, err = c.RegisterUpdate(ctx, "sk1", "ff00000000000000000000000000000000000000000000000000000000000000")
	if err != nil {
		t.Fatal(err)
	}
}

func TestVaults(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	ctx := context.Background()

	v, err := c.VaultGet(ctx, "sk1")
	if err != nil {
		t.Fatal(err)
	}
	if string(v.Data) != "vaultdata" || v.ContentType != 42 {
		t.Fatalf("unexpected vault: %+v", v)
	}

	cost, err := c.VaultPut(ctx, "sk1", []byte("newdata"), 42)
	if err != nil {
		t.Fatal(err)
	}
	if cost != "600" {
		t.Fatalf("unexpected vault put cost: %s", cost)
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
