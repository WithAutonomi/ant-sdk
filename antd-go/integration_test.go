package antd

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"
)

// integrationClient returns a Client pointed at a live antd daemon.
// It skips the test if the daemon is not reachable.
func integrationClient(t *testing.T) *Client {
	t.Helper()

	url := os.Getenv("ANTD_TEST_URL")
	if url == "" {
		url = "http://127.0.0.1:51105"
	}

	c := NewClient(url, WithTimeout(10*time.Second))

	// Probe health to decide whether to skip.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, err := c.Health(ctx)
	if err != nil {
		t.Skipf("skipping integration test: antd daemon not reachable at %s: %v", url, err)
	}
	return c
}

func TestIntegration_Health(t *testing.T) {
	c := integrationClient(t)
	h, err := c.Health(context.Background())
	if err != nil {
		t.Fatalf("Health failed: %v", err)
	}
	if !h.OK {
		t.Fatal("expected health OK=true")
	}
	if h.Network != "local" {
		t.Fatalf("expected network=local, got %q", h.Network)
	}
}

func TestIntegration_DataPutPublic_NoWallet(t *testing.T) {
	c := integrationClient(t)
	_, err := c.DataPutPublic(context.Background(), []byte("hello"), PaymentModeAuto)
	if err == nil {
		t.Fatal("expected error from DataPutPublic without wallet")
	}
	var svcErr *ServiceUnavailableError
	var netErr *NetworkError
	if !errors.As(err, &svcErr) && !errors.As(err, &netErr) {
		t.Fatalf("expected ServiceUnavailableError or NetworkError, got %T: %v", err, err)
	}
}

func TestIntegration_DataGetPublic_InvalidAddress(t *testing.T) {
	c := integrationClient(t)
	_, err := c.DataGetPublic(context.Background(), "not-a-valid-address")
	if err == nil {
		t.Fatal("expected error for invalid address")
	}
	// Could be 400 (bad address format) or 404 (not found) or 502 (no peers).
	var badReq *BadRequestError
	var notFound *NotFoundError
	var netErr *NetworkError
	var svcErr *ServiceUnavailableError
	if !errors.As(err, &badReq) && !errors.As(err, &notFound) && !errors.As(err, &netErr) && !errors.As(err, &svcErr) {
		t.Fatalf("expected BadRequestError, NotFoundError, NetworkError, or ServiceUnavailableError, got %T: %v", err, err)
	}
}

func TestIntegration_WalletAddress_NoWallet(t *testing.T) {
	c := integrationClient(t)
	_, err := c.WalletAddress(context.Background())
	if err == nil {
		t.Fatal("expected error from WalletAddress without wallet")
	}
	var svcErr *ServiceUnavailableError
	if !errors.As(err, &svcErr) {
		t.Fatalf("expected ServiceUnavailableError, got %T: %v", err, err)
	}
}

func TestIntegration_WalletBalance_NoWallet(t *testing.T) {
	c := integrationClient(t)
	_, err := c.WalletBalance(context.Background())
	if err == nil {
		t.Fatal("expected error from WalletBalance without wallet")
	}
	var svcErr *ServiceUnavailableError
	if !errors.As(err, &svcErr) {
		t.Fatalf("expected ServiceUnavailableError, got %T: %v", err, err)
	}
}

func TestIntegration_WalletApprove_NoWallet(t *testing.T) {
	c := integrationClient(t)
	err := c.WalletApprove(context.Background())
	if err == nil {
		t.Fatal("expected error from WalletApprove without wallet")
	}
	var svcErr *ServiceUnavailableError
	if !errors.As(err, &svcErr) {
		t.Fatalf("expected ServiceUnavailableError, got %T: %v", err, err)
	}
}

func TestIntegration_FinalizeUpload_InvalidID(t *testing.T) {
	c := integrationClient(t)
	_, err := c.FinalizeUpload(context.Background(), "nonexistent-upload-id", map[string]string{"q": "t"}, false)
	if err == nil {
		t.Fatal("expected error for nonexistent upload_id")
	}
	var notFound *NotFoundError
	var badReq *BadRequestError
	var svcErr *ServiceUnavailableError
	if !errors.As(err, &notFound) && !errors.As(err, &badReq) && !errors.As(err, &svcErr) {
		t.Fatalf("expected NotFoundError, BadRequestError, or ServiceUnavailableError, got %T: %v", err, err)
	}
}

func TestIntegration_DataCost_NoPeers(t *testing.T) {
	c := integrationClient(t)
	_, err := c.DataCost(context.Background(), []byte("test data"), PaymentModeAuto)
	if err == nil {
		t.Fatal("expected error from DataCost without peers")
	}
	// No peers means 502 (NetworkError) or 503 (ServiceUnavailableError).
	var netErr *NetworkError
	var svcErr *ServiceUnavailableError
	if !errors.As(err, &netErr) && !errors.As(err, &svcErr) {
		t.Fatalf("expected NetworkError or ServiceUnavailableError, got %T: %v", err, err)
	}
}
