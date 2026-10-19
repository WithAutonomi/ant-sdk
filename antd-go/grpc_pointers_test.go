package antd

import (
	"context"
	"errors"
	"net"
	"testing"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"

	pb "github.com/WithAutonomi/ant-sdk/antd-go/proto/antd/v1"
)

// mockPointerService answers like antd: owner "final", "conflict", "short"
// and "retained" fail the way the daemon does, with the error code in the
// trailers; owner "pay" fails as an older daemon would, with no code.
type mockPointerService struct {
	pb.UnimplementedPointerServiceServer
}

func pointerFailure(ctx context.Context, owner string) error {
	failures := map[string]struct {
		code    codes.Code
		antd    string
		message string
	}{
		"final":    {codes.FailedPrecondition, "POINTER_FINAL", "Pointer is final: x"},
		"forked":   {codes.FailedPrecondition, "POINTER_FORKED", "Pointer is forked: x"},
		"conflict": {codes.Aborted, "CONFLICT", "Conflict: x"},
		"short":    {codes.Unavailable, "CLOSE_GROUP_SHORTFALL", "Close group shortfall: only 3 answered"},
		"retained": {codes.Unavailable, "CLOSE_GROUP_SHORTFALL", "Close group shortfall: stored on 4 of 5 (paid attempt retained: call finalize again with the same upload_id to store it against the same payment)"},
		"pay":      {codes.FailedPrecondition, "", "Payment error: x"},
	}
	f, ok := failures[owner]
	if !ok {
		return nil
	}
	if f.antd != "" {
		_ = grpc.SetTrailer(ctx, metadata.Pairs("x-antd-error-code", f.antd))
	}
	return status.Error(f.code, f.message)
}

func (m *mockPointerService) ListKeys(context.Context, *pb.ListPointerKeysRequest) (*pb.ListPointerKeysResponse, error) {
	return &pb.ListPointerKeysResponse{Keys: []*pb.PointerKey{{Address: "aa"}, {Address: "bb"}}}, nil
}

func (m *mockPointerService) Update(ctx context.Context, req *pb.PointerWriteRequest) (*pb.PointerWriteResponse, error) {
	if err := pointerFailure(ctx, req.GetOwner()); err != nil {
		return nil, err
	}
	return &pb.PointerWriteResponse{Address: req.GetOwner(), StateId: "ss", Counter: "2"}, nil
}

func (m *mockPointerService) Finalize(ctx context.Context, req *pb.FinalizePointerRequest) (*pb.FinalizePointerResponse, error) {
	if err := pointerFailure(ctx, req.GetUploadId()); err != nil {
		return nil, err
	}
	return &pb.FinalizePointerResponse{Address: "aa", StateId: "ss", Counter: "0"}, nil
}

func (m *mockPointerService) Get(context.Context, *pb.GetPointerRequest) (*pb.PointerRecord, error) {
	return &pb.PointerRecord{
		Address: "aa", Owner: "pk", Counter: "18446744073709551615", Kind: "pointer", KindTag: 1,
		Target: "bb", StateId: "ss", IsFinal: true, TransferredTo: "bb",
	}, nil
}

func (m *mockPointerService) Finality(context.Context, *pb.PointerFinalityRequest) (*pb.PointerFinality, error) {
	return &pb.PointerFinality{
		Address: "aa", Group: 7, Answered: 7, Status: "forked",
		States: []*pb.PointerFinalState{
			{StateId: "s1", Kind: "pointer", KindTag: 1, Target: "t1", Holders: 4, TransferredTo: "t1"},
			{StateId: "s2", Kind: "chunk", Target: "t2", Holders: 2},
		},
		Majority: &pb.PointerFinalState{StateId: "s1", Kind: "pointer", KindTag: 1, Target: "t1", Holders: 4, TransferredTo: "t1"},
	}, nil
}

func (m *mockPointerService) Prepare(_ context.Context, req *pb.PreparePointerRequest) (*pb.PreparePointerResponse, error) {
	return &pb.PreparePointerResponse{
		UploadId: "up", Op: req.GetOp(), Address: req.GetOwner(), StateId: "ss", Counter: "1",
		PaymentType: "wave_batch", TotalAmount: "5",
		Payments: []*pb.PaymentEntry{{QuoteHash: "0xq", RewardsAddress: "0xr", Amount: "5"}},
	}, nil
}

func startPointerServer(t *testing.T) *GrpcClient {
	t.Helper()
	lis := bufconn.Listen(bufSize)
	s := grpc.NewServer()
	pb.RegisterPointerServiceServer(s, &mockPointerService{})
	go func() { _ = s.Serve(lis) }()
	t.Cleanup(func() { s.Stop() })
	c, err := NewGrpcClient("passthrough:///bufconn", WithDialOptions(
		grpc.WithContextDialer(func(context.Context, string) (net.Conn, error) { return lis.Dial() }),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	))
	if err != nil {
		t.Fatalf("failed to create grpc client: %v", err)
	}
	t.Cleanup(func() { c.Close() })
	return c
}

func TestGrpcPointerKeysAndGet(t *testing.T) {
	c := startPointerServer(t)
	keys, err := c.PointerKeys(context.Background())
	if err != nil || len(keys) != 2 || keys[1] != "bb" {
		t.Fatalf("keys = %v, %v", keys, err)
	}
	r, err := c.PointerGet(context.Background(), "aa")
	if err != nil {
		t.Fatal(err)
	}
	if r.Counter != PointerFinalCounter || !r.Final || r.TransferredTo != "bb" {
		t.Fatalf("record = %+v", r)
	}
}

func TestGrpcPointerFinalityForked(t *testing.T) {
	c := startPointerServer(t)
	f, err := c.PointerFinality(context.Background(), "aa")
	if err != nil {
		t.Fatal(err)
	}
	if f.Status != PointerForked || f.Counter != nil || f.State != nil || len(f.States) != 2 ||
		f.Majority == nil || f.Majority.TransferredTo != "t1" {
		t.Fatalf("finality = %+v", f)
	}
}

func TestGrpcPointerPrepare(t *testing.T) {
	c := startPointerServer(t)
	p, err := c.PointerPrepare(context.Background(), PointerPrepareRequest{Owner: "aa", Op: PointerOpUpdate, Target: "tt"})
	if err != nil {
		t.Fatal(err)
	}
	if p.Op != PointerOpUpdate || p.Counter != 1 || len(p.Payments) != 1 {
		t.Fatalf("prepare = %+v", p)
	}
}

func TestGrpcPointerErrorsMapByTrailerCode(t *testing.T) {
	c := startPointerServer(t)
	cases := map[string]func(error) bool{
		"final":    func(e error) bool { var t *PointerFinalError; return errors.As(e, &t) && t.StatusCode == 409 },
		"forked":   func(e error) bool { var t *ForkError; return errors.As(e, &t) },
		"conflict": func(e error) bool { var t *ConflictError; return errors.As(e, &t) },
		"short": func(e error) bool {
			var t *CloseGroupShortfallError
			return errors.As(e, &t) && !t.Retryable && t.StatusCode == 503
		},
		// Without the trailer a daemon's FAILED_PRECONDITION is still a payment error.
		"pay": func(e error) bool { var t *PaymentError; return errors.As(e, &t) },
	}
	for owner, check := range cases {
		_, err := c.PointerUpdate(context.Background(), owner, "tt", "")
		if err == nil || !check(err) {
			t.Errorf("%s: got %T %v", owner, err, err)
		}
	}

	_, err := c.PointerFinalize(context.Background(), "retained", nil)
	var short *CloseGroupShortfallError
	if !errors.As(err, &short) || !short.Retryable {
		t.Fatalf("a finalize that kept the paid state must say so: %T %v", err, err)
	}
}
