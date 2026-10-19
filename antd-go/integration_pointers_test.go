package antd

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"
)

// pointerOwners returns the two owner addresses a live pointer test may
// write, from ANTD_TEST_POINTER_OWNERS ("addr1,addr2"). The daemon at
// ANTD_TEST_URL must hold their keys (--pointer-keys) and a wallet, and both
// pointers must be unwritten: the test creates them and hands the first over
// to the second, which leaves the first final for good. Skips when unset.
func pointerOwners(t *testing.T) (string, string) {
	t.Helper()
	owners := strings.Split(os.Getenv("ANTD_TEST_POINTER_OWNERS"), ",")
	if len(owners) != 2 || owners[0] == "" || owners[1] == "" {
		t.Skip("skipping live pointer test: set ANTD_TEST_POINTER_OWNERS to two unwritten owner addresses")
	}
	return owners[0], owners[1]
}

func TestIntegration_Pointers(t *testing.T) {
	a, b := pointerOwners(t)
	c := integrationClient(t)
	c.http.Timeout = 10 * time.Minute
	ctx := context.Background()

	targets := make([]string, 3)
	for i, text := range []string{"go pointer target one", "go pointer target two", "go recipient target"} {
		put, err := c.DataPutPublic(ctx, []byte(text), PaymentModeAuto)
		if err != nil {
			t.Fatalf("DataPutPublic: %v", err)
		}
		targets[i] = put.Address
	}

	if _, err := c.PointerGet(ctx, a); !errors.As(err, new(*NotFoundError)) {
		t.Fatalf("an unwritten pointer must read as NotFound, got %T %v", err, err)
	}
	w, err := c.PointerCreate(ctx, a, targets[0], "")
	if err != nil || w.Counter != 0 {
		t.Fatalf("PointerCreate: %+v %v", w, err)
	}
	if _, err := c.PointerCreate(ctx, a, targets[1], ""); !errors.As(err, new(*AlreadyExistsError)) {
		t.Fatalf("a second create must be AlreadyExists, got %T %v", err, err)
	}
	if w, err = c.PointerUpdate(ctx, a, targets[1], ""); err != nil || w.Counter != 1 {
		t.Fatalf("PointerUpdate: %+v %v", w, err)
	}
	res, err := c.PointerResolve(ctx, a)
	if err != nil || res.Target != targets[1] {
		t.Fatalf("PointerResolve: %+v %v", res, err)
	}
	data, err := c.DataGetPublic(ctx, res.Target)
	if err != nil || string(data) != "go pointer target two" {
		t.Fatalf("data through the pointer: %q %v", data, err)
	}
	f, err := c.PointerFinality(ctx, a)
	if err != nil || f.Status != PointerOpen || f.Counter == nil || *f.Counter != 1 {
		t.Fatalf("PointerFinality: %+v %v", f, err)
	}

	if _, err := c.PointerCreate(ctx, b, targets[2], ""); err != nil {
		t.Fatalf("PointerCreate recipient: %v", err)
	}
	tr, err := c.PointerTransfer(ctx, a, b)
	if err != nil || tr.Finality == nil || tr.Finality.Status != PointerFinal || tr.Finality.TransferredTo != b {
		t.Fatalf("PointerTransfer: %+v %v", tr, err)
	}
	r, err := c.PointerGet(ctx, a)
	if err != nil || !r.Final || r.Counter != PointerFinalCounter || r.TransferredTo != b {
		t.Fatalf("PointerGet after transfer: %+v %v", r, err)
	}
	ctl, err := c.PointerController(ctx, a)
	if err != nil || ctl.Pointer != b || len(ctl.Transfers) != 1 {
		t.Fatalf("PointerController: %+v %v", ctl, err)
	}
	if _, err := c.PointerUpdate(ctx, a, targets[0], ""); !errors.As(err, new(*PointerFinalError)) {
		t.Fatalf("updating a final pointer must be PointerFinal, got %T %v", err, err)
	}

	// The same daemon over gRPC, when ANTD_TEST_GRPC is set.
	target := os.Getenv("ANTD_TEST_GRPC")
	if target == "" {
		return
	}
	g, err := NewGrpcClient(target, WithGrpcTimeout(10*time.Minute))
	if err != nil {
		t.Fatalf("NewGrpcClient: %v", err)
	}
	defer g.Close()
	gr, err := g.PointerGet(ctx, a)
	if err != nil || !gr.Final || gr.TransferredTo != b {
		t.Fatalf("gRPC PointerGet: %+v %v", gr, err)
	}
	gw, err := g.PointerUpdate(ctx, b, targets[0], "")
	if err != nil || gw.Counter != 1 {
		t.Fatalf("gRPC PointerUpdate: %+v %v", gw, err)
	}
	gres, err := g.PointerResolve(ctx, a)
	if err != nil || gres.Target != targets[0] {
		t.Fatalf("gRPC PointerResolve follows the recipient: %+v %v", gres, err)
	}
	if _, err := g.PointerUpdate(ctx, a, targets[1], ""); !errors.As(err, new(*PointerFinalError)) {
		t.Fatalf("gRPC update of a final pointer must be PointerFinal, got %T %v", err, err)
	}
}
