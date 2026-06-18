package antd

import (
	"context"
	"fmt"
	"io"
	"strconv"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"

	pb "github.com/WithAutonomi/ant-sdk/antd-go/proto/antd/v1"
)

// DefaultGrpcTarget is the default address of the antd gRPC server.
const DefaultGrpcTarget = "localhost:50051"

// DefaultGrpcTimeout is the default per-call timeout for gRPC requests.
const DefaultGrpcTimeout = 5 * time.Minute

// GrpcOption configures a GrpcClient.
type GrpcOption func(*GrpcClient)

// WithGrpcTimeout sets the per-call timeout for gRPC requests.
func WithGrpcTimeout(d time.Duration) GrpcOption {
	return func(c *GrpcClient) { c.timeout = d }
}

// WithDialOptions appends gRPC dial options.
func WithDialOptions(opts ...grpc.DialOption) GrpcOption {
	return func(c *GrpcClient) { c.dialOpts = append(c.dialOpts, opts...) }
}

// GrpcClient is a gRPC client for the antd daemon. It exposes the same
// methods as the REST Client, using the same model types and error types.
type GrpcClient struct {
	conn    *grpc.ClientConn
	timeout time.Duration

	dialOpts []grpc.DialOption

	health pb.HealthServiceClient
	data   pb.DataServiceClient
	chunk  pb.ChunkServiceClient
	file   pb.FileServiceClient
	upload pb.UploadServiceClient
	wallet pb.WalletServiceClient
}

// NewGrpcClientAutoDiscover creates a gRPC client that discovers the daemon target
// automatically. It reads the port file written by antd on startup, falling back
// to DefaultGrpcTarget. Returns the client, the resolved target, and any error.
func NewGrpcClientAutoDiscover(opts ...GrpcOption) (*GrpcClient, string, error) {
	target := DiscoverGrpcTarget()
	if target == "" {
		target = DefaultGrpcTarget
	}
	c, err := NewGrpcClient(target, opts...)
	return c, target, err
}

// NewGrpcClient creates a new gRPC client connected to the given target
// (e.g. "localhost:50051"). The connection is established lazily on first use.
func NewGrpcClient(target string, opts ...GrpcOption) (*GrpcClient, error) {
	c := &GrpcClient{
		timeout: DefaultGrpcTimeout,
	}
	for _, o := range opts {
		o(c)
	}

	// Default to insecure transport if no dial options are provided.
	if len(c.dialOpts) == 0 {
		c.dialOpts = append(c.dialOpts, grpc.WithTransportCredentials(insecure.NewCredentials()))
	}

	conn, err := grpc.NewClient(target, c.dialOpts...)
	if err != nil {
		return nil, fmt.Errorf("grpc dial: %w", err)
	}
	c.conn = conn

	c.health = pb.NewHealthServiceClient(conn)
	c.data = pb.NewDataServiceClient(conn)
	c.chunk = pb.NewChunkServiceClient(conn)
	c.file = pb.NewFileServiceClient(conn)
	c.upload = pb.NewUploadServiceClient(conn)
	c.wallet = pb.NewWalletServiceClient(conn)

	return c, nil
}

// Close releases the underlying gRPC connection.
func (c *GrpcClient) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}

// ctx wraps the caller's context with the configured timeout.
func (c *GrpcClient) ctx(parent context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(parent, c.timeout)
}

// --- Error mapping ---

// errorFromGrpc converts a gRPC status error to the corresponding antd error
// type, matching the same typed errors returned by the REST client.
func errorFromGrpc(err error) error {
	if err == nil {
		return nil
	}
	st, ok := status.FromError(err)
	if !ok {
		return err
	}
	msg := st.Message()
	base := AntdError{Message: msg}

	switch st.Code() {
	case codes.InvalidArgument:
		base.StatusCode = 400
		return &BadRequestError{base}
	case codes.FailedPrecondition:
		base.StatusCode = 402
		return &PaymentError{base}
	case codes.NotFound:
		base.StatusCode = 404
		return &NotFoundError{base}
	case codes.AlreadyExists:
		base.StatusCode = 409
		return &AlreadyExistsError{base}
	case codes.ResourceExhausted:
		base.StatusCode = 413
		return &TooLargeError{base}
	case codes.Internal:
		base.StatusCode = 500
		return &InternalError{base}
	case codes.Unavailable:
		base.StatusCode = 502
		return &NetworkError{base}
	default:
		base.StatusCode = int(st.Code())
		return &base
	}
}

// --- Health (1 method) ---

// Health checks the antd daemon status.
func (c *GrpcClient) Health(ctx context.Context) (*HealthStatus, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.health.Check(ctx, &pb.HealthCheckRequest{})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &HealthStatus{
		OK:                  resp.GetStatus() == "ok",
		Network:             resp.GetNetwork(),
		Version:             resp.GetVersion(),
		EvmNetwork:          resp.GetEvmNetwork(),
		UptimeSeconds:       resp.GetUptimeSeconds(),
		BuildCommit:         resp.GetBuildCommit(),
		PaymentTokenAddress: resp.GetPaymentTokenAddress(),
		PaymentVaultAddress: resp.GetPaymentVaultAddress(),
	}, nil
}

// --- Data (5 methods) ---

// DataPut stores private encrypted data on the network and returns the
// caller-held DataMap (hex).
func (c *GrpcClient) DataPut(ctx context.Context, data []byte, paymentMode PaymentMode) (*DataPutResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.data.Put(ctx, &pb.PutDataRequest{
		Data:        data,
		PaymentMode: string(paymentMode),
	})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &DataPutResult{
		DataMap:         resp.GetDataMap(),
		ChunksStored:    resp.GetChunksStored(),
		PaymentModeUsed: resp.GetPaymentModeUsed(),
	}, nil
}

// DataGet retrieves private data from a caller-held DataMap (hex).
func (c *GrpcClient) DataGet(ctx context.Context, dataMap string) ([]byte, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.data.Get(ctx, &pb.GetDataRequest{DataMap: dataMap})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return resp.GetData(), nil
}

// DataPutPublic stores public immutable data on the network and returns the
// on-network DataMap address.
func (c *GrpcClient) DataPutPublic(ctx context.Context, data []byte, paymentMode PaymentMode) (*DataPutPublicResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.data.PutPublic(ctx, &pb.PutPublicDataRequest{
		Data:        data,
		PaymentMode: string(paymentMode),
	})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &DataPutPublicResult{
		Address:         resp.GetAddress(),
		ChunksStored:    resp.GetChunksStored(),
		PaymentModeUsed: resp.GetPaymentModeUsed(),
	}, nil
}

// DataGetPublic retrieves public data by address.
func (c *GrpcClient) DataGetPublic(ctx context.Context, address string) ([]byte, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.data.GetPublic(ctx, &pb.GetPublicDataRequest{Address: address})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return resp.GetData(), nil
}

// dataChunkStream is the minimal view of a server-streaming DataChunk RPC that
// both Stream and StreamPublic satisfy, letting one reader adapter wrap either.
type dataChunkStream interface {
	Recv() (*pb.DataChunk, error)
	Header() (metadata.MD, error)
}

// grpcChunkReader adapts a server-streaming DataChunk RPC into an io.ReadCloser
// so gRPC streaming downloads present the same surface as the REST client's
// DataStream. It pulls one chunk at a time (constant memory) and buffers any
// bytes left over from a chunk that didn't fit the caller's Read buffer.
type grpcChunkReader struct {
	stream dataChunkStream
	cancel context.CancelFunc
	buf    []byte
}

func (r *grpcChunkReader) Read(p []byte) (int, error) {
	for len(r.buf) == 0 {
		chunk, err := r.stream.Recv()
		if err != nil {
			// io.EOF is the clean end-of-stream signal; pass it through
			// verbatim and map everything else onto our error types.
			if err == io.EOF {
				return 0, io.EOF
			}
			return 0, errorFromGrpc(err)
		}
		r.buf = chunk.GetData()
	}
	n := copy(p, r.buf)
	r.buf = r.buf[n:]
	return n, nil
}

// Close cancels the underlying RPC. It is safe to call after the stream has
// already drained; cancelling a finished context is a no-op.
func (r *grpcChunkReader) Close() error {
	r.cancel()
	return nil
}

// DataStream streams private data from a caller-held DataMap (hex) instead of
// buffering it all in memory — the gRPC counterpart to DataGet and the mirror
// of the REST client's DataStream. The caller reads the returned stream and
// MUST Close it (Close cancels the RPC).
func (c *GrpcClient) DataStream(ctx context.Context, dataMap string) (io.ReadCloser, error) {
	// Unlike the buffered calls, the timeout context must live until the
	// caller is done reading, so cancel is handed to Close rather than
	// deferred here.
	ctx, cancel := c.ctx(ctx)
	stream, err := c.data.Stream(ctx, &pb.StreamDataRequest{DataMap: dataMap})
	if err != nil {
		cancel()
		return nil, errorFromGrpc(err)
	}
	return &grpcChunkReader{stream: stream, cancel: cancel}, nil
}

// DataStreamPublic streams public data by address — the gRPC counterpart to
// DataGetPublic and the mirror of the REST client's DataStreamPublic. The
// caller reads the returned stream and MUST Close it.
func (c *GrpcClient) DataStreamPublic(ctx context.Context, address string) (io.ReadCloser, error) {
	ctx, cancel := c.ctx(ctx)
	stream, err := c.data.StreamPublic(ctx, &pb.StreamPublicDataRequest{Address: address})
	if err != nil {
		cancel()
		return nil, errorFromGrpc(err)
	}
	return &grpcChunkReader{stream: stream, cancel: cancel}, nil
}

// DownloadStream is a progress-enabled streaming download: a sequence of
// [DownloadFrame]s, each either a plaintext data chunk or a [DownloadProgress]
// update interleaved on the same RPC. Returned by DataStreamWithProgress /
// DataStreamPublicWithProgress. The caller drains it with Recv until io.EOF and
// MUST Close it (Close cancels the RPC).
//
// Unlike the plain DataStream io.ReadCloser, frames preserve the chunk
// boundaries the server emits — a data frame holds exactly one decrypted chunk.
type DownloadStream struct {
	stream dataChunkStream
	cancel context.CancelFunc
	meta   *uint64 // pending byte-total Meta frame, emitted before any chunk
}

// Recv returns the next frame, or io.EOF when the stream is exhausted. A frame
// whose Meta is non-nil is the byte-total denominator (emitted first); a frame
// whose Progress is non-nil is a progress update; otherwise it carries data
// bytes. A wire frame with no oneof arm set (shouldn't occur) is surfaced as an
// empty data frame, matching the antd-rust reference consumer.
func (s *DownloadStream) Recv() (DownloadFrame, error) {
	if s.meta != nil {
		total := *s.meta
		s.meta = nil
		return DownloadFrame{Meta: &total}, nil
	}
	chunk, err := s.stream.Recv()
	if err != nil {
		if err == io.EOF {
			return DownloadFrame{}, io.EOF
		}
		return DownloadFrame{}, errorFromGrpc(err)
	}
	if p := chunk.GetProgress(); p != nil {
		return DownloadFrame{Progress: &DownloadProgress{
			Phase:   p.GetPhase(),
			Fetched: p.GetFetched(),
			Total:   p.GetTotal(),
		}}, nil
	}
	return DownloadFrame{Data: chunk.GetData()}, nil
}

// Close cancels the underlying RPC. Safe to call after the stream has drained.
func (s *DownloadStream) Close() error {
	s.cancel()
	return nil
}

// metaFromHeader reads the total download size from the stream's
// x-content-length response header (sent before the first chunk) and returns it
// as a pending Meta frame. Header() blocks until the server sends its initial
// metadata. Returns nil when the header is absent or unparseable (older
// daemons), so no Meta frame is emitted.
func metaFromHeader(stream dataChunkStream) *uint64 {
	md, err := stream.Header()
	if err != nil {
		return nil
	}
	vals := md.Get("x-content-length")
	if len(vals) == 0 {
		return nil
	}
	n, err := strconv.ParseUint(vals[0], 10, 64)
	if err != nil {
		return nil
	}
	return &n
}

// DataStreamWithProgress is DataStream with interleaved fetch-progress frames so
// the caller can drive a *determinate* download progress bar. It sets the
// stream request's include_progress flag, then returns a [DownloadStream] whose
// frames are either plaintext chunks or [DownloadProgress] updates. The byte
// denominator arrives separately as the x-content-length response header.
func (c *GrpcClient) DataStreamWithProgress(ctx context.Context, dataMap string) (*DownloadStream, error) {
	ctx, cancel := c.ctx(ctx)
	stream, err := c.data.Stream(ctx, &pb.StreamDataRequest{DataMap: dataMap, IncludeProgress: true})
	if err != nil {
		cancel()
		return nil, errorFromGrpc(err)
	}
	return &DownloadStream{stream: stream, cancel: cancel, meta: metaFromHeader(stream)}, nil
}

// DataStreamPublicWithProgress is DataStreamPublic with interleaved
// fetch-progress frames. See DataStreamWithProgress.
func (c *GrpcClient) DataStreamPublicWithProgress(ctx context.Context, address string) (*DownloadStream, error) {
	ctx, cancel := c.ctx(ctx)
	stream, err := c.data.StreamPublic(ctx, &pb.StreamPublicDataRequest{Address: address, IncludeProgress: true})
	if err != nil {
		cancel()
		return nil, errorFromGrpc(err)
	}
	return &DownloadStream{stream: stream, cancel: cancel, meta: metaFromHeader(stream)}, nil
}

// DataCost returns a pre-upload cost breakdown for the given bytes.
//
// The server samples a small number of chunk addresses and extrapolates —
// much faster than quoting every chunk on slow networks. Gas is advisory.
func (c *GrpcClient) DataCost(ctx context.Context, data []byte, paymentMode PaymentMode) (*UploadCostEstimate, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.data.Cost(ctx, &pb.DataCostRequest{
		Data:        data,
		PaymentMode: string(paymentMode),
	})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &UploadCostEstimate{
		Cost:                resp.GetAttoTokens(),
		FileSize:            resp.GetFileSize(),
		ChunkCount:          resp.GetChunkCount(),
		EstimatedGasCostWei: resp.GetEstimatedGasCostWei(),
		PaymentMode:         resp.GetPaymentMode(),
	}, nil
}

// --- Chunks (2 methods) ---

// ChunkPut stores a raw chunk on the network.
func (c *GrpcClient) ChunkPut(ctx context.Context, data []byte) (*PutResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.chunk.Put(ctx, &pb.PutChunkRequest{Data: data})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &PutResult{
		Cost:    resp.GetCost().GetAttoTokens(),
		Address: resp.GetAddress(),
	}, nil
}

// ChunkGet retrieves a chunk by address.
func (c *GrpcClient) ChunkGet(ctx context.Context, address string) ([]byte, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.chunk.Get(ctx, &pb.GetChunkRequest{Address: address})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return resp.GetData(), nil
}

// --- Files (5 methods) ---

// FilePut uploads a local file as a private upload and returns the caller-held
// DataMap (hex).
func (c *GrpcClient) FilePut(ctx context.Context, path string, paymentMode PaymentMode) (*FilePutResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.file.Put(ctx, &pb.PutFileRequest{
		Path:        path,
		PaymentMode: string(paymentMode),
	})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &FilePutResult{
		DataMap:         resp.GetDataMap(),
		StorageCostAtto: resp.GetStorageCostAtto(),
		GasCostWei:      resp.GetGasCostWei(),
		ChunksStored:    resp.GetChunksStored(),
		PaymentModeUsed: resp.GetPaymentModeUsed(),
	}, nil
}

// FileGet downloads a private file from a caller-held DataMap into destPath.
func (c *GrpcClient) FileGet(ctx context.Context, dataMap, destPath string) error {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	_, err := c.file.Get(ctx, &pb.GetFileRequest{
		DataMap:  dataMap,
		DestPath: destPath,
	})
	return errorFromGrpc(err)
}

// FilePutPublic uploads a local file as a public upload. The DataMap is
// stored on-network as an extra chunk; the returned address is the shareable
// retrieval handle.
func (c *GrpcClient) FilePutPublic(ctx context.Context, path string, paymentMode PaymentMode) (*FilePutPublicResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.file.PutPublic(ctx, &pb.PutFileRequest{
		Path:        path,
		PaymentMode: string(paymentMode),
	})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &FilePutPublicResult{
		Address:         resp.GetAddress(),
		StorageCostAtto: resp.GetStorageCostAtto(),
		GasCostWei:      resp.GetGasCostWei(),
		ChunksStored:    resp.GetChunksStored(),
		PaymentModeUsed: resp.GetPaymentModeUsed(),
	}, nil
}

// FileGetPublic downloads a public file from an on-network DataMap address into destPath.
func (c *GrpcClient) FileGetPublic(ctx context.Context, address, destPath string) error {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	_, err := c.file.GetPublic(ctx, &pb.GetFilePublicRequest{
		Address:  address,
		DestPath: destPath,
	})
	return errorFromGrpc(err)
}

// FileCost returns a pre-upload cost breakdown for the file at path.
//
// The server samples a small number of chunk addresses and extrapolates —
// much faster than quoting every chunk on slow networks. Gas is advisory.
func (c *GrpcClient) FileCost(ctx context.Context, path string, isPublic bool, paymentMode PaymentMode) (*UploadCostEstimate, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.file.Cost(ctx, &pb.FileCostRequest{
		Path:        path,
		IsPublic:    isPublic,
		PaymentMode: string(paymentMode),
	})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &UploadCostEstimate{
		Cost:                resp.GetAttoTokens(),
		FileSize:            resp.GetFileSize(),
		ChunkCount:          resp.GetChunkCount(),
		EstimatedGasCostWei: resp.GetEstimatedGasCostWei(),
		PaymentMode:         resp.GetPaymentMode(),
	}, nil
}

// --- Chunks (external signer, 2 methods) ---

// PrepareChunkUpload prepares a single chunk for external-signer publish.
//
// Mirrors Client.PrepareChunkUpload over gRPC. Either the chunk is already
// on-network (AlreadyStored=true with other fields empty) or returns wave-batch
// payment details for payForQuotes().
//
// Unlike ChunkPut, does NOT require the daemon to have a wallet — funds flow
// through the external signer.
//
// Requires antd >= 0.9.0.
func (c *GrpcClient) PrepareChunkUpload(ctx context.Context, content []byte) (*PrepareChunkResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.chunk.PrepareChunk(ctx, &pb.PrepareChunkRequest{Data: content})
	if err != nil {
		return nil, errorFromGrpc(err)
	}

	r := &PrepareChunkResult{
		Address:             resp.GetAddress(),
		AlreadyStored:       resp.GetAlreadyStored(),
		UploadID:            resp.GetUploadId(),
		PaymentType:         resp.GetPaymentType(),
		TotalAmount:         resp.GetTotalAmount(),
		PaymentVaultAddress: resp.GetPaymentVaultAddress(),
		PaymentTokenAddress: resp.GetPaymentTokenAddress(),
		RPCUrl:              resp.GetRpcUrl(),
	}
	for _, p := range resp.GetPayments() {
		r.Payments = append(r.Payments, PaymentInfo{
			QuoteHash:      p.GetQuoteHash(),
			RewardsAddress: p.GetRewardsAddress(),
			Amount:         p.GetAmount(),
		})
	}
	return r, nil
}

// FinalizeChunkUpload submits a prepared chunk to the network after the
// external signer has paid. Returns the network address of the stored chunk
// (matches PrepareChunkResult.Address).
//
// Requires antd >= 0.9.0.
func (c *GrpcClient) FinalizeChunkUpload(ctx context.Context, uploadID string, txHashes map[string]string) (string, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.chunk.FinalizeChunk(ctx, &pb.FinalizeChunkRequest{
		UploadId: uploadID,
		TxHashes: txHashes,
	})
	if err != nil {
		return "", errorFromGrpc(err)
	}
	return resp.GetAddress(), nil
}

// --- Upload (external signer, 5 methods) ---

// prepareResponseToResult converts a proto PrepareUploadResponse into the
// REST-style PrepareUploadResult, populating the merkle-only fields
// (Depth, PoolCommitments, MerklePaymentTimestamp) only when
// PaymentType == "merkle".
func prepareResponseToResult(resp *pb.PrepareUploadResponse) *PrepareUploadResult {
	result := &PrepareUploadResult{
		UploadID:            resp.GetUploadId(),
		PaymentType:         resp.GetPaymentType(),
		TotalAmount:         resp.GetTotalAmount(),
		PaymentVaultAddress: resp.GetPaymentVaultAddress(),
		PaymentTokenAddress: resp.GetPaymentTokenAddress(),
		RPCUrl:              resp.GetRpcUrl(),
	}
	for _, p := range resp.GetPayments() {
		result.Payments = append(result.Payments, PaymentInfo{
			QuoteHash:      p.GetQuoteHash(),
			RewardsAddress: p.GetRewardsAddress(),
			Amount:         p.GetAmount(),
		})
	}
	if result.PaymentType == "merkle" {
		result.Depth = int(resp.GetDepth())
		result.MerklePaymentTimestamp = resp.GetMerklePaymentTimestamp()
		for _, pc := range resp.GetPoolCommitments() {
			entry := PoolCommitmentEntry{PoolHash: pc.GetPoolHash()}
			for _, cand := range pc.GetCandidates() {
				entry.Candidates = append(entry.Candidates, CandidateNodeEntry{
					RewardsAddress: cand.GetRewardsAddress(),
					Amount:         cand.GetAmount(),
				})
			}
			result.PoolCommitments = append(result.PoolCommitments, entry)
		}
	}
	return result
}

// PrepareUpload prepares a private file upload for external signing.
//
// Mirrors Client.PrepareUpload over gRPC.
//
// Requires antd >= 0.9.0.
func (c *GrpcClient) PrepareUpload(ctx context.Context, path string) (*PrepareUploadResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.upload.PrepareFileUpload(ctx, &pb.PrepareFileUploadRequest{
		Path: path,
	})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return prepareResponseToResult(resp), nil
}

// PrepareUploadPublic prepares a public file upload for external signing.
// The DataMap chunk is bundled into the same external-signer payment batch;
// after FinalizeUpload, FinalizeUploadResult.DataMapAddress is the shareable
// retrieval handle.
//
// Mirrors Client.PrepareUploadPublic over gRPC.
//
// Requires antd >= 0.9.0.
func (c *GrpcClient) PrepareUploadPublic(ctx context.Context, path string) (*PrepareUploadResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.upload.PrepareFileUpload(ctx, &pb.PrepareFileUploadRequest{
		Path:       path,
		Visibility: "public",
	})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return prepareResponseToResult(resp), nil
}

// PrepareDataUpload prepares a private in-memory data upload for external
// signing.
//
// Mirrors Client.PrepareDataUpload over gRPC.
//
// Requires antd >= 0.9.0.
func (c *GrpcClient) PrepareDataUpload(ctx context.Context, data []byte) (*PrepareUploadResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.upload.PrepareDataUpload(ctx, &pb.PrepareDataUploadRequest{
		Data: data,
	})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return prepareResponseToResult(resp), nil
}

// FinalizeUpload finalizes a wave-batch upload after the external signer has
// submitted payForQuotes() transactions. txHashes maps quote_hash to tx_hash
// for each payment.
//
// If storeDataMap is true, the DataMap is also stored on-network via the
// daemon's internal wallet and Address is returned. Prefer
// PrepareUploadPublic + reading DataMapAddress instead.
//
// Mirrors Client.FinalizeUpload over gRPC.
//
// Requires antd >= 0.9.0.
func (c *GrpcClient) FinalizeUpload(ctx context.Context, uploadID string, txHashes map[string]string, storeDataMap bool) (*FinalizeUploadResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.upload.FinalizeUpload(ctx, &pb.FinalizeUploadRequest{
		UploadId:     uploadID,
		TxHashes:     txHashes,
		StoreDataMap: storeDataMap,
	})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &FinalizeUploadResult{
		DataMap:        resp.GetDataMap(),
		Address:        resp.GetAddress(),
		DataMapAddress: resp.GetDataMapAddress(),
		ChunksStored:   int64(resp.GetChunksStored()),
	}, nil
}

// FinalizeMerkleUpload finalizes a merkle upload after the external signer
// has submitted the payForMerkleTree2 transaction. winnerPoolHash is the
// bytes32 value from the MerklePaymentMade event (hex with 0x prefix).
//
// Mirrors Client.FinalizeMerkleUpload over gRPC.
//
// Requires antd >= 0.9.0.
func (c *GrpcClient) FinalizeMerkleUpload(ctx context.Context, uploadID string, winnerPoolHash string, storeDataMap bool) (*FinalizeUploadResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.upload.FinalizeUpload(ctx, &pb.FinalizeUploadRequest{
		UploadId:       uploadID,
		WinnerPoolHash: winnerPoolHash,
		StoreDataMap:   storeDataMap,
	})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &FinalizeUploadResult{
		DataMap:        resp.GetDataMap(),
		Address:        resp.GetAddress(),
		DataMapAddress: resp.GetDataMapAddress(),
		ChunksStored:   int64(resp.GetChunksStored()),
	}, nil
}

// --- Wallet ---
//
// V2-286: parity with REST Client.Wallet* methods. A missing daemon wallet
// (no AUTONOMI_WALLET_KEY) is surfaced as gRPC FailedPrecondition; we map it
// to the same error hierarchy as the other gRPC failure paths.

// WalletAddress returns the wallet's public address (hex with 0x prefix).
func (c *GrpcClient) WalletAddress(ctx context.Context) (*WalletAddress, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.wallet.GetAddress(ctx, &pb.GetWalletAddressRequest{})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &WalletAddress{Address: resp.GetAddress()}, nil
}

// WalletBalance returns the wallet's token and gas balances (atto tokens
// as decimal strings).
func (c *GrpcClient) WalletBalance(ctx context.Context) (*WalletBalance, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.wallet.GetBalance(ctx, &pb.GetWalletBalanceRequest{})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &WalletBalance{
		Balance:    resp.GetBalance(),
		GasBalance: resp.GetGasBalance(),
	}, nil
}

// WalletApprove approves the wallet to spend tokens on the payment vault
// contract. One-time operation; idempotent at the contract level.
func (c *GrpcClient) WalletApprove(ctx context.Context) error {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	_, err := c.wallet.Approve(ctx, &pb.WalletApproveRequest{})
	return errorFromGrpc(err)
}
