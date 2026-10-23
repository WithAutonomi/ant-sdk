package antd

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	pb "github.com/WithAutonomi/ant-sdk/antd-go/proto/antd/v1"
)

// manifestHeader is the five-byte `.ant` header; "wUFOVAE=" is its base64.
var manifestHeader = []byte{0xC1, 'A', 'N', 'T', 0x01}

func u64(v uint64) *uint64 { return &v }

func TestBuildManifest(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/manifests/build" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if body["name"] != "album" || body["embed_roots"] != false {
			t.Fatalf("unexpected options: %+v", body)
		}
		entries := body["entries"].([]any)
		first := entries[0].(map[string]any)
		second := entries[1].(map[string]any)
		if first["path"] != "a.txt" || first["data_map"] != "abcd" || first["size"] != float64(10) {
			t.Fatalf("unexpected first entry: %+v", first)
		}
		if _, ok := first["address"]; ok {
			t.Fatalf("embedded entry must not send an address: %+v", first)
		}
		if second["address"] != "11" || second["path"] != nil || second["size"] != nil {
			t.Fatalf("unexpected second entry: %+v", second)
		}
		_, _ = io.WriteString(w, `{
			"manifest": "wUFOVAE=",
			"link": "ant://manifest/wUFOVAE",
			"entries": [
				{"effective_name": "a.txt", "path": "a.txt", "size": 10, "kind": "embedded",
				 "content_address": "cc", "exact_size": 10},
				{"effective_name": "11", "kind": "public", "content_address": "11"}
			]
		}`)
	}))
	defer srv.Close()

	res, err := NewClient(srv.URL).BuildManifest(context.Background(), []ManifestEntryInput{
		{Path: "a.txt", Size: u64(10), DataMap: "abcd"},
		{Address: "11"},
	}, &BuildManifestOptions{Name: "album", KeepShrunkDataMaps: true})
	if err != nil {
		t.Fatal(err)
	}
	if string(res.Manifest) != string(manifestHeader) || res.Link != "ant://manifest/wUFOVAE" {
		t.Fatalf("unexpected manifest/link: %q %q", res.Manifest, res.Link)
	}
	if len(res.Entries) != 2 {
		t.Fatalf("unexpected entries: %+v", res.Entries)
	}
	a, p := res.Entries[0], res.Entries[1]
	if a.Kind != "embedded" || *a.Size != 10 || *a.ExactSize != 10 || a.ContentAddress != "cc" {
		t.Fatalf("unexpected embedded entry: %+v", a)
	}
	if p.Kind != "public" || p.Size != nil || p.ExactSize != nil || p.Path != "" || p.EffectiveName != "11" {
		t.Fatalf("unexpected public entry: %+v", p)
	}
}

func TestRestFilePutReportsSha256(t *testing.T) {
	srv := mockDaemon(t)
	defer srv.Close()
	c := NewClient(srv.URL)
	put, err := c.FilePut(context.Background(), "/tmp/f", PaymentModeAuto)
	if err != nil {
		t.Fatal(err)
	}
	pub, err := c.FilePutPublic(context.Background(), "/tmp/f", PaymentModeAuto)
	if err != nil {
		t.Fatal(err)
	}
	if put.Sha256 != "a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6" || pub.Sha256 != "a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6" {
		t.Fatalf("sha256 did not come through: %q %q", put.Sha256, pub.Sha256)
	}
}

func TestManifestSha256GoesOutAndComesBack(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		switch r.URL.Path {
		case "/v1/manifests/build":
			entries := body["entries"].([]any)
			if entries[0].(map[string]any)["sha256"] != "a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6" {
				t.Fatalf("sha256 not sent: %+v", entries[0])
			}
			if _, ok := entries[1].(map[string]any)["sha256"]; ok {
				t.Fatalf("empty sha256 must be omitted: %+v", entries[1])
			}
			_, _ = io.WriteString(w, `{"manifest": "wUFOVAE=", "entries": [
				{"effective_name": "a", "path": "a", "kind": "public", "content_address": "11", "sha256": "a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6"}]}`)
		case "/v1/manifests/decode":
			_, _ = io.WriteString(w, `{"source": "manifest", "entries": [
				{"effective_name": "a", "path": "a", "kind": "public", "content_address": "11", "sha256": "a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6"},
				{"effective_name": "b", "path": "b", "kind": "public", "content_address": "22"}]}`)
		}
	}))
	defer srv.Close()
	c := NewClient(srv.URL)
	b, err := c.BuildManifest(context.Background(), []ManifestEntryInput{
		{Path: "a", Address: "11", Sha256: "a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6"},
		{Path: "b", Address: "22"},
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if b.Entries[0].Sha256 != "a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6" {
		t.Fatalf("build entry sha256: %+v", b.Entries[0])
	}
	d, err := c.DecodeManifest(context.Background(), manifestHeader, false)
	if err != nil {
		t.Fatal(err)
	}
	if d.Entries[0].Sha256 != "a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6" || d.Entries[1].Sha256 != "" {
		t.Fatalf("decode sha256: %+v", d.Entries)
	}
}

func TestBuildManifestDefaultsEmbedRoots(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		if body["embed_roots"] != true {
			t.Fatalf("embed_roots should default to true: %+v", body)
		}
		if _, ok := body["name"]; ok {
			t.Fatalf("empty name must be omitted: %+v", body)
		}
		_, _ = io.WriteString(w, `{"manifest": "", "entries": []}`)
	}))
	defer srv.Close()
	if _, err := NewClient(srv.URL).BuildManifest(context.Background(), []ManifestEntryInput{{Address: "11"}}, nil); err != nil {
		t.Fatal(err)
	}
}

func TestBuildManifestRejectsAmbiguousEntriesBeforeSending(t *testing.T) {
	c := NewClient("http://127.0.0.1:1") // never dialled
	ok := ManifestEntryInput{Address: "11"}
	cases := []struct {
		name    string
		entries []ManifestEntryInput
		want    string
	}{
		{"neither", []ManifestEntryInput{{}}, "1 invalid entries: entries[0]: needs a data_map or an address"},
		{"both", []ManifestEntryInput{{DataMap: "aa", Address: "bb"}}, "1 invalid entries: entries[0]: give data_map or address, not both"},
		{"two bad around a good one", []ManifestEntryInput{{DataMap: "aa", Address: "bb"}, ok, {}},
			"2 invalid entries: entries[0]: give data_map or address, not both; entries[2]: needs a data_map or an address"},
	}
	for _, tc := range cases {
		_, err := c.BuildManifest(context.Background(), tc.entries, nil)
		checkBadRequest(t, tc.name, err, tc.want)
	}
}

func checkBadRequest(t *testing.T, name string, err error, want string) {
	t.Helper()
	var bad *BadRequestError
	if !errors.As(err, &bad) || bad.StatusCode != http.StatusBadRequest || bad.Message != want {
		t.Errorf("%s: want *BadRequestError 400 %q, got %T: %v", name, want, err, err)
	}
}

// Past 20 bad entries the daemon names the first 20 and counts the rest.
func TestBuildManifestCapsReportedEntryErrors(t *testing.T) {
	entries := make([]ManifestEntryInput, 23) // all neither
	_, err := NewClient("http://127.0.0.1:1").BuildManifest(context.Background(), entries, nil)
	var bad *BadRequestError
	if !errors.As(err, &bad) {
		t.Fatalf("got %T: %v", err, err)
	}
	if !strings.HasPrefix(bad.Message, "23 invalid entries: entries[0]: needs a data_map or an address; entries[1]:") ||
		!strings.HasSuffix(bad.Message, "entries[19]: needs a data_map or an address; and 3 more") ||
		strings.Contains(bad.Message, "entries[20]") {
		t.Fatalf("unexpected message: %q", bad.Message)
	}
}

// Pre-send rejections are the same *BadRequestError over REST and gRPC.
func TestManifestClientSideRejectionsAreBadRequestOnBothTransports(t *testing.T) {
	ctx := context.Background()
	rest := NewClient("http://127.0.0.1:1") // never dialled
	grpcc := startMockServer(t)
	const entryMsg = "1 invalid entries: entries[0]: needs a data_map or an address"
	_, err := rest.BuildManifest(ctx, []ManifestEntryInput{{}}, nil)
	checkBadRequest(t, "rest build entry", err, entryMsg)
	_, err = grpcc.BuildManifest(ctx, []ManifestEntryInput{{}}, nil)
	checkBadRequest(t, "grpc build entry", err, entryMsg)
	_, err = rest.DecodeManifest(ctx, nil, false)
	checkBadRequest(t, "rest empty bytes", err, noDecodeInput)
	_, err = grpcc.DecodeManifest(ctx, nil, false)
	checkBadRequest(t, "grpc empty bytes", err, noDecodeInput)
	_, err = rest.DecodeManifestLink(ctx, "", false)
	checkBadRequest(t, "rest empty link", err, noDecodeInput)
	_, err = grpcc.DecodeManifestLink(ctx, "", false)
	checkBadRequest(t, "grpc empty link", err, noDecodeInput)
}

func TestDecodeManifestAndLink(t *testing.T) {
	var got []map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/manifests/decode" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		got = append(got, body)
		_, _ = io.WriteString(w, `{
			"source": "manifest", "name": "album", "torrent_info_hash_v2": "bb",
			"entries": [
				{"effective_name": "a.txt", "path": "a.txt", "kind": "embedded",
				 "content_address": "cc", "data_map": "abcd", "exact_size": 3},
				{"effective_name": "b", "path": "b", "kind": "public", "content_address": "dd",
				 "error": "Record not found: gone"}
			]
		}`)
	}))
	defer srv.Close()
	c := NewClient(srv.URL)

	res, err := c.DecodeManifest(context.Background(), manifestHeader, true)
	if err != nil {
		t.Fatal(err)
	}
	if got[0]["manifest"] != "wUFOVAE=" || got[0]["resolve"] != true {
		t.Fatalf("unexpected request: %+v", got[0])
	}
	if res.Source != "manifest" || res.Name != "album" || res.TorrentInfoHashV2 != "bb" || res.TorrentInfoHashV1 != "" {
		t.Fatalf("unexpected header fields: %+v", res)
	}
	if res.Entries[0].DataMap != "abcd" || *res.Entries[0].ExactSize != 3 {
		t.Fatalf("unexpected embedded entry: %+v", res.Entries[0])
	}
	if res.Entries[1].Error == "" || res.Entries[1].ExactSize != nil {
		t.Fatalf("unexpected failed entry: %+v", res.Entries[1])
	}

	if _, err := c.DecodeManifestLink(context.Background(), "ant://manifest/wUFOVAE", false); err != nil {
		t.Fatal(err)
	}
	if got[1]["link"] != "ant://manifest/wUFOVAE" || got[1]["resolve"] != false {
		t.Fatalf("unexpected link request: %+v", got[1])
	}
	if _, ok := got[1]["manifest"]; ok {
		t.Fatalf("link request must not send manifest bytes: %+v", got[1])
	}
}

func TestDecodeManifestKeepsExactSizesAbove2To53(t *testing.T) {
	// 2^53+1 and MaxUint64 both round when decoded through a float64.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.WriteString(w, `{"source": "manifest", "entries": [
			{"effective_name": "a", "kind": "public", "content_address": "aa",
			 "size": 9007199254740993, "exact_size": 18446744073709551615},
			{"effective_name": "b", "kind": "public", "content_address": "bb", "size": 0}
		]}`)
	}))
	defer srv.Close()

	res, err := NewClient(srv.URL).DecodeManifest(context.Background(), manifestHeader, false)
	if err != nil {
		t.Fatal(err)
	}
	a, b := res.Entries[0], res.Entries[1]
	if a.Size == nil || *a.Size != 9007199254740993 {
		t.Fatalf("size: got %v, want 9007199254740993", a.Size)
	}
	if a.ExactSize == nil || *a.ExactSize != math.MaxUint64 {
		t.Fatalf("exact_size: got %v, want MaxUint64", a.ExactSize)
	}
	if b.Size == nil || *b.Size != 0 || b.ExactSize != nil {
		t.Fatalf("a present zero must stay distinct from absent: %+v", b)
	}
}

func TestDecodeManifestBadRequestIsTyped(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = io.WriteString(w, `{"error": "Bad request: not a manifest: missing or invalid header", "code": "BAD_REQUEST"}`)
	}))
	defer srv.Close()
	_, err := NewClient(srv.URL).DecodeManifest(context.Background(), []byte("nope"), false)
	var bad *BadRequestError
	if !errors.As(err, &bad) {
		t.Fatalf("expected *BadRequestError, got %T: %v", err, err)
	}
}

// mockManifestService implements pb.ManifestServiceServer.
type mockManifestService struct {
	pb.UnimplementedManifestServiceServer
}

// bigManifestSize is past the client's default receive ceiling, so only a
// raised per-call limit lets a manifest this large arrive.
const bigManifestSize = DefaultGrpcMaxRecvMsgSize + 1024*1024

func (m *mockManifestService) Build(_ context.Context, req *pb.BuildManifestRequest) (*pb.BuildManifestResponse, error) {
	if req.GetName() == "big" {
		return &pb.BuildManifestResponse{Manifest: make([]byte, bigManifestSize)}, nil
	}
	if req.GetName() != "album" || req.EmbedRoots == nil || !req.GetEmbedRoots() || len(req.GetEntries()) != 2 {
		return nil, errors.New("unexpected request")
	}
	first, second := req.GetEntries()[0], req.GetEntries()[1]
	if first.GetPath() != "a.txt" || first.GetDataMap() != "abcd" || first.Size == nil || first.GetSize() != 10 {
		return nil, errors.New("unexpected first entry")
	}
	if second.Path != nil || second.GetAddress() != "11" || second.Size != nil || second.Sha256 != nil {
		return nil, errors.New("unexpected second entry")
	}
	ten := uint64(10)
	path := "a.txt"
	return &pb.BuildManifestResponse{
		Manifest: manifestHeader,
		Link:     "ant://manifest/wUFOVAE",
		Entries: []*pb.ManifestEntryInfo{
			{EffectiveName: "a.txt", Path: &path, Size: &ten, Kind: "embedded", ContentAddress: "cc", ExactSize: &ten, Sha256: first.GetSha256()},
			{EffectiveName: "11", Kind: "public", ContentAddress: "11"},
		},
	}, nil
}

func (m *mockManifestService) Decode(_ context.Context, req *pb.DecodeManifestRequest) (*pb.DecodeManifestResponse, error) {
	resp := &pb.DecodeManifestResponse{Source: "manifest"}
	if req.GetLink() == "big" {
		resp.Entries = []*pb.ManifestEntryInfo{{Kind: "embedded", DataMap: strings.Repeat("a", bigManifestSize)}}
		return resp, nil
	}
	switch in := req.GetInput().(type) {
	case *pb.DecodeManifestRequest_Manifest:
		name := "bytes"
		resp.Name = &name
	case *pb.DecodeManifestRequest_Link:
		resp.Source = "file_link"
		resp.Entries = []*pb.ManifestEntryInfo{{EffectiveName: in.Link, Kind: "public", ContentAddress: in.Link}}
	default:
		return nil, errors.New("no input")
	}
	if req.GetResolve() {
		resp.TorrentInfoHashV1 = "resolved"
	}
	return resp, nil
}

func TestGrpcBuildManifest(t *testing.T) {
	c := startMockServer(t)
	res, err := c.BuildManifest(context.Background(), []ManifestEntryInput{
		{Path: "a.txt", Size: u64(10), DataMap: "abcd", Sha256: "a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6"},
		{Address: "11"},
	}, &BuildManifestOptions{Name: "album"})
	if err != nil {
		t.Fatal(err)
	}
	if res.Entries[0].Sha256 != "a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6" || res.Entries[1].Sha256 != "" {
		t.Fatalf("sha256 did not round-trip over gRPC: %+v", res.Entries)
	}
	if string(res.Manifest) != string(manifestHeader) || res.Link == "" || len(res.Entries) != 2 {
		t.Fatalf("unexpected result: %+v", res)
	}
	if *res.Entries[0].Size != 10 || res.Entries[0].Path != "a.txt" || res.Entries[1].Size != nil {
		t.Fatalf("unexpected entries: %+v", res.Entries)
	}
}

func TestGrpcDecodeManifestAndLink(t *testing.T) {
	c := startMockServer(t)
	res, err := c.DecodeManifest(context.Background(), manifestHeader, true)
	if err != nil {
		t.Fatal(err)
	}
	if res.Name != "bytes" || res.TorrentInfoHashV1 != "resolved" {
		t.Fatalf("unexpected bytes decode: %+v", res)
	}
	addr := "42424242424242424242424242424242424242424242424242424242424242aa"
	res, err = c.DecodeManifestLink(context.Background(), addr, false)
	if err != nil {
		t.Fatal(err)
	}
	if res.Source != "file_link" || len(res.Entries) != 1 || res.Entries[0].ContentAddress != addr || res.TorrentInfoHashV1 != "" {
		t.Fatalf("unexpected link decode: %+v", res)
	}
}

// A manifest response past the client's default receive ceiling must still
// arrive: Build and Decode raise the limit per call (maxManifestGrpcMessage),
// since a manifest can be 64 MiB and a decode carries its DataMaps in hex.
func TestGrpcManifestCallsRaiseTheRecvLimit(t *testing.T) {
	if bigManifestSize <= DefaultGrpcMaxRecvMsgSize || bigManifestSize > maxManifestGrpcMessage {
		t.Fatalf("fixture must sit between the default and the manifest ceilings, got %d bytes", bigManifestSize)
	}
	c := startMockServer(t)

	built, err := c.BuildManifest(context.Background(), []ManifestEntryInput{{Address: "11"}}, &BuildManifestOptions{Name: "big"})
	if err != nil {
		t.Fatalf("large Build response rejected on a default client: %v", err)
	}
	if len(built.Manifest) != bigManifestSize {
		t.Fatalf("expected %d manifest bytes, got %d", bigManifestSize, len(built.Manifest))
	}

	decoded, err := c.DecodeManifestLink(context.Background(), "big", false)
	if err != nil {
		t.Fatalf("large Decode response rejected on a default client: %v", err)
	}
	if len(decoded.Entries) != 1 || len(decoded.Entries[0].DataMap) != bigManifestSize {
		t.Fatalf("large Decode response mangled: %d entries", len(decoded.Entries))
	}
}
