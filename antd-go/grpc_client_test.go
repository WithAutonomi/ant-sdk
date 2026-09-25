package antd

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"testing"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"
	"google.golang.org/protobuf/proto"

	pb "github.com/WithAutonomi/ant-sdk/antd-go/proto/antd/v1"
)

const bufSize = 1024 * 1024

// --- Mock service implementations ---

// mockHealthService implements pb.HealthServiceServer.
type mockHealthService struct {
	pb.UnimplementedHealthServiceServer
}

func (m *mockHealthService) Check(_ context.Context, _ *pb.HealthCheckRequest) (*pb.HealthCheckResponse, error) {
	return &pb.HealthCheckResponse{
		Status:              "ok",
		Network:             "local",
		Version:             "0.4.0",
		EvmNetwork:          "local",
		UptimeSeconds:       42,
		BuildCommit:         "abcdef123456",
		PaymentTokenAddress: "0xtoken",
		PaymentVaultAddress: "0xvault",
	}, nil
}

// mockDataService implements pb.DataServiceServer.
type mockDataService struct {
	pb.UnimplementedDataServiceServer
}

// lastPaymentMode captures the payment_mode value seen by the most recent
// data/file request, so tests can assert that the enum wires through to the
// proto field at the boundary. Reset per-call by callers.
var lastPaymentMode string

func (m *mockDataService) PutPublic(_ context.Context, req *pb.PutPublicDataRequest) (*pb.PutPublicDataResponse, error) {
	lastPaymentMode = req.GetPaymentMode()
	return &pb.PutPublicDataResponse{
		Cost:    &pb.Cost{AttoTokens: ""},
		Address: "abc123",
	}, nil
}

func (m *mockDataService) GetPublic(_ context.Context, _ *pb.GetPublicDataRequest) (*pb.GetPublicDataResponse, error) {
	return &pb.GetPublicDataResponse{Data: []byte("hello")}, nil
}

func (m *mockDataService) Put(_ context.Context, req *pb.PutDataRequest) (*pb.PutDataResponse, error) {
	lastPaymentMode = req.GetPaymentMode()
	return &pb.PutDataResponse{
		Cost:    &pb.Cost{AttoTokens: ""},
		DataMap: "dm123",
	}, nil
}

func (m *mockDataService) Get(_ context.Context, _ *pb.GetDataRequest) (*pb.GetDataResponse, error) {
	return &pb.GetDataResponse{Data: []byte("secret")}, nil
}

// Stream emits the private payload as two chunks so the reader's
// chunk-boundary buffering is exercised, not just a single Recv.
func (m *mockDataService) Stream(req *pb.StreamDataRequest, srv grpc.ServerStreamingServer[pb.DataChunk]) error {
	if req.GetIncludeProgress() {
		// Mirror the daemon: attach the byte total as response metadata.
		_ = srv.SetHeader(metadata.Pairs("x-content-length", "6"))
		if err := srv.Send(&pb.DataChunk{Kind: &pb.DataChunk_Progress{Progress: &pb.DownloadProgress{
			Phase: "fetching", Fetched: 1, Total: 2,
		}}}); err != nil {
			return err
		}
	}
	for _, part := range [][]byte{[]byte("sec"), []byte("ret")} {
		if err := srv.Send(&pb.DataChunk{Kind: &pb.DataChunk_Data{Data: part}}); err != nil {
			return err
		}
	}
	return nil
}

func (m *mockDataService) StreamPublic(req *pb.StreamPublicDataRequest, srv grpc.ServerStreamingServer[pb.DataChunk]) error {
	if req.GetIncludeProgress() {
		_ = srv.SetHeader(metadata.Pairs("x-content-length", "5"))
		if err := srv.Send(&pb.DataChunk{Kind: &pb.DataChunk_Progress{Progress: &pb.DownloadProgress{
			Phase: "fetching", Fetched: 1, Total: 2,
		}}}); err != nil {
			return err
		}
	}
	for _, part := range [][]byte{[]byte("hel"), []byte("lo")} {
		if err := srv.Send(&pb.DataChunk{Kind: &pb.DataChunk_Data{Data: part}}); err != nil {
			return err
		}
	}
	return nil
}

func (m *mockDataService) Cost(_ context.Context, req *pb.DataCostRequest) (*pb.Cost, error) {
	lastPaymentMode = req.GetPaymentMode()
	return &pb.Cost{
		AttoTokens:          "50",
		FileSize:            4,
		ChunkCount:          3,
		EstimatedGasCostWei: "150000000000000",
		PaymentMode:         "single",
	}, nil
}

// mockChunkService implements pb.ChunkServiceServer.
type mockChunkService struct {
	pb.UnimplementedChunkServiceServer
}

func (m *mockChunkService) Put(_ context.Context, _ *pb.PutChunkRequest) (*pb.PutChunkResponse, error) {
	return &pb.PutChunkResponse{
		Cost:    &pb.Cost{AttoTokens: "10"},
		Address: "chunk1",
	}, nil
}

func (m *mockChunkService) Get(_ context.Context, _ *pb.GetChunkRequest) (*pb.GetChunkResponse, error) {
	return &pb.GetChunkResponse{Data: []byte("chunkdata")}, nil
}

func (m *mockChunkService) PrepareChunk(_ context.Context, req *pb.PrepareChunkRequest) (*pb.PrepareChunkResponse, error) {
	// Inputs starting with "EXISTS" are treated as already-stored.
	if len(req.GetData()) >= 6 && string(req.GetData()[:6]) == "EXISTS" {
		return &pb.PrepareChunkResponse{
			Address:       "0xabc",
			AlreadyStored: true,
		}, nil
	}
	resp := &pb.PrepareChunkResponse{
		Address:       "0xnewchunk",
		AlreadyStored: false,
		UploadId:      "upid_chunk_42",
		PaymentType:   "wave_batch",
		Payments: []*pb.PaymentEntry{
			{QuoteHash: "0xq1", RewardsAddress: "0xr1", Amount: "100"},
		},
		TotalAmount:         "100",
		PaymentVaultAddress: "0xvault",
		PaymentTokenAddress: "0xtoken",
		RpcUrl:              "http://localhost:8545",
	}
	if req.GetIncludeSignedQuotes() {
		resp.SignedQuotes = mockSignedQuotes("0xq1")
	}
	return resp, nil
}

// mockSignedQuotes is the daemon's shape for one signed wave-batch quote:
// raw msgpack bytes on the wire ("opaque" / "side" stand in), which the
// client must base64-encode into the shared model.
func mockSignedQuotes(quoteHash string) []*pb.SignedQuoteEntry {
	return []*pb.SignedQuoteEntry{
		{QuoteHash: quoteHash, Quote: []byte("opaque"), CommitmentSidecar: []byte("side")},
	}
}

// mockVerifyService verifies "opaque" quotes only, treats a present sidecar
// as a pinned commitment of 42 keys, and reports the batch valid when every
// entry is.
type mockVerifyService struct {
	pb.UnimplementedVerifyServiceServer
}

func (m *mockVerifyService) VerifyQuotes(_ context.Context, req *pb.VerifyQuotesRequest) (*pb.VerifyQuotesResponse, error) {
	resp := &pb.VerifyQuotesResponse{Valid: len(req.GetEntries()) > 0}
	for _, e := range req.GetEntries() {
		v := &pb.VerifyQuoteVerdict{
			QuoteHash:         e.GetQuoteHash(),
			QuoteDecoded:      true,
			TimestampUnixSecs: 1756000000,
			Content:           "aa",
			Price:             "5",
			RewardsAddress:    e.GetRewardsAddress(),
		}
		if string(e.GetSignedQuote()) == "opaque" {
			v.Valid = true
		} else {
			v.Error = "signed_quote did not deserialize as a PaymentQuote"
			resp.Valid = false
		}
		if len(e.GetCommitmentSidecar()) > 0 {
			v.CommittedKeyCount = 42
			v.Pinned = true
		}
		resp.Entries = append(resp.Entries, v)
	}
	return resp, nil
}

func (m *mockChunkService) FinalizeChunk(_ context.Context, req *pb.FinalizeChunkRequest) (*pb.FinalizeChunkResponse, error) {
	// Echo the upload_id into the address so the test can verify forwarding.
	return &pb.FinalizeChunkResponse{
		Address: "addr_for_" + req.GetUploadId(),
	}, nil
}

// mockUploadService implements pb.UploadServiceServer.
type mockUploadService struct {
	pb.UnimplementedUploadServiceServer
}

func (m *mockUploadService) PrepareFileUpload(_ context.Context, req *pb.PrepareFileUploadRequest) (*pb.PrepareUploadResponse, error) {
	// Encode visibility into upload_id so the test can verify forwarding.
	resp := &pb.PrepareUploadResponse{
		UploadId:    "upid_file_" + req.GetVisibility(),
		PaymentType: "wave_batch",
		Payments: []*pb.PaymentEntry{
			{QuoteHash: "0xqa", RewardsAddress: "0xra", Amount: "1"},
		},
		TotalAmount:         "1",
		PaymentVaultAddress: "0xvault",
		PaymentTokenAddress: "0xtoken",
		RpcUrl:              "http://localhost:8545",
		TotalChunks:         3,
		AlreadyStoredCount:  1,
	}
	if req.GetIncludeSignedQuotes() {
		resp.SignedQuotes = mockSignedQuotes("0xqa")
		if req.GetPath() == bigPreparePath {
			resp.SignedQuotes = bigSignedQuotes()
		}
	}
	return resp, nil
}

// bigPreparePath makes the mock return bigSignedQuotes: a full-size
// wave-batch prepare whose signed quotes push the response well past
// grpc-go's 4 MiB default receive limit.
const bigPreparePath = "/big"

// bigSignedQuotes is 1024 entries (the daemon's MAX_VERIFY_ENTRIES) with
// 8,000-byte quote blobs, about 8.3 MB on the wire. Synthetic transport
// fixture only; the bytes are not real quotes.
func bigSignedQuotes() []*pb.SignedQuoteEntry {
	entries := make([]*pb.SignedQuoteEntry, 1024)
	for i := range entries {
		entries[i] = &pb.SignedQuoteEntry{
			QuoteHash:         fmt.Sprintf("0xq%04d", i),
			Quote:             bytes.Repeat([]byte{'q'}, 8000),
			CommitmentSidecar: []byte("side"),
		}
	}
	return entries
}

func (m *mockUploadService) PrepareDataUpload(_ context.Context, req *pb.PrepareDataUploadRequest) (*pb.PrepareUploadResponse, error) {
	// Merkle when payload starts with "MERKLE"; wave-batch otherwise.
	uploadID := "upid_data_" + req.GetVisibility()
	d := req.GetData()
	if len(d) >= 6 && string(d[:6]) == "MERKLE" {
		return &pb.PrepareUploadResponse{
			UploadId:    uploadID,
			PaymentType: "merkle",
			Depth:       7,
			PoolCommitments: []*pb.PoolCommitmentEntry{
				{
					PoolHash: "0xpool",
					Candidates: []*pb.CandidateNodeEntry{
						{RewardsAddress: "0xc1", Amount: "5"},
					},
				},
			},
			MerklePaymentTimestamp: 1700000000,
			TotalAmount:            "0",
			PaymentVaultAddress:    "0xvault",
			PaymentTokenAddress:    "0xtoken",
			RpcUrl:                 "http://localhost:8545",
		}, nil
	}
	resp := &pb.PrepareUploadResponse{
		UploadId:    uploadID,
		PaymentType: "wave_batch",
		Payments: []*pb.PaymentEntry{
			{QuoteHash: "0xqb", RewardsAddress: "0xrb", Amount: "2"},
		},
		TotalAmount:         "2",
		PaymentVaultAddress: "0xvault",
		PaymentTokenAddress: "0xtoken",
		RpcUrl:              "http://localhost:8545",
	}
	if req.GetIncludeSignedQuotes() {
		resp.SignedQuotes = mockSignedQuotes("0xqb")
	}
	return resp, nil
}

func (m *mockUploadService) FinalizeUpload(_ context.Context, req *pb.FinalizeUploadRequest) (*pb.FinalizeUploadResponse, error) {
	// Magic id: simulate a quorum-shortfall finalize (PARTIAL_UPLOAD).
	if req.GetUploadId() == "partial" {
		return nil, status.Error(codes.Aborted, "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)")
	}
	// Magic id: an ABORTED that is not a partial upload at all (nothing
	// emits this today; guards the message-prefix gate).
	if req.GetUploadId() == "aborted-other" {
		return nil, status.Error(codes.Aborted, "operation aborted for some other reason")
	}
	// Magic id: an ABORTED that embeds the partial-upload text without
	// starting with it (a wrapped upstream error); guards the anchored gate.
	if req.GetUploadId() == "aborted-embedded" {
		return nil, status.Error(codes.Aborted, "upstream error: Partial upload: 1/3 chunks stored, 2 failed")
	}
	// Magic id: a partial upload the daemon did NOT retain (unpaid merkle
	// batches, or an older daemon's message).
	if req.GetUploadId() == "partial-final" {
		return nil, status.Error(codes.Aborted, "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum (stored chunks persist; re-prepare the same content to retry only the remainder)")
	}
	// Merkle multi-batch: winner_pool_hashes populated. Echo the paid-batch
	// count back as ChunksStored so tests can assert the list arrived.
	if hashes := req.GetWinnerPoolHashes(); len(hashes) > 0 {
		paid := 0
		for _, h := range hashes {
			if h != "" {
				paid++
			}
		}
		return &pb.FinalizeUploadResponse{
			DataMap:      "dm_merkle_multi",
			ChunksStored: uint64(paid),
		}, nil
	}
	// Merkle: winner_pool_hash populated, tx_hashes empty.
	if req.GetWinnerPoolHash() != "" {
		address := ""
		if req.GetStoreDataMap() {
			address = "stored_on_network"
		}
		return &pb.FinalizeUploadResponse{
			DataMap:      "dm_merkle",
			Address:      address,
			ChunksStored: 64,
		}, nil
	}
	// Wave-batch: include data_map_address when visibility was public
	// (encoded into upload_id by the prepare mock).
	dataMapAddress := ""
	uid := req.GetUploadId()
	if len(uid) >= 6 && uid[len(uid)-6:] == "public" {
		dataMapAddress = "addr_public_dm"
	}
	return &pb.FinalizeUploadResponse{
		DataMap:        "dm_wave",
		DataMapAddress: dataMapAddress,
		ChunksStored:   3,
	}, nil
}

// mockFileService implements pb.FileServiceServer.
type mockFileService struct {
	pb.UnimplementedFileServiceServer
}

func (m *mockFileService) Put(_ context.Context, req *pb.PutFileRequest) (*pb.PutFileResponse, error) {
	lastPaymentMode = req.GetPaymentMode()
	return &pb.PutFileResponse{
		DataMap:         "filedm1",
		StorageCostAtto: "500",
		GasCostWei:      "21",
		ChunksStored:    2,
		PaymentModeUsed: "single",
	}, nil
}

func (m *mockFileService) Get(_ context.Context, _ *pb.GetFileRequest) (*pb.GetFileResponse, error) {
	return &pb.GetFileResponse{}, nil
}

func (m *mockFileService) PutPublic(_ context.Context, req *pb.PutFileRequest) (*pb.PutFilePublicResponse, error) {
	lastPaymentMode = req.GetPaymentMode()
	return &pb.PutFilePublicResponse{
		Address:         "file1",
		StorageCostAtto: "1000",
		GasCostWei:      "42",
		ChunksStored:    3,
		PaymentModeUsed: "auto",
	}, nil
}

func (m *mockFileService) GetPublic(_ context.Context, _ *pb.GetFilePublicRequest) (*pb.GetFileResponse, error) {
	return &pb.GetFileResponse{}, nil
}

func (m *mockFileService) Cost(_ context.Context, req *pb.FileCostRequest) (*pb.Cost, error) {
	lastPaymentMode = req.GetPaymentMode()
	return &pb.Cost{
		AttoTokens:          "1000",
		FileSize:            4096,
		ChunkCount:          3,
		EstimatedGasCostWei: "150000000000000",
		PaymentMode:         "auto",
	}, nil
}

// --- Error mock services ---

// errorHealthService always returns a configurable gRPC error.
type errorHealthService struct {
	pb.UnimplementedHealthServiceServer
	code codes.Code
	msg  string
}

func (m *errorHealthService) Check(_ context.Context, _ *pb.HealthCheckRequest) (*pb.HealthCheckResponse, error) {
	return nil, status.Error(m.code, m.msg)
}

// --- Test helpers ---

// startMockServer creates an in-process gRPC server with all mock services registered
// and returns a connected GrpcClient.
func startMockServer(t *testing.T) *GrpcClient {
	t.Helper()
	return startMockServerWith(t)
}

// startMockServerWith is startMockServer with extra client options applied
// after the bufconn dialer.
func startMockServerWith(t *testing.T, extra ...GrpcOption) *GrpcClient {
	t.Helper()
	lis := bufconn.Listen(bufSize)

	s := grpc.NewServer()
	pb.RegisterHealthServiceServer(s, &mockHealthService{})
	pb.RegisterDataServiceServer(s, &mockDataService{})
	pb.RegisterChunkServiceServer(s, &mockChunkService{})
	pb.RegisterFileServiceServer(s, &mockFileService{})
	pb.RegisterUploadServiceServer(s, &mockUploadService{})
	pb.RegisterWalletServiceServer(s, &mockWalletService{})
	pb.RegisterVerifyServiceServer(s, &mockVerifyService{})

	go func() {
		// Server stop on test cleanup is expected, swallow the error.
		_ = s.Serve(lis)
	}()
	t.Cleanup(func() { s.Stop() })

	dialer := func(context.Context, string) (net.Conn, error) {
		return lis.Dial()
	}

	opts := append([]GrpcOption{
		WithDialOptions(
			grpc.WithContextDialer(dialer),
			grpc.WithTransportCredentials(insecure.NewCredentials()),
		),
	}, extra...)
	c, err := NewGrpcClient("passthrough:///bufconn", opts...)
	if err != nil {
		t.Fatalf("failed to create grpc client: %v", err)
	}
	t.Cleanup(func() { c.Close() })
	return c
}

// startErrorServer creates an in-process gRPC server that always returns the
// given gRPC error code/message for the HealthService.
func startErrorServer(t *testing.T, code codes.Code, msg string) *GrpcClient {
	t.Helper()
	lis := bufconn.Listen(bufSize)

	s := grpc.NewServer()
	pb.RegisterHealthServiceServer(s, &errorHealthService{code: code, msg: msg})

	go func() {
		// Server stop on test cleanup is expected, swallow the error.
		_ = s.Serve(lis)
	}()
	t.Cleanup(func() { s.Stop() })

	dialer := func(context.Context, string) (net.Conn, error) {
		return lis.Dial()
	}

	c, err := NewGrpcClient("passthrough:///bufconn",
		WithDialOptions(
			grpc.WithContextDialer(dialer),
			grpc.WithTransportCredentials(insecure.NewCredentials()),
		),
	)
	if err != nil {
		t.Fatalf("failed to create grpc client: %v", err)
	}
	t.Cleanup(func() { c.Close() })
	return c
}

// --- Tests for all gRPC methods ---

func TestGrpcHealth(t *testing.T) {
	c := startMockServer(t)
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

func TestGrpcDataPutPublic(t *testing.T) {
	c := startMockServer(t)
	lastPaymentMode = ""
	put, err := c.DataPutPublic(context.Background(), []byte("hello"), PaymentModeMerkle)
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "abc123" {
		t.Fatalf("unexpected put: %+v", put)
	}
	if lastPaymentMode != "merkle" {
		t.Fatalf("payment_mode did not wire through: got %q, want %q", lastPaymentMode, "merkle")
	}
}

func TestGrpcDataGetPublic(t *testing.T) {
	c := startMockServer(t)
	data, err := c.DataGetPublic(context.Background(), "abc123")
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "hello" {
		t.Fatalf("unexpected data: %s", data)
	}
}

func TestGrpcDataPut(t *testing.T) {
	c := startMockServer(t)
	lastPaymentMode = ""
	put, err := c.DataPut(context.Background(), []byte("secret"), PaymentModeSingle)
	if err != nil {
		t.Fatal(err)
	}
	if put.DataMap != "dm123" {
		t.Fatalf("unexpected put: %+v", put)
	}
	if lastPaymentMode != "single" {
		t.Fatalf("payment_mode did not wire through: got %q, want %q", lastPaymentMode, "single")
	}
}

func TestGrpcDataGet(t *testing.T) {
	c := startMockServer(t)
	data, err := c.DataGet(context.Background(), "dm123")
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "secret" {
		t.Fatalf("unexpected data: %s", data)
	}
}

func TestGrpcDataStream(t *testing.T) {
	c := startMockServer(t)
	rc, err := c.DataStream(context.Background(), "dm123")
	if err != nil {
		t.Fatal(err)
	}
	defer rc.Close()
	data, err := io.ReadAll(rc)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "secret" {
		t.Fatalf("unexpected streamed data: %s", data)
	}
}

func TestGrpcDataStreamPublic(t *testing.T) {
	c := startMockServer(t)
	rc, err := c.DataStreamPublic(context.Background(), "abc123")
	if err != nil {
		t.Fatal(err)
	}
	defer rc.Close()
	data, err := io.ReadAll(rc)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "hello" {
		t.Fatalf("unexpected streamed data: %s", data)
	}
}

// drainFrames reads a DownloadFrameStream to EOF, returning the concatenated
// data bytes, every progress frame, and the meta byte-total (if any).
func drainFrames(t *testing.T, s DownloadFrameStream) ([]byte, []DownloadProgress, *uint64) {
	t.Helper()
	var data []byte
	var progress []DownloadProgress
	var meta *uint64
	for {
		frame, err := s.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		switch {
		case frame.IsMeta():
			meta = frame.Meta
		case frame.IsProgress():
			progress = append(progress, *frame.Progress)
		default:
			data = append(data, frame.Data...)
		}
	}
	return data, progress, meta
}

func TestGrpcDataStreamWithProgress(t *testing.T) {
	c := startMockServer(t)
	s, err := c.DataStreamWithProgress(context.Background(), "dm123")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	data, progress, meta := drainFrames(t, s)
	if string(data) != "secret" {
		t.Fatalf("unexpected streamed data: %s", data)
	}
	if meta == nil || *meta != 6 {
		t.Fatalf("expected Meta byte-total 6, got %v", meta)
	}
	if len(progress) != 1 || progress[0].Phase != "fetching" || progress[0].Fetched != 1 || progress[0].Total != 2 {
		t.Fatalf("unexpected progress frames: %+v", progress)
	}
}

func TestGrpcDataStreamPublicWithProgress(t *testing.T) {
	c := startMockServer(t)
	s, err := c.DataStreamPublicWithProgress(context.Background(), "abc123")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	data, progress, meta := drainFrames(t, s)
	if string(data) != "hello" {
		t.Fatalf("unexpected streamed data: %s", data)
	}
	if meta == nil || *meta != 5 {
		t.Fatalf("expected Meta byte-total 5, got %v", meta)
	}
	if len(progress) != 1 || progress[0].Phase != "fetching" {
		t.Fatalf("unexpected progress frames: %+v", progress)
	}
}

func TestGrpcDataCost(t *testing.T) {
	c := startMockServer(t)
	lastPaymentMode = ""
	est, err := c.DataCost(context.Background(), []byte("test"), PaymentModeAuto)
	if err != nil {
		t.Fatal(err)
	}
	if est.Cost != "50" || est.FileSize != 4 || est.ChunkCount != 3 ||
		est.EstimatedGasCostWei != "150000000000000" || est.PaymentMode != "single" {
		t.Fatalf("unexpected estimate: %+v", est)
	}
	if lastPaymentMode != "auto" {
		t.Fatalf("payment_mode did not wire through: got %q, want %q", lastPaymentMode, "auto")
	}
}

func TestGrpcChunkPut(t *testing.T) {
	c := startMockServer(t)
	put, err := c.ChunkPut(context.Background(), []byte("chunkdata"))
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "chunk1" || put.Cost != "10" {
		t.Fatalf("unexpected chunk put: %+v", put)
	}
}

func TestGrpcChunkGet(t *testing.T) {
	c := startMockServer(t)
	data, err := c.ChunkGet(context.Background(), "chunk1")
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "chunkdata" {
		t.Fatalf("unexpected chunk data: %s", data)
	}
}

func TestGrpcFilePutPublic(t *testing.T) {
	c := startMockServer(t)
	lastPaymentMode = ""
	put, err := c.FilePutPublic(context.Background(), "/tmp/test.txt", PaymentModeAuto)
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "file1" || put.StorageCostAtto != "1000" || put.GasCostWei != "42" || put.ChunksStored != 3 || put.PaymentModeUsed != "auto" {
		t.Fatalf("unexpected file upload: %+v", put)
	}
	if lastPaymentMode != "auto" {
		t.Fatalf("payment_mode did not wire through: got %q, want %q", lastPaymentMode, "auto")
	}
}

func TestGrpcFileGetPublic(t *testing.T) {
	c := startMockServer(t)
	err := c.FileGetPublic(context.Background(), "file1", "/tmp/out.txt")
	if err != nil {
		t.Fatal(err)
	}
}

func TestGrpcFilePut(t *testing.T) {
	c := startMockServer(t)
	lastPaymentMode = ""
	put, err := c.FilePut(context.Background(), "/tmp/test.txt", PaymentModeMerkle)
	if err != nil {
		t.Fatal(err)
	}
	if put.DataMap != "filedm1" || put.StorageCostAtto != "500" || put.GasCostWei != "21" || put.ChunksStored != 2 || put.PaymentModeUsed != "single" {
		t.Fatalf("unexpected file put: %+v", put)
	}
	if lastPaymentMode != "merkle" {
		t.Fatalf("payment_mode did not wire through: got %q, want %q", lastPaymentMode, "merkle")
	}
}

func TestGrpcFileGet(t *testing.T) {
	c := startMockServer(t)
	if err := c.FileGet(context.Background(), "filedm1", "/tmp/out.txt"); err != nil {
		t.Fatal(err)
	}
}

func TestGrpcFileCost(t *testing.T) {
	c := startMockServer(t)
	lastPaymentMode = ""
	est, err := c.FileCost(context.Background(), "/tmp/test.txt", true, PaymentModeSingle)
	if err != nil {
		t.Fatal(err)
	}
	if est.Cost != "1000" || est.FileSize != 4096 || est.ChunkCount != 3 ||
		est.EstimatedGasCostWei != "150000000000000" || est.PaymentMode != "auto" {
		t.Fatalf("unexpected estimate: %+v", est)
	}
	if lastPaymentMode != "single" {
		t.Fatalf("payment_mode did not wire through: got %q, want %q", lastPaymentMode, "single")
	}
}

// --- External-signer prepare/finalize tests ---

func TestGrpcPrepareUploadOmitsVisibilityWhenPrivate(t *testing.T) {
	c := startMockServer(t)
	r, err := c.PrepareUpload(context.Background(), "/tmp/x.bin")
	if err != nil {
		t.Fatal(err)
	}
	// PrepareUpload sets no visibility, so proto3 default of "" is sent;
	// the mock echoes that into upload_id.
	if r.UploadID != "upid_file_" {
		t.Fatalf("expected default visibility echoed: got %q", r.UploadID)
	}
	if r.TotalChunks != 3 || r.AlreadyStoredCount != 1 {
		t.Fatalf("preflight fields not mapped: total=%d already=%d", r.TotalChunks, r.AlreadyStoredCount)
	}
	if r.PaymentType != "wave_batch" {
		t.Fatalf("expected wave_batch, got %q", r.PaymentType)
	}
	if len(r.Payments) != 1 || r.Payments[0].QuoteHash != "0xqa" {
		t.Fatalf("unexpected payments: %+v", r.Payments)
	}
	if r.Depth != 0 || len(r.PoolCommitments) != 0 {
		t.Fatalf("merkle fields populated on wave-batch: %+v", r)
	}
}

func TestGrpcPrepareUploadWithOptionsSendsFlagAndMapsSignedQuotes(t *testing.T) {
	c := startMockServer(t)
	r, err := c.PrepareUploadWithOptions(context.Background(), "/tmp/x.bin", PrepareOptions{IncludeSignedQuotes: true})
	if err != nil {
		t.Fatal(err)
	}
	if len(r.SignedQuotes) != 1 {
		t.Fatalf("unexpected signed_quotes: %+v", r.SignedQuotes)
	}
	// Raw proto bytes must land base64-encoded, exactly as REST delivers them.
	sq := r.SignedQuotes[0]
	if sq.QuoteHash != "0xqa" || sq.Quote != "b3BhcXVl" || sq.CommitmentSidecar != "c2lkZQ==" {
		t.Fatalf("unexpected entry: %+v", sq)
	}
	// Options must not disturb the rest of the mapping.
	if r.UploadID != "upid_file_" || r.TotalChunks != 3 || r.AlreadyStoredCount != 1 {
		t.Fatalf("unexpected result: %+v", r)
	}
}

func TestGrpcPrepareUploadWithoutFlagCarriesNoSignedQuotes(t *testing.T) {
	c := startMockServer(t)
	r, err := c.PrepareUpload(context.Background(), "/tmp/x.bin")
	if err != nil {
		t.Fatal(err)
	}
	if len(r.SignedQuotes) != 0 {
		t.Fatalf("signed_quotes populated without the flag: %+v", r.SignedQuotes)
	}
}

func TestGrpcPrepareDataUploadWithOptionsSendsFlagAndVisibility(t *testing.T) {
	c := startMockServer(t)
	r, err := c.PrepareDataUploadWithOptions(context.Background(), []byte("small"), PrepareOptions{
		Visibility:          "public",
		IncludeSignedQuotes: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if r.UploadID != "upid_data_public" {
		t.Fatalf("visibility not forwarded: %q", r.UploadID)
	}
	if len(r.SignedQuotes) != 1 || r.SignedQuotes[0].Quote != "b3BhcXVl" {
		t.Fatalf("unexpected signed_quotes: %+v", r.SignedQuotes)
	}
}

func TestGrpcPrepareChunkUploadWithOptionsMapsSignedQuotes(t *testing.T) {
	c := startMockServer(t)
	r, err := c.PrepareChunkUploadWithOptions(context.Background(), []byte("fresh chunk"), PrepareOptions{IncludeSignedQuotes: true})
	if err != nil {
		t.Fatal(err)
	}
	if len(r.SignedQuotes) != 1 || r.SignedQuotes[0].QuoteHash != "0xq1" || r.SignedQuotes[0].Quote != "b3BhcXVl" {
		t.Fatalf("unexpected signed_quotes: %+v", r.SignedQuotes)
	}
	plain, err := c.PrepareChunkUpload(context.Background(), []byte("fresh chunk"))
	if err != nil {
		t.Fatal(err)
	}
	if len(plain.SignedQuotes) != 0 {
		t.Fatalf("signed_quotes populated without the flag: %+v", plain.SignedQuotes)
	}
}

// A full-size signed-quote prepare response (>4 MiB, grpc-go's default
// receive limit) must decode on a default client: the SDK sets its own
// receive ceiling, sized like the daemon's, on every call.
func TestGrpcPrepareUploadLargeSignedQuoteResponseFitsDefaultRecvLimit(t *testing.T) {
	fixture := &pb.PrepareUploadResponse{SignedQuotes: bigSignedQuotes()}
	if n := proto.Size(fixture); n <= 4*1024*1024 {
		t.Fatalf("fixture must exceed grpc-go's 4 MiB default to be a regression test, got %d bytes", n)
	}

	c := startMockServer(t)
	r, err := c.PrepareUploadWithOptions(context.Background(), bigPreparePath, PrepareOptions{IncludeSignedQuotes: true})
	if err != nil {
		t.Fatalf("large signed-quote response rejected on a default client: %v", err)
	}
	if len(r.SignedQuotes) != 1024 {
		t.Fatalf("expected 1024 signed quotes, got %d", len(r.SignedQuotes))
	}
	if r.SignedQuotes[1023].QuoteHash != "0xq1023" || len(r.SignedQuotes[1023].Quote) != base64.StdEncoding.EncodedLen(8000) {
		t.Fatalf("last entry mangled: %+v", r.SignedQuotes[1023])
	}
}

// The ceiling is a real bound, not a no-op: a caller-set limit below the
// response size is enforced and surfaces as the mapped 413, not a hang or a
// truncated result.
func TestGrpcPrepareUploadRecvLimitIsEnforcedAndConfigurable(t *testing.T) {
	c := startMockServerWith(t, WithGrpcMaxRecvMsgSize(1024*1024))
	_, err := c.PrepareUploadWithOptions(context.Background(), bigPreparePath, PrepareOptions{IncludeSignedQuotes: true})
	if err == nil {
		t.Fatal("expected the 1 MiB receive limit to reject an 8 MB response")
	}
	var tooLarge *TooLargeError
	if !errors.As(err, &tooLarge) || !strings.Contains(err.Error(), "larger than max") {
		t.Fatalf("expected a TooLargeError carrying the receive-limit message, got: %v", err)
	}
	// A small response on the same client is unaffected.
	if _, err := c.PrepareUpload(context.Background(), "/tmp/x.bin"); err != nil {
		t.Fatalf("small response failed under the lowered limit: %v", err)
	}
}

func TestGrpcVerifyQuotes(t *testing.T) {
	c := startMockServer(t)
	// Same inputs as the REST TestVerifyQuotes: base64 strings in, decoded
	// to raw bytes on the wire ("opaque" verifies, "opaque2" does not).
	res, err := c.VerifyQuotes(context.Background(), []VerifyQuoteEntry{
		{QuoteHash: "qh1", RewardsAddress: "ra1", Amount: "5", SignedQuote: "b3BhcXVl", CommitmentSidecar: "c2lkZQ=="},
		{QuoteHash: "qh2", RewardsAddress: "ra2", Amount: "6", SignedQuote: "b3BhcXVlMg=="},
	})
	if err != nil {
		t.Fatal(err)
	}
	if res.Valid {
		t.Fatal("expected overall valid=false")
	}
	if len(res.Entries) != 2 {
		t.Fatalf("unexpected entries: %+v", res.Entries)
	}
	if !res.Entries[0].Valid || res.Entries[0].CommittedKeyCount != 42 || !res.Entries[0].Pinned ||
		res.Entries[0].TimestampUnixSecs != 1756000000 || res.Entries[0].RewardsAddress != "ra1" {
		t.Fatalf("unexpected first verdict: %+v", res.Entries[0])
	}
	if res.Entries[1].Valid || res.Entries[1].Error == "" || res.Entries[1].Pinned {
		t.Fatalf("unexpected second verdict: %+v", res.Entries[1])
	}
}

func TestGrpcVerifyQuotesRoundTripsPreparedEntries(t *testing.T) {
	// A signed quote obtained over gRPC (base64-encoded into the model) must
	// feed VerifyQuotes unchanged and verify.
	c := startMockServer(t)
	prep, err := c.PrepareUploadWithOptions(context.Background(), "/tmp/x.bin", PrepareOptions{IncludeSignedQuotes: true})
	if err != nil {
		t.Fatal(err)
	}
	sq := prep.SignedQuotes[0]
	res, err := c.VerifyQuotes(context.Background(), []VerifyQuoteEntry{{
		QuoteHash:         sq.QuoteHash,
		RewardsAddress:    prep.Payments[0].RewardsAddress,
		Amount:            prep.Payments[0].Amount,
		SignedQuote:       sq.Quote,
		CommitmentSidecar: sq.CommitmentSidecar,
	}})
	if err != nil {
		t.Fatal(err)
	}
	if !res.Valid || len(res.Entries) != 1 || !res.Entries[0].Pinned {
		t.Fatalf("round-tripped entry did not verify: %+v", res)
	}
}

func TestGrpcVerifyQuotesRejectsMalformedBase64BeforeSending(t *testing.T) {
	c := startMockServer(t)
	_, err := c.VerifyQuotes(context.Background(), []VerifyQuoteEntry{
		{QuoteHash: "qh1", SignedQuote: "not base64!"},
	})
	if err == nil || !strings.Contains(err.Error(), "signed_quote is not valid base64") {
		t.Fatalf("expected a base64 error, got %v", err)
	}
	_, err = c.VerifyQuotes(context.Background(), []VerifyQuoteEntry{
		{QuoteHash: "qh1", SignedQuote: "b3BhcXVl", CommitmentSidecar: "%%%"},
	})
	if err == nil || !strings.Contains(err.Error(), "commitment_sidecar is not valid base64") {
		t.Fatalf("expected a base64 error, got %v", err)
	}
}

func TestGrpcPrepareUploadPublicForwardsVisibility(t *testing.T) {
	c := startMockServer(t)
	r, err := c.PrepareUploadPublic(context.Background(), "/tmp/x.bin")
	if err != nil {
		t.Fatal(err)
	}
	if r.UploadID != "upid_file_public" {
		t.Fatalf("expected visibility public to wire through: got %q", r.UploadID)
	}
}

func TestGrpcPrepareDataUploadWaveBatch(t *testing.T) {
	c := startMockServer(t)
	r, err := c.PrepareDataUpload(context.Background(), []byte("small"))
	if err != nil {
		t.Fatal(err)
	}
	if r.UploadID != "upid_data_" {
		t.Fatalf("unexpected upload_id: %q", r.UploadID)
	}
	if r.PaymentType != "wave_batch" {
		t.Fatalf("expected wave_batch, got %q", r.PaymentType)
	}
	if r.Depth != 0 {
		t.Fatalf("merkle depth set on wave-batch: %d", r.Depth)
	}
}

func TestGrpcPrepareDataUploadMerkle(t *testing.T) {
	c := startMockServer(t)
	r, err := c.PrepareDataUpload(context.Background(), []byte("MERKLE-large-payload"))
	if err != nil {
		t.Fatal(err)
	}
	if r.PaymentType != "merkle" {
		t.Fatalf("expected merkle, got %q", r.PaymentType)
	}
	if r.Depth != 7 {
		t.Fatalf("expected depth 7, got %d", r.Depth)
	}
	if r.MerklePaymentTimestamp != 1700000000 {
		t.Fatalf("expected merkle timestamp 1700000000, got %d", r.MerklePaymentTimestamp)
	}
	if len(r.PoolCommitments) != 1 || r.PoolCommitments[0].PoolHash != "0xpool" {
		t.Fatalf("unexpected pool commitments: %+v", r.PoolCommitments)
	}
	if r.PoolCommitments[0].Candidates[0].RewardsAddress != "0xc1" {
		t.Fatalf("unexpected candidate: %+v", r.PoolCommitments[0].Candidates[0])
	}
}

func TestGrpcFinalizeUploadWaveBatchPrivateOmitsDataMapAddress(t *testing.T) {
	c := startMockServer(t)
	r, err := c.FinalizeUpload(context.Background(), "upid_file_", map[string]string{"0xq1": "0xtx1"}, false)
	if err != nil {
		t.Fatal(err)
	}
	if r.DataMap != "dm_wave" {
		t.Fatalf("unexpected data_map: %q", r.DataMap)
	}
	if r.DataMapAddress != "" {
		t.Fatalf("expected empty data_map_address for private finalize: %q", r.DataMapAddress)
	}
	if r.ChunksStored != 3 {
		t.Fatalf("expected 3 chunks_stored, got %d", r.ChunksStored)
	}
}

func TestGrpcFinalizeUploadWaveBatchPublicReturnsDataMapAddress(t *testing.T) {
	c := startMockServer(t)
	r, err := c.FinalizeUpload(context.Background(), "upid_file_public", map[string]string{"0xq1": "0xtx1"}, false)
	if err != nil {
		t.Fatal(err)
	}
	if r.DataMapAddress != "addr_public_dm" {
		t.Fatalf("expected data_map_address for public finalize: got %q", r.DataMapAddress)
	}
}

func TestGrpcFinalizeMerkleUploadStoreDataMapTrue(t *testing.T) {
	c := startMockServer(t)
	r, err := c.FinalizeMerkleUpload(context.Background(), "upid_data_", "0xwinpool", true)
	if err != nil {
		t.Fatal(err)
	}
	if r.DataMap != "dm_merkle" {
		t.Fatalf("unexpected data_map: %q", r.DataMap)
	}
	if r.Address != "stored_on_network" {
		t.Fatalf("expected address populated on store_data_map=true: %q", r.Address)
	}
	if r.ChunksStored != 64 {
		t.Fatalf("expected 64 chunks_stored, got %d", r.ChunksStored)
	}
}

func TestGrpcFinalizeMerkleUploadStoreDataMapFalse(t *testing.T) {
	c := startMockServer(t)
	r, err := c.FinalizeMerkleUpload(context.Background(), "upid_data_", "0xwinpool", false)
	if err != nil {
		t.Fatal(err)
	}
	if r.DataMap != "dm_merkle" {
		t.Fatalf("unexpected data_map: %q", r.DataMap)
	}
	if r.Address != "" {
		t.Fatalf("expected empty address for store_data_map=false: %q", r.Address)
	}
}

func TestGrpcPrepareChunkUploadNewChunk(t *testing.T) {
	c := startMockServer(t)
	r, err := c.PrepareChunkUpload(context.Background(), []byte("newchunk"))
	if err != nil {
		t.Fatal(err)
	}
	if r.AlreadyStored {
		t.Fatal("expected already_stored=false for new chunk")
	}
	if r.Address != "0xnewchunk" {
		t.Fatalf("unexpected address: %q", r.Address)
	}
	if r.UploadID != "upid_chunk_42" {
		t.Fatalf("unexpected upload_id: %q", r.UploadID)
	}
	if r.PaymentType != "wave_batch" || r.TotalAmount != "100" {
		t.Fatalf("unexpected payment shape: %+v", r)
	}
	if len(r.Payments) != 1 || r.Payments[0].QuoteHash != "0xq1" {
		t.Fatalf("unexpected payments: %+v", r.Payments)
	}
	if r.RPCUrl != "http://localhost:8545" {
		t.Fatalf("unexpected rpc_url: %q", r.RPCUrl)
	}
}

func TestGrpcPrepareChunkUploadAlreadyStoredShortCircuit(t *testing.T) {
	c := startMockServer(t)
	r, err := c.PrepareChunkUpload(context.Background(), []byte("EXISTS-data"))
	if err != nil {
		t.Fatal(err)
	}
	if !r.AlreadyStored {
		t.Fatal("expected already_stored=true")
	}
	if r.Address != "0xabc" {
		t.Fatalf("unexpected address: %q", r.Address)
	}
	if r.UploadID != "" {
		t.Fatalf("expected empty upload_id on short-circuit: %q", r.UploadID)
	}
	if len(r.Payments) != 0 {
		t.Fatalf("expected no payments on short-circuit: %+v", r.Payments)
	}
}

func TestGrpcFinalizeChunkUploadReturnsAddressAndForwardsBody(t *testing.T) {
	c := startMockServer(t)
	addr, err := c.FinalizeChunkUpload(context.Background(), "upid_chunk_42", map[string]string{"0xq1": "0xtxabc"})
	if err != nil {
		t.Fatal(err)
	}
	if addr != "addr_for_upid_chunk_42" {
		t.Fatalf("expected echo, got: %q", addr)
	}
}

// --- gRPC error mapping tests ---

func TestGrpcErrorNotFound(t *testing.T) {
	c := startErrorServer(t, codes.NotFound, "not found")
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

func TestGrpcErrorInvalidArgument(t *testing.T) {
	c := startErrorServer(t, codes.InvalidArgument, "invalid data")
	_, err := c.Health(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	var br *BadRequestError
	if !errors.As(err, &br) {
		t.Fatalf("expected BadRequestError, got %T: %v", err, err)
	}
	if br.StatusCode != 400 {
		t.Fatalf("expected status 400, got %d", br.StatusCode)
	}
}

func TestGrpcErrorFailedPrecondition(t *testing.T) {
	c := startErrorServer(t, codes.FailedPrecondition, "insufficient funds")
	_, err := c.Health(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	var pe *PaymentError
	if !errors.As(err, &pe) {
		t.Fatalf("expected PaymentError, got %T: %v", err, err)
	}
	if pe.StatusCode != 402 {
		t.Fatalf("expected status 402, got %d", pe.StatusCode)
	}
}

func TestGrpcErrorAlreadyExists(t *testing.T) {
	c := startErrorServer(t, codes.AlreadyExists, "already exists")
	_, err := c.Health(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	var ae *AlreadyExistsError
	if !errors.As(err, &ae) {
		t.Fatalf("expected AlreadyExistsError, got %T: %v", err, err)
	}
	if ae.StatusCode != 409 {
		t.Fatalf("expected status 409, got %d", ae.StatusCode)
	}
}

func TestGrpcErrorResourceExhausted(t *testing.T) {
	c := startErrorServer(t, codes.ResourceExhausted, "payload too large")
	_, err := c.Health(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	var tl *TooLargeError
	if !errors.As(err, &tl) {
		t.Fatalf("expected TooLargeError, got %T: %v", err, err)
	}
	if tl.StatusCode != 413 {
		t.Fatalf("expected status 413, got %d", tl.StatusCode)
	}
}

func TestGrpcErrorInternal(t *testing.T) {
	c := startErrorServer(t, codes.Internal, "server error")
	_, err := c.Health(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	var ie *InternalError
	if !errors.As(err, &ie) {
		t.Fatalf("expected InternalError, got %T: %v", err, err)
	}
	if ie.StatusCode != 500 {
		t.Fatalf("expected status 500, got %d", ie.StatusCode)
	}
}

func TestGrpcErrorUnavailable(t *testing.T) {
	c := startErrorServer(t, codes.Unavailable, "network unreachable")
	_, err := c.Health(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	var ne *NetworkError
	if !errors.As(err, &ne) {
		t.Fatalf("expected NetworkError, got %T: %v", err, err)
	}
	if ne.StatusCode != 502 {
		t.Fatalf("expected status 502, got %d", ne.StatusCode)
	}
}

// --- V2-286: WalletService mock + tests ---

type mockWalletService struct {
	pb.UnimplementedWalletServiceServer
}

func (m *mockWalletService) GetAddress(_ context.Context, _ *pb.GetWalletAddressRequest) (*pb.GetWalletAddressResponse, error) {
	return &pb.GetWalletAddressResponse{
		Address: "0xabc1234567890abcdef1234567890abcdef123456",
	}, nil
}

func (m *mockWalletService) GetBalance(_ context.Context, _ *pb.GetWalletBalanceRequest) (*pb.GetWalletBalanceResponse, error) {
	return &pb.GetWalletBalanceResponse{
		Balance:    "1000000000000000000",
		GasBalance: "500000000000000000",
	}, nil
}

func (m *mockWalletService) Approve(_ context.Context, _ *pb.WalletApproveRequest) (*pb.WalletApproveResponse, error) {
	return &pb.WalletApproveResponse{Approved: true}, nil
}

// startUnconfiguredWalletServer returns FailedPrecondition for every wallet
// RPC, matching the daemon's behaviour when no AUTONOMI_WALLET_KEY is set.
type unconfiguredWalletService struct {
	pb.UnimplementedWalletServiceServer
}

func (u *unconfiguredWalletService) GetAddress(_ context.Context, _ *pb.GetWalletAddressRequest) (*pb.GetWalletAddressResponse, error) {
	return nil, status.Error(codes.FailedPrecondition, "wallet not configured — set AUTONOMI_WALLET_KEY")
}

func (u *unconfiguredWalletService) GetBalance(_ context.Context, _ *pb.GetWalletBalanceRequest) (*pb.GetWalletBalanceResponse, error) {
	return nil, status.Error(codes.FailedPrecondition, "wallet not configured — set AUTONOMI_WALLET_KEY")
}

func (u *unconfiguredWalletService) Approve(_ context.Context, _ *pb.WalletApproveRequest) (*pb.WalletApproveResponse, error) {
	return nil, status.Error(codes.FailedPrecondition, "wallet not configured — set AUTONOMI_WALLET_KEY")
}

func startUnconfiguredWalletServer(t *testing.T) *GrpcClient {
	t.Helper()
	lis := bufconn.Listen(bufSize)

	s := grpc.NewServer()
	pb.RegisterWalletServiceServer(s, &unconfiguredWalletService{})

	go func() {
		_ = s.Serve(lis)
	}()
	t.Cleanup(func() { s.Stop() })

	dialer := func(context.Context, string) (net.Conn, error) {
		return lis.Dial()
	}

	c, err := NewGrpcClient("passthrough:///bufconn",
		WithDialOptions(
			grpc.WithContextDialer(dialer),
			grpc.WithTransportCredentials(insecure.NewCredentials()),
		),
	)
	if err != nil {
		t.Fatalf("failed to create grpc client: %v", err)
	}
	t.Cleanup(func() { c.Close() })
	return c
}

func TestGrpcWalletAddress(t *testing.T) {
	c := startMockServer(t)
	r, err := c.WalletAddress(context.Background())
	if err != nil {
		t.Fatalf("WalletAddress: %v", err)
	}
	if r.Address != "0xabc1234567890abcdef1234567890abcdef123456" {
		t.Fatalf("address: got %q", r.Address)
	}
}

func TestGrpcWalletBalance(t *testing.T) {
	c := startMockServer(t)
	r, err := c.WalletBalance(context.Background())
	if err != nil {
		t.Fatalf("WalletBalance: %v", err)
	}
	if r.Balance != "1000000000000000000" {
		t.Fatalf("balance: got %q", r.Balance)
	}
	if r.GasBalance != "500000000000000000" {
		t.Fatalf("gas_balance: got %q", r.GasBalance)
	}
}

func TestGrpcWalletApprove(t *testing.T) {
	c := startMockServer(t)
	if err := c.WalletApprove(context.Background()); err != nil {
		t.Fatalf("WalletApprove: %v", err)
	}
}

// The daemon emits `Status::failed_precondition` for "wallet not configured",
// which antd-go's existing errorFromGrpc maps to *PaymentError. (The semantic
// is a bit off — REST returns 503 for the same case — but matches the
// established gRPC→SDK mapping across all SDKs and is not in V2-286's scope
// to renumber.)
func TestGrpcWalletAddressUnconfiguredReturnsTypedError(t *testing.T) {
	c := startUnconfiguredWalletServer(t)
	_, err := c.WalletAddress(context.Background())
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	var perr *PaymentError
	if !errors.As(err, &perr) {
		t.Fatalf("expected *PaymentError (FailedPrecondition→Payment), got %T: %v", err, err)
	}
}

func TestGrpcFinalizeMerkleUploadMulti(t *testing.T) {
	c := startMockServer(t)
	res, err := c.FinalizeMerkleUploadMulti(context.Background(), "mup1", []string{"0xw1", "", "0xw3"}, false)
	if err != nil {
		t.Fatal(err)
	}
	if res.DataMap != "dm_merkle_multi" {
		t.Fatalf("unexpected data_map: %s", res.DataMap)
	}
	// The mock echoes the count of non-empty winner hashes back.
	if res.ChunksStored != 2 {
		t.Fatalf("expected 2 paid batches echoed, got %d", res.ChunksStored)
	}
}

func TestGrpcPartialUploadMapsToPartialUploadError(t *testing.T) {
	c := startMockServer(t)
	_, err := c.FinalizeMerkleUploadMulti(context.Background(), "partial", []string{"0xw1"}, false)
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	var perr *PartialUploadError
	if !errors.As(err, &perr) {
		t.Fatalf("expected *PartialUploadError (Aborted), got %T: %v", err, err)
	}
	if perr.StatusCode != 502 {
		t.Fatalf("expected status 502, got %d", perr.StatusCode)
	}
	// Counts and the retained hint are parsed from the status message, so
	// the gRPC client matches the REST client's typed error.
	if perr.ChunksStored != 300 || perr.ChunksFailed != 12 || perr.TotalChunks != 312 {
		t.Fatalf("unexpected counts parsed from message: %+v", perr)
	}
	if !perr.Retryable {
		t.Fatalf("expected Retryable from the retained hint: %+v", perr)
	}

	_, err = c.FinalizeMerkleUploadMulti(context.Background(), "partial-final", []string{"0xw1"}, false)
	if !errors.As(err, &perr) {
		t.Fatalf("expected *PartialUploadError, got %T: %v", err, err)
	}
	if perr.Retryable {
		t.Fatalf("no retained hint must read as not retryable: %+v", perr)
	}

	// An ABORTED without the daemon's "Partial upload:" prefix is not a
	// partial upload and must not be reported as one.
	_, err = c.FinalizeMerkleUploadMulti(context.Background(), "aborted-other", []string{"0xw1"}, false)
	if errors.As(err, &perr) {
		t.Fatalf("non-partial ABORTED must not map to PartialUploadError: %v", err)
	}
	var base *AntdError
	if !errors.As(err, &base) || base.StatusCode != int(codes.Aborted) {
		t.Fatalf("expected the generic mapping with the gRPC code, got %T: %v", err, err)
	}

	// Nor is one that merely embeds the prefix: the gate is anchored.
	_, err = c.FinalizeMerkleUploadMulti(context.Background(), "aborted-embedded", []string{"0xw1"}, false)
	if errors.As(err, &perr) {
		t.Fatalf("embedded-marker ABORTED must not map to PartialUploadError: %v", err)
	}
	if !errors.As(err, &base) || base.StatusCode != int(codes.Aborted) {
		t.Fatalf("expected the generic mapping with the gRPC code, got %T: %v", err, err)
	}
}

func TestPrepareResponseToResultMultiBatch(t *testing.T) {
	resp := &pb.PrepareUploadResponse{
		UploadId:    "mb1",
		PaymentType: "merkle",
		MerkleBatches: []*pb.MerkleBatchEntry{
			{
				Depth: 8,
				PoolCommitments: []*pb.PoolCommitmentEntry{{
					PoolHash:   "0xp1",
					Candidates: []*pb.CandidateNodeEntry{{RewardsAddress: "0xr1", Amount: "7"}},
				}},
				MerklePaymentTimestamp: 1712150400,
			},
			{Depth: 6, MerklePaymentTimestamp: 1712150401},
		},
		TotalAmount: "0",
	}
	res := prepareResponseToResult(resp)
	if len(res.MerkleBatches) != 2 {
		t.Fatalf("expected 2 batches, got %d", len(res.MerkleBatches))
	}
	if res.MerkleBatches[0].Depth != 8 || res.MerkleBatches[1].Depth != 6 {
		t.Fatalf("unexpected batch depths: %+v", res.MerkleBatches)
	}
	if res.MerkleBatches[0].PoolCommitments[0].Candidates[0].Amount != "7" {
		t.Fatalf("unexpected candidate amount: %+v", res.MerkleBatches[0])
	}
	// Multi-batch prepares leave the legacy singular fields empty.
	if res.Depth != 0 || len(res.PoolCommitments) != 0 {
		t.Fatalf("legacy fields must stay empty on multi-batch: %+v", res)
	}
}

func TestIsPartialUploadMessageIsAnchored(t *testing.T) {
	cases := []struct {
		msg  string
		want bool
	}{
		{"Partial upload: 1/3 chunks stored, 2 failed", true},
		{"Partial upload: garbled", true}, // the gate only checks the prefix
		{"upstream error: Partial upload: 1/3 chunks stored, 2 failed", false},
		{" Partial upload: 1/3 chunks stored, 2 failed", false},
		{"partial upload: 1/3 chunks stored, 2 failed", false},
		{"", false},
	}
	for _, tc := range cases {
		if got := isPartialUploadMessage(tc.msg); got != tc.want {
			t.Errorf("isPartialUploadMessage(%q) = %v, want %v", tc.msg, got, tc.want)
		}
	}
}

func TestErrorFromGrpcPartialUploadContract(t *testing.T) {
	const hint = " after retries: quorum (paid attempt retained: call finalize again with the same upload_id to store the remainder against the same payment)"
	const over = "18446744073709551616" // 2^64
	cases := []struct {
		name                  string
		msg                   string
		partial               bool
		stored, failed, total uint64
		retryable             bool
	}{
		{"well-formed with hint", "Partial upload: 300/312 chunks stored, 12 failed" + hint, true, 300, 12, 312, true},
		{"well-formed without hint", "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum", true, 300, 12, 312, false},
		{"stored overflow with hint", "Partial upload: " + over + "/312 chunks stored, 12 failed" + hint, true, 0, 0, 0, false},
		{"total overflow with hint", "Partial upload: 300/" + over + " chunks stored, 12 failed" + hint, true, 0, 0, 0, false},
		{"failed overflow with hint", "Partial upload: 300/312 chunks stored, " + over + " failed" + hint, true, 0, 0, 0, false},
		{"pattern miss with hint", "Partial upload: chunks missing" + hint, true, 0, 0, 0, false},
		{"embedded marker", "upstream error: Partial upload: 1/3 chunks stored, 2 failed", false, 0, 0, 0, false},
		{"embedded marker with hint", "upstream error: Partial upload: 1/3 chunks stored, 2 failed" + hint, false, 0, 0, 0, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := errorFromGrpc(status.Error(codes.Aborted, tc.msg))
			var perr *PartialUploadError
			if !tc.partial {
				if errors.As(err, &perr) {
					t.Fatalf("must not map to *PartialUploadError: %+v", perr)
				}
				var base *AntdError
				if !errors.As(err, &base) || base.StatusCode != int(codes.Aborted) || base.Message != tc.msg {
					t.Fatalf("expected the generic ABORTED mapping, got %T: %v", err, err)
				}
				return
			}
			if !errors.As(err, &perr) {
				t.Fatalf("expected *PartialUploadError, got %T: %v", err, err)
			}
			if perr.StatusCode != 502 || perr.Message != tc.msg {
				t.Fatalf("unexpected status/message: %+v", perr)
			}
			if perr.ChunksStored != tc.stored || perr.ChunksFailed != tc.failed || perr.TotalChunks != tc.total || perr.Retryable != tc.retryable {
				t.Fatalf("got (%d, %d, %d, %v), want (%d, %d, %d, %v)",
					perr.ChunksStored, perr.ChunksFailed, perr.TotalChunks, perr.Retryable,
					tc.stored, tc.failed, tc.total, tc.retryable)
			}
		})
	}
}
