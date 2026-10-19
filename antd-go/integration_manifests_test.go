package antd

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"
)

// liveManifestFixtures are data the daemon at ANTD_TEST_URL already stores,
// so the live manifest test builds and decodes without paying for anything.
type liveManifestFixtures struct {
	addresses   [2]string // public data addresses (ANTD_TEST_MANIFEST_ADDRESSES)
	sizes       [2]uint64 // their plaintext sizes (ANTD_TEST_MANIFEST_SIZES)
	dataMap     string    // a private upload's hex DataMap (ANTD_TEST_MANIFEST_DATA_MAP)
	dataMapSize uint64    // its plaintext size (ANTD_TEST_MANIFEST_DATA_MAP_SIZE)
	link        string    // optional: a link built from all three (ANTD_TEST_MANIFEST_LINK)
}

// manifestFixtures reads the live manifest fixtures. It skips when
// ANTD_TEST_MANIFEST_ADDRESSES ("addr1,addr2") is unset; once it is set, the
// sizes and the DataMap are required too.
func manifestFixtures(t *testing.T) liveManifestFixtures {
	t.Helper()
	raw := os.Getenv("ANTD_TEST_MANIFEST_ADDRESSES")
	if raw == "" {
		t.Skip("skipping live manifest test: set ANTD_TEST_MANIFEST_ADDRESSES and the other ANTD_TEST_MANIFEST_* fixtures")
	}
	var f liveManifestFixtures
	addrs := strings.Split(raw, ",")
	sizes := strings.Split(os.Getenv("ANTD_TEST_MANIFEST_SIZES"), ",")
	if len(addrs) != 2 || addrs[0] == "" || addrs[1] == "" || len(sizes) != 2 {
		t.Fatal("ANTD_TEST_MANIFEST_ADDRESSES and ANTD_TEST_MANIFEST_SIZES must each hold two comma-separated values")
	}
	for i := range addrs {
		n, err := strconv.ParseUint(sizes[i], 10, 64)
		if err != nil {
			t.Fatalf("ANTD_TEST_MANIFEST_SIZES: %v", err)
		}
		f.addresses[i], f.sizes[i] = addrs[i], n
	}
	f.dataMap = os.Getenv("ANTD_TEST_MANIFEST_DATA_MAP")
	if f.dataMap == "" {
		t.Fatal("ANTD_TEST_MANIFEST_DATA_MAP is required with ANTD_TEST_MANIFEST_ADDRESSES")
	}
	n, err := strconv.ParseUint(os.Getenv("ANTD_TEST_MANIFEST_DATA_MAP_SIZE"), 10, 64)
	if err != nil {
		t.Fatalf("ANTD_TEST_MANIFEST_DATA_MAP_SIZE: %v", err)
	}
	f.dataMapSize = n
	f.link = os.Getenv("ANTD_TEST_MANIFEST_LINK")
	return f
}

// manifestAPI is the manifest surface both clients share.
type manifestAPI interface {
	BuildManifest(ctx context.Context, entries []ManifestEntryInput, opts *BuildManifestOptions) (*BuiltManifest, error)
	DecodeManifest(ctx context.Context, manifest []byte, resolve bool) (*DecodedManifest, error)
	DecodeManifestLink(ctx context.Context, link string, resolve bool) (*DecodedManifest, error)
}

// The entries' effective names, in encoded order (sorted by effective name).
var liveManifestNames = []string{"private/three.txt", "public/one.txt", "public/two.txt"}

func TestIntegration_Manifests(t *testing.T) {
	f := manifestFixtures(t)
	c := integrationClient(t)
	c.http.Timeout = 2 * time.Minute

	built := checkLiveManifests(t, "REST", c, f)
	checkClientRefusalMatchesDaemon(t, c, f)

	// The same daemon over gRPC, when ANTD_TEST_GRPC is set.
	target := os.Getenv("ANTD_TEST_GRPC")
	if target == "" {
		return
	}
	g, err := NewGrpcClient(target, WithGrpcTimeout(2*time.Minute))
	if err != nil {
		t.Fatalf("NewGrpcClient: %v", err)
	}
	defer g.Close()
	gbuilt := checkLiveManifests(t, "gRPC", g, f)
	if !bytes.Equal(gbuilt.Manifest, built.Manifest) || gbuilt.Link != built.Link {
		t.Fatal("REST and gRPC built different manifests from the same entries")
	}
}

// checkLiveManifests builds a manifest of the fixtures over api, decodes it
// back from its bytes and its link, decodes the fixture link and checks that
// an invalid entry is a bad request. Nothing it calls pays.
func checkLiveManifests(t *testing.T, transport string, api manifestAPI, f liveManifestFixtures) *BuiltManifest {
	t.Helper()
	ctx := context.Background()

	// One size recorded, two left unset: unset must read back as nil.
	built, err := api.BuildManifest(ctx, []ManifestEntryInput{
		{Path: "public/one.txt", Address: f.addresses[0], Size: &f.sizes[0]},
		{Path: "public/two.txt", Address: f.addresses[1]},
		{Path: "private/three.txt", DataMap: f.dataMap},
	}, &BuildManifestOptions{Name: "go-live"})
	if err != nil {
		t.Fatalf("%s BuildManifest: %v", transport, err)
	}
	if !bytes.HasPrefix(built.Manifest, manifestHeader) {
		t.Fatalf("%s BuildManifest: not .ant bytes: %x", transport, built.Manifest)
	}
	if !strings.HasPrefix(built.Link, "ant://manifest/") {
		t.Fatalf("%s BuildManifest: expected a link, got %q", transport, built.Link)
	}
	checkLiveEntries(t, transport+" BuildManifest", built.Entries)
	priv, one, two := built.Entries[0], built.Entries[1], built.Entries[2]
	if priv.Kind != "embedded" || len(priv.ContentAddress) != 64 || priv.DataMap != "" {
		t.Fatalf("%s BuildManifest: unexpected embedded entry: %+v", transport, priv)
	}
	if priv.ExactSize == nil || *priv.ExactSize != f.dataMapSize {
		t.Fatalf("%s BuildManifest: an embedded root knows its exact size: %+v", transport, priv)
	}
	if one.Kind != "public" || one.ContentAddress != f.addresses[0] || one.Size == nil || *one.Size != f.sizes[0] || one.ExactSize != nil {
		t.Fatalf("%s BuildManifest: unexpected first public entry: %+v", transport, one)
	}
	if two.Kind != "public" || two.ContentAddress != f.addresses[1] || two.Size != nil || two.ExactSize != nil {
		t.Fatalf("%s BuildManifest: unexpected second public entry: %+v", transport, two)
	}

	// Decode the bytes and the link, resolving exact sizes from the network.
	fromBytes, err := api.DecodeManifest(ctx, built.Manifest, true)
	if err != nil {
		t.Fatalf("%s DecodeManifest: %v", transport, err)
	}
	checkLiveDecoded(t, transport+" DecodeManifest", fromBytes, built, f)
	fromLink, err := api.DecodeManifestLink(ctx, built.Link, true)
	if err != nil {
		t.Fatalf("%s DecodeManifestLink: %v", transport, err)
	}
	checkLiveDecoded(t, transport+" DecodeManifestLink", fromLink, built, f)

	// Without resolve, a public entry's exact size is unknown.
	plain, err := api.DecodeManifestLink(ctx, built.Link, false)
	if err != nil {
		t.Fatalf("%s DecodeManifestLink (no resolve): %v", transport, err)
	}
	if len(plain.Entries) != 3 || plain.Entries[1].ExactSize != nil || plain.Entries[2].ExactSize != nil {
		t.Fatalf("%s DecodeManifestLink (no resolve): public entries must have no exact size: %+v", transport, plain.Entries)
	}

	// The fixture link lists the same three files.
	if f.link != "" {
		fixture, err := api.DecodeManifestLink(ctx, f.link, true)
		if err != nil {
			t.Fatalf("%s DecodeManifestLink (fixture): %v", transport, err)
		}
		if fixture.Source != "manifest" || len(fixture.Entries) != 3 {
			t.Fatalf("%s DecodeManifestLink (fixture): unexpected manifest: %+v", transport, fixture)
		}
		want := map[string]uint64{
			priv.ContentAddress: f.dataMapSize,
			f.addresses[0]:      f.sizes[0],
			f.addresses[1]:      f.sizes[1],
		}
		for _, e := range fixture.Entries {
			size, ok := want[e.ContentAddress]
			if !ok || e.Error != "" || e.ExactSize == nil || *e.ExactSize != size {
				t.Fatalf("%s DecodeManifestLink (fixture): unexpected entry: %+v", transport, e)
			}
			delete(want, e.ContentAddress)
		}
	}

	// An invalid entry is a bad request that names it.
	_, err = api.BuildManifest(ctx, []ManifestEntryInput{
		{Path: "ok.txt", Address: f.addresses[0]},
		{Path: "../x", Address: f.addresses[1]},
	}, nil)
	var bad *BadRequestError
	if !errors.As(err, &bad) || !strings.Contains(bad.Message, "entries[1]") {
		t.Fatalf("%s BuildManifest with path ../x: expected a BadRequestError naming entries[1], got %T %v", transport, err, err)
	}
	t.Logf("%s: built a %d-byte manifest (%d-byte link), decoded it with exact sizes, fixture link checked: %v", transport, len(built.Manifest), len(built.Link), f.link != "")
	return built
}

func checkLiveEntries(t *testing.T, call string, entries []ManifestEntryInfo) {
	t.Helper()
	if len(entries) != len(liveManifestNames) {
		t.Fatalf("%s: expected %d entries, got %+v", call, len(liveManifestNames), entries)
	}
	for i, e := range entries {
		if e.EffectiveName != liveManifestNames[i] || e.Path != liveManifestNames[i] {
			t.Fatalf("%s: entry %d is %q (path %q), want %q", call, i, e.EffectiveName, e.Path, liveManifestNames[i])
		}
	}
}

func checkLiveDecoded(t *testing.T, call string, d *DecodedManifest, built *BuiltManifest, f liveManifestFixtures) {
	t.Helper()
	if d.Source != "manifest" || d.Name != "go-live" || d.TorrentInfoHashV1 != "" || d.TorrentInfoHashV2 != "" {
		t.Fatalf("%s: unexpected header: %+v", call, d)
	}
	checkLiveEntries(t, call, d.Entries)
	exact := []uint64{f.dataMapSize, f.sizes[0], f.sizes[1]}
	for i, e := range d.Entries {
		b := built.Entries[i]
		if e.Error != "" || e.ExactSize == nil || *e.ExactSize != exact[i] {
			t.Fatalf("%s: %s should resolve to %d bytes, got %s (error %q)", call, e.EffectiveName, exact[i], sizeString(e.ExactSize), e.Error)
		}
		sameSize := (e.Size == nil) == (b.Size == nil) && (e.Size == nil || *e.Size == *b.Size)
		if e.Kind != b.Kind || e.ContentAddress != b.ContentAddress || !sameSize {
			t.Fatalf("%s: %s differs from the built entry: %+v vs %+v", call, e.EffectiveName, e, b)
		}
	}
	if d.Entries[0].DataMap == "" || d.Entries[1].DataMap != "" || d.Entries[2].DataMap != "" {
		t.Fatalf("%s: only the embedded entry carries a DataMap: %+v", call, d.Entries)
	}
}

func sizeString(size *uint64) string {
	if size == nil {
		return "none"
	}
	return strconv.FormatUint(*size, 10)
}

// checkClientRefusalMatchesDaemon sends the daemon the same invalid entries
// the client refuses before sending, and checks that the client's message is
// the daemon's (which adds only its "Bad request: " prefix).
func checkClientRefusalMatchesDaemon(t *testing.T, c *Client, f liveManifestFixtures) {
	t.Helper()
	ctx := context.Background()
	_, err := c.BuildManifest(ctx, []ManifestEntryInput{
		{Address: f.addresses[0], DataMap: f.dataMap},
		{Address: f.addresses[1]},
		{},
	}, nil)
	var bad *BadRequestError
	if !errors.As(err, &bad) || bad.StatusCode != http.StatusBadRequest {
		t.Fatalf("client refusal: expected a 400 *BadRequestError, got %T %v", err, err)
	}
	body, err := json.Marshal(map[string]any{"entries": []map[string]any{
		{"address": f.addresses[0], "data_map": f.dataMap},
		{"address": f.addresses[1]},
		{},
	}})
	if err != nil {
		t.Fatal(err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/v1/manifests/build", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var wire struct{ Error string }
	if err := json.NewDecoder(resp.Body).Decode(&wire); err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusBadRequest || strings.TrimPrefix(wire.Error, "Bad request: ") != bad.Message {
		t.Fatalf("daemon said %d %q, client said %q", resp.StatusCode, wire.Error, bad.Message)
	}
}
