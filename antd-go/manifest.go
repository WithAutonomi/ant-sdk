package antd

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"google.golang.org/grpc"

	pb "github.com/WithAutonomi/ant-sdk/antd-go/proto/antd/v1"
)

// Manifests (ADR-0006): `.ant` files and `ant://` links that describe a set
// of files, each with an optional path and size and either an embedded
// DataMap or a public DataMap address. The daemon builds and decodes them
// through ant-core, so callers never re-implement the format. Nothing is
// uploaded or paid for.

// ManifestEntryInput is one file for BuildManifest. Set exactly one of
// DataMap or Address.
type ManifestEntryInput struct {
	// Path is the relative path the entry extracts under, subject to the
	// portable path rules. Empty: it extracts under its content address.
	Path string
	// Size is the plaintext size to record, as given (the creator's claim).
	// Nil: none is recorded; readers take the exact size from an embedded
	// root DataMap.
	Size *uint64
	// DataMap is a hex DataMap, as the upload methods return it. The entry
	// embeds it: the manifest is the key to the file.
	DataMap string
	// Address is a public file's DataMap address (hex, 32 bytes).
	Address string
}

// BuildManifestOptions are the optional parts of a BuildManifest call.
type BuildManifestOptions struct {
	// Name is a suggested root directory name (one portable path component).
	Name string
	// TorrentInfoHashes are BitTorrent info hashes of the same files: hex,
	// 40 characters for v1 and/or 64 for v2.
	TorrentInfoHashes []string
	// KeepShrunkDataMaps embeds shrunk DataMaps exactly as given. By default
	// the daemon resolves each one's root (fetching its wrapper records) and
	// embeds the root when it is at most 64 KiB, so recipients skip that
	// fetch (ADR-0006's policy).
	KeepShrunkDataMaps bool
}

// ManifestEntryInfo is what a manifest says about one entry.
type ManifestEntryInfo struct {
	// EffectiveName is Path, or the content address in hex when there is none.
	EffectiveName string
	Path          string
	// Size is the size recorded in the manifest: the creator's claim.
	Size *uint64
	// Kind is "embedded" or "public".
	Kind string
	// ContentAddress (hex) is the file's public DataMap address, whether or
	// not it was ever made public; the same for private and public uploads
	// of one file.
	ContentAddress string
	// DataMap is the embedded DataMap in the hex form the download methods
	// accept. Decode only; empty for public entries.
	DataMap string
	// ExactSize is the exact plaintext size: from an embedded root DataMap,
	// or after a resolving decode.
	ExactSize *uint64
	// Error says why a resolving decode failed for this entry.
	Error string
}

// BuiltManifest is the result of BuildManifest.
type BuiltManifest struct {
	// Manifest is the `.ant` bytes.
	Manifest []byte
	// Link is the `ant://manifest/` link, set only when it fits the
	// recommended 1,500 bytes.
	Link string
	// Entries are in encoded order (sorted by effective name).
	Entries []ManifestEntryInfo
}

// DecodedManifest is the result of DecodeManifest and DecodeManifestLink.
type DecodedManifest struct {
	// Source is "manifest", or "file_link" for a file link or bare address
	// (reported as one public entry with no path).
	Source            string
	Name              string
	TorrentInfoHashV1 string
	TorrentInfoHashV2 string
	Entries           []ManifestEntryInfo
}

// maxManifestGrpcMessage is the receive ceiling for manifest calls: a
// manifest can be 64 MiB, and a decode response carries its DataMaps in hex.
const maxManifestGrpcMessage = 256 * 1024 * 1024

func checkManifestEntries(entries []ManifestEntryInput) error {
	for i, e := range entries {
		if (e.DataMap == "") == (e.Address == "") {
			return fmt.Errorf("antd: manifest entry %d: set exactly one of DataMap or Address", i)
		}
	}
	return nil
}

// --- REST ---

// BuildManifest builds a `.ant` manifest from DataMaps and public addresses
// already in hand, via POST /v1/manifests/build. opts may be nil.
//
// Requires the antd release after 0.15.0.
func (c *Client) BuildManifest(ctx context.Context, entries []ManifestEntryInput, opts *BuildManifestOptions) (*BuiltManifest, error) {
	if err := checkManifestEntries(entries); err != nil {
		return nil, err
	}
	if opts == nil {
		opts = &BuildManifestOptions{}
	}
	wire := make([]map[string]any, 0, len(entries))
	for _, e := range entries {
		m := map[string]any{}
		if e.Path != "" {
			m["path"] = e.Path
		}
		if e.Size != nil {
			m["size"] = *e.Size
		}
		if e.DataMap != "" {
			m["data_map"] = e.DataMap
		} else {
			m["address"] = e.Address
		}
		wire = append(wire, m)
	}
	body := map[string]any{
		"entries":     wire,
		"embed_roots": !opts.KeepShrunkDataMaps,
	}
	if opts.Name != "" {
		body["name"] = opts.Name
	}
	if len(opts.TorrentInfoHashes) > 0 {
		body["torrent_info_hashes"] = opts.TorrentInfoHashes
	}
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/manifests/build", body)
	if err != nil {
		return nil, err
	}
	raw, err := b64Decode(str(j, "manifest"))
	if err != nil {
		return nil, fmt.Errorf("antd: BuildManifest: manifest is not valid base64: %w", err)
	}
	return &BuiltManifest{
		Manifest: raw,
		Link:     str(j, "link"),
		Entries:  parseManifestEntries(arrAt(j, "entries")),
	}, nil
}

// DecodeManifest decodes `.ant` bytes via POST /v1/manifests/decode. With
// resolve, the daemon fetches each entry's DataMap (and wrapper records) to
// report ExactSize and confirm the DataMap is on the network; content chunks
// are not fetched, and one entry's failure is reported in its Error.
//
// Requires the antd release after 0.15.0.
func (c *Client) DecodeManifest(ctx context.Context, manifest []byte, resolve bool) (*DecodedManifest, error) {
	if len(manifest) == 0 {
		return nil, errors.New("antd: DecodeManifest: manifest is empty")
	}
	return c.decodeManifest(ctx, map[string]any{"manifest": b64Encode(manifest), "resolve": resolve})
}

// DecodeManifestLink decodes an `ant://` manifest link, file link or bare
// 64-hex address via POST /v1/manifests/decode. See DecodeManifest for
// resolve.
//
// Requires the antd release after 0.15.0.
func (c *Client) DecodeManifestLink(ctx context.Context, link string, resolve bool) (*DecodedManifest, error) {
	if link == "" {
		return nil, errors.New("antd: DecodeManifestLink: link is empty")
	}
	return c.decodeManifest(ctx, map[string]any{"link": link, "resolve": resolve})
}

func (c *Client) decodeManifest(ctx context.Context, body map[string]any) (*DecodedManifest, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/manifests/decode", body)
	if err != nil {
		return nil, err
	}
	return &DecodedManifest{
		Source:            str(j, "source"),
		Name:              str(j, "name"),
		TorrentInfoHashV1: str(j, "torrent_info_hash_v1"),
		TorrentInfoHashV2: str(j, "torrent_info_hash_v2"),
		Entries:           parseManifestEntries(arrAt(j, "entries")),
	}, nil
}

func optUint64(m map[string]any, key string) *uint64 {
	if _, ok := m[key].(float64); !ok {
		return nil
	}
	v := unum64(m, key)
	return &v
}

func parseManifestEntries(raw []any) []ManifestEntryInfo {
	out := make([]ManifestEntryInfo, 0, len(raw))
	for _, e := range raw {
		m, ok := e.(map[string]any)
		if !ok {
			continue
		}
		out = append(out, ManifestEntryInfo{
			EffectiveName:  str(m, "effective_name"),
			Path:           str(m, "path"),
			Size:           optUint64(m, "size"),
			Kind:           str(m, "kind"),
			ContentAddress: str(m, "content_address"),
			DataMap:        str(m, "data_map"),
			ExactSize:      optUint64(m, "exact_size"),
			Error:          str(m, "error"),
		})
	}
	return out
}

// --- gRPC ---

// BuildManifest is the gRPC twin of Client.BuildManifest. opts may be nil.
//
// Requires the antd release after 0.15.0.
func (c *GrpcClient) BuildManifest(ctx context.Context, entries []ManifestEntryInput, opts *BuildManifestOptions) (*BuiltManifest, error) {
	if err := checkManifestEntries(entries); err != nil {
		return nil, err
	}
	if opts == nil {
		opts = &BuildManifestOptions{}
	}
	embedRoots := !opts.KeepShrunkDataMaps
	req := &pb.BuildManifestRequest{
		TorrentInfoHashes: opts.TorrentInfoHashes,
		EmbedRoots:        &embedRoots,
	}
	if opts.Name != "" {
		req.Name = &opts.Name
	}
	for _, e := range entries {
		in := &pb.ManifestEntryInput{Size: e.Size}
		if e.Path != "" {
			path := e.Path
			in.Path = &path
		}
		if e.DataMap != "" {
			in.Source = &pb.ManifestEntryInput_DataMap{DataMap: e.DataMap}
		} else {
			in.Source = &pb.ManifestEntryInput_Address{Address: e.Address}
		}
		req.Entries = append(req.Entries, in)
	}

	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.manifest.Build(ctx, req, grpc.MaxCallRecvMsgSize(maxManifestGrpcMessage))
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &BuiltManifest{
		Manifest: resp.GetManifest(),
		Link:     resp.GetLink(),
		Entries:  fromPbManifestEntries(resp.GetEntries()),
	}, nil
}

// DecodeManifest is the gRPC twin of Client.DecodeManifest.
//
// Requires the antd release after 0.15.0.
func (c *GrpcClient) DecodeManifest(ctx context.Context, manifest []byte, resolve bool) (*DecodedManifest, error) {
	if len(manifest) == 0 {
		return nil, errors.New("antd: DecodeManifest: manifest is empty")
	}
	return c.decodeManifest(ctx, &pb.DecodeManifestRequest{
		Input:   &pb.DecodeManifestRequest_Manifest{Manifest: manifest},
		Resolve: resolve,
	})
}

// DecodeManifestLink is the gRPC twin of Client.DecodeManifestLink.
//
// Requires the antd release after 0.15.0.
func (c *GrpcClient) DecodeManifestLink(ctx context.Context, link string, resolve bool) (*DecodedManifest, error) {
	if link == "" {
		return nil, errors.New("antd: DecodeManifestLink: link is empty")
	}
	return c.decodeManifest(ctx, &pb.DecodeManifestRequest{
		Input:   &pb.DecodeManifestRequest_Link{Link: link},
		Resolve: resolve,
	})
}

func (c *GrpcClient) decodeManifest(ctx context.Context, req *pb.DecodeManifestRequest) (*DecodedManifest, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.manifest.Decode(ctx, req, grpc.MaxCallRecvMsgSize(maxManifestGrpcMessage))
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &DecodedManifest{
		Source:            resp.GetSource(),
		Name:              resp.GetName(),
		TorrentInfoHashV1: resp.GetTorrentInfoHashV1(),
		TorrentInfoHashV2: resp.GetTorrentInfoHashV2(),
		Entries:           fromPbManifestEntries(resp.GetEntries()),
	}, nil
}

func fromPbManifestEntries(entries []*pb.ManifestEntryInfo) []ManifestEntryInfo {
	out := make([]ManifestEntryInfo, 0, len(entries))
	for _, e := range entries {
		out = append(out, ManifestEntryInfo{
			EffectiveName:  e.GetEffectiveName(),
			Path:           e.GetPath(),
			Size:           e.Size,
			Kind:           e.GetKind(),
			ContentAddress: e.GetContentAddress(),
			DataMap:        e.GetDataMap(),
			ExactSize:      e.ExactSize,
			Error:          e.GetError(),
		})
	}
	return out
}
