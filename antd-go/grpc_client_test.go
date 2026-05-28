package antd

import (
	"context"
	"errors"
	"net"
	"testing"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"

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
	lis := bufconn.Listen(bufSize)

	s := grpc.NewServer()
	pb.RegisterHealthServiceServer(s, &mockHealthService{})
	pb.RegisterDataServiceServer(s, &mockDataService{})
	pb.RegisterChunkServiceServer(s, &mockChunkService{})
	pb.RegisterFileServiceServer(s, &mockFileService{})
	pb.RegisterWalletServiceServer(s, &mockWalletService{})

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
