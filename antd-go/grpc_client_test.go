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
		Status:  "ok",
		Network: "local",
	}, nil
}

// mockDataService implements pb.DataServiceServer.
type mockDataService struct {
	pb.UnimplementedDataServiceServer
}

func (m *mockDataService) PutPublic(_ context.Context, _ *pb.PutPublicDataRequest) (*pb.PutPublicDataResponse, error) {
	return &pb.PutPublicDataResponse{
		Cost:    &pb.Cost{AttoTokens: "100"},
		Address: "abc123",
	}, nil
}

func (m *mockDataService) GetPublic(_ context.Context, _ *pb.GetPublicDataRequest) (*pb.GetPublicDataResponse, error) {
	return &pb.GetPublicDataResponse{Data: []byte("hello")}, nil
}

func (m *mockDataService) PutPrivate(_ context.Context, _ *pb.PutPrivateDataRequest) (*pb.PutPrivateDataResponse, error) {
	return &pb.PutPrivateDataResponse{
		Cost:    &pb.Cost{AttoTokens: "200"},
		DataMap: "dm123",
	}, nil
}

func (m *mockDataService) GetPrivate(_ context.Context, _ *pb.GetPrivateDataRequest) (*pb.GetPrivateDataResponse, error) {
	return &pb.GetPrivateDataResponse{Data: []byte("secret")}, nil
}

func (m *mockDataService) GetCost(_ context.Context, _ *pb.DataCostRequest) (*pb.Cost, error) {
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

func (m *mockFileService) UploadPublic(_ context.Context, _ *pb.UploadFileRequest) (*pb.UploadPublicResponse, error) {
	return &pb.UploadPublicResponse{
		Address:         "file1",
		StorageCostAtto: "1000",
		GasCostWei:      "42",
		ChunksStored:    3,
		PaymentModeUsed: "auto",
	}, nil
}

func (m *mockFileService) DownloadPublic(_ context.Context, _ *pb.DownloadPublicRequest) (*pb.DownloadResponse, error) {
	return &pb.DownloadResponse{}, nil
}

func (m *mockFileService) DirUploadPublic(_ context.Context, _ *pb.UploadFileRequest) (*pb.UploadPublicResponse, error) {
	return &pb.UploadPublicResponse{
		Address:         "dir1",
		StorageCostAtto: "2000",
		GasCostWei:      "100",
		ChunksStored:    5,
		PaymentModeUsed: "merkle",
	}, nil
}

func (m *mockFileService) DirDownloadPublic(_ context.Context, _ *pb.DownloadPublicRequest) (*pb.DownloadResponse, error) {
	return &pb.DownloadResponse{}, nil
}

func (m *mockFileService) GetFileCost(_ context.Context, _ *pb.FileCostRequest) (*pb.Cost, error) {
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

	go func() {
		if err := s.Serve(lis); err != nil {
			// Server stopped, expected during test cleanup.
		}
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
		if err := s.Serve(lis); err != nil {
			// Server stopped.
		}
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
}

func TestGrpcDataPutPublic(t *testing.T) {
	c := startMockServer(t)
	put, err := c.DataPutPublic(context.Background(), []byte("hello"))
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "abc123" || put.Cost != "100" {
		t.Fatalf("unexpected put: %+v", put)
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

func TestGrpcDataPutPrivate(t *testing.T) {
	c := startMockServer(t)
	put, err := c.DataPutPrivate(context.Background(), []byte("secret"))
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "dm123" || put.Cost != "200" {
		t.Fatalf("unexpected put: %+v", put)
	}
}

func TestGrpcDataGetPrivate(t *testing.T) {
	c := startMockServer(t)
	data, err := c.DataGetPrivate(context.Background(), "dm123")
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "secret" {
		t.Fatalf("unexpected data: %s", data)
	}
}

func TestGrpcDataCost(t *testing.T) {
	c := startMockServer(t)
	est, err := c.DataCost(context.Background(), []byte("test"))
	if err != nil {
		t.Fatal(err)
	}
	if est.Cost != "50" || est.FileSize != 4 || est.ChunkCount != 3 ||
		est.EstimatedGasCostWei != "150000000000000" || est.PaymentMode != "single" {
		t.Fatalf("unexpected estimate: %+v", est)
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

func TestGrpcFileUploadPublic(t *testing.T) {
	c := startMockServer(t)
	put, err := c.FileUploadPublic(context.Background(), "/tmp/test.txt")
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "file1" || put.StorageCostAtto != "1000" || put.GasCostWei != "42" || put.ChunksStored != 3 || put.PaymentModeUsed != "auto" {
		t.Fatalf("unexpected file upload: %+v", put)
	}
}

func TestGrpcFileDownloadPublic(t *testing.T) {
	c := startMockServer(t)
	err := c.FileDownloadPublic(context.Background(), "file1", "/tmp/out.txt")
	if err != nil {
		t.Fatal(err)
	}
}

func TestGrpcDirUploadPublic(t *testing.T) {
	c := startMockServer(t)
	put, err := c.DirUploadPublic(context.Background(), "/tmp/mydir")
	if err != nil {
		t.Fatal(err)
	}
	if put.Address != "dir1" || put.StorageCostAtto != "2000" || put.GasCostWei != "100" || put.ChunksStored != 5 || put.PaymentModeUsed != "merkle" {
		t.Fatalf("unexpected dir upload: %+v", put)
	}
}

func TestGrpcDirDownloadPublic(t *testing.T) {
	c := startMockServer(t)
	err := c.DirDownloadPublic(context.Background(), "dir1", "/tmp/outdir")
	if err != nil {
		t.Fatal(err)
	}
}

func TestGrpcFileCost(t *testing.T) {
	c := startMockServer(t)
	est, err := c.FileCost(context.Background(), "/tmp/test.txt", true)
	if err != nil {
		t.Fatal(err)
	}
	if est.Cost != "1000" || est.FileSize != 4096 || est.ChunkCount != 3 ||
		est.EstimatedGasCostWei != "150000000000000" || est.PaymentMode != "auto" {
		t.Fatalf("unexpected estimate: %+v", est)
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
