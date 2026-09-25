package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	antd "github.com/WithAutonomi/ant-sdk/antd-go"
)

func init() {
	// Keep the backoff real but short so the suite stays fast.
	retryBackoffUnit = 5 * time.Millisecond
}

// partialBody is what antd returns for a post-payment storage shortfall.
func partialBody(stored, failed, total uint64, retryable bool) map[string]any {
	return map[string]any{
		"error":         "Partial upload: chunks missing",
		"code":          "PARTIAL_UPLOAD",
		"chunks_stored": stored,
		"chunks_failed": failed,
		"total_chunks":  total,
		"retryable":     retryable,
	}
}

// finalizeServer serves /v1/upload/finalize from a scripted list of
// responses, one per call, and records every request body so a test can
// prove the retry reuses the same arguments.
func finalizeServer(t *testing.T, responses []map[string]any) (*httptest.Server, *atomic.Int32, *[]string) {
	t.Helper()
	var calls atomic.Int32
	bodies := &[]string{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/upload/finalize" {
			http.NotFound(w, r)
			return
		}
		raw, _ := io.ReadAll(r.Body)
		*bodies = append(*bodies, string(raw))
		i := int(calls.Add(1)) - 1
		if i >= len(responses) {
			t.Errorf("unexpected finalize call #%d", i+1)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		resp := responses[i]
		w.Header().Set("Content-Type", "application/json")
		if resp["code"] == "PARTIAL_UPLOAD" {
			w.WriteHeader(http.StatusBadGateway)
		}
		_ = json.NewEncoder(w).Encode(resp)
	}))
	t.Cleanup(srv.Close)
	return srv, &calls, bodies
}

func TestFinalizeWithRetryResumesSameArgumentsUntilComplete(t *testing.T) {
	srv, calls, bodies := finalizeServer(t, []map[string]any{
		partialBody(300, 12, 312, true),
		partialBody(308, 4, 312, true),
		{"data_map": "aa", "data_map_address": "bb", "chunks_stored": 312},
	})
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	tx := map[string]string{"0xq1": "0xt1"}

	res, err := finalizeWithRetry(ctx, antd.NewClient(srv.URL), "u1", tx, false)
	if err != nil {
		t.Fatalf("expected recovery, got %v", err)
	}
	if res.ChunksStored != 312 || calls.Load() != 3 {
		t.Fatalf("expected 3 calls ending complete, got calls=%d res=%+v", calls.Load(), res)
	}
	// Every retry must carry the same upload_id and tx map: no re-prepare,
	// no fresh quote hashes, no second payment.
	for i, b := range *bodies {
		if !strings.Contains(b, `"upload_id":"u1"`) || !strings.Contains(b, `"0xq1":"0xt1"`) {
			t.Fatalf("call %d did not reuse the original arguments: %s", i+1, b)
		}
	}
}

func TestFinalizeWithRetryStopsWhenFailedCountStopsShrinking(t *testing.T) {
	srv, calls, _ := finalizeServer(t, []map[string]any{
		partialBody(300, 12, 312, true),
		partialBody(300, 12, 312, true), // no progress: stuck
		{"data_map": "never reached"},
	})
	_, err := finalizeWithRetry(context.Background(), antd.NewClient(srv.URL), "u1", map[string]string{}, false)
	if err == nil {
		t.Fatal("expected a stuck error")
	}
	var perr *antd.PartialUploadError
	if !errors.As(err, &perr) || !perr.Retryable || !perr.RetentionKnown {
		t.Fatalf("stuck error must wrap the retained partial upload: %v", err)
	}
	if !strings.Contains(err.Error(), "stuck") || !strings.Contains(err.Error(), "upload_id u1") {
		t.Fatalf("stuck error should name the retained upload: %v", err)
	}
	if calls.Load() != 2 {
		t.Fatalf("expected exactly 2 calls, got %d", calls.Load())
	}
}

func TestFinalizeWithRetryCapsAttempts(t *testing.T) {
	// Shrinking every time but never completing: the cap must end it.
	responses := make([]map[string]any, 0, 8)
	for i := uint64(0); i < 8; i++ {
		responses = append(responses, partialBody(300+i, 12-i, 312, true))
	}
	srv, calls, _ := finalizeServer(t, responses)
	_, err := finalizeWithRetry(context.Background(), antd.NewClient(srv.URL), "u1", map[string]string{}, false)
	if err == nil || !strings.Contains(err.Error(), "5 attempt(s)") {
		t.Fatalf("expected the 5-attempt cap, got %v", err)
	}
	if calls.Load() != 5 {
		t.Fatalf("expected 5 calls, got %d", calls.Load())
	}
}

func TestFinalizeWithRetryReturnsNonRetryablePartialUntouched(t *testing.T) {
	srv, calls, _ := finalizeServer(t, []map[string]any{
		partialBody(300, 12, 312, false), // daemon confirms nothing retained (unpaid merkle batches, daemon wallet)
	})
	_, err := finalizeWithRetry(context.Background(), antd.NewClient(srv.URL), "u1", map[string]string{}, false)
	var perr *antd.PartialUploadError
	if !errors.As(err, &perr) || perr.Retryable || !perr.RetentionKnown {
		t.Fatalf("expected the known non-retryable partial upload as-is, got %v", err)
	}
	if _, ok := err.(*antd.PartialUploadError); !ok {
		t.Fatalf("a confirmed non-retained partial must be returned untouched, got %T", err)
	}
	if calls.Load() != 1 {
		t.Fatalf("must not retry a non-retryable partial, got %d calls", calls.Load())
	}
}

func TestFinalizeWithRetryStopsOnUnknownRetention(t *testing.T) {
	// A missing (daemon older than 0.14.0) or malformed retryable flag means
	// retention is unknown: the daemon may still hold the paid attempt, so
	// the loop must stop on the first call, return the typed error, and
	// point the caller at the upload_id rather than a re-prepare.
	for name, retryable := range map[string]any{"missing": nil, "null": nil, "string": "true", "number": 1} {
		t.Run(name, func(t *testing.T) {
			body := partialBody(300, 12, 312, false)
			if name == "missing" {
				delete(body, "retryable")
			} else {
				body["retryable"] = retryable
			}
			srv, calls, _ := finalizeServer(t, []map[string]any{body, {"data_map": "never reached"}})
			_, err := finalizeWithRetry(context.Background(), antd.NewClient(srv.URL), "u1", map[string]string{"0xq1": "0xt1"}, false)
			var perr *antd.PartialUploadError
			if !errors.As(err, &perr) || perr.RetentionKnown || perr.Retryable {
				t.Fatalf("expected the typed partial with unknown retention, got %v", err)
			}
			if calls.Load() != 1 {
				t.Fatalf("must stop on unknown retention, got %d calls", calls.Load())
			}
			if !strings.Contains(err.Error(), "upload_id u1") || !strings.Contains(err.Error(), "reconcile") {
				t.Fatalf("unknown-retention error should keep the upload_id and say to reconcile: %v", err)
			}
		})
	}
}

func TestFinalizeWithRetryPreservesPaidAttemptOnCancellation(t *testing.T) {
	srv, _, _ := finalizeServer(t, []map[string]any{
		partialBody(300, 12, 312, true),
		{"data_map": "never reached"},
	})
	// The first finalize returns a retained partial quickly; the deadline
	// then expires during the backoff before the second attempt.
	retryBackoffUnit = 2 * time.Second
	defer func() { retryBackoffUnit = 5 * time.Millisecond }()
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	_, err := finalizeWithRetry(ctx, antd.NewClient(srv.URL), "u1", map[string]string{}, false)
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("cancellation identity must survive: %v", err)
	}
	var perr *antd.PartialUploadError
	if !errors.As(err, &perr) || !perr.Retryable || perr.ChunksStored != 300 {
		t.Fatalf("the retained partial upload must survive cancellation for errors.As: %v", err)
	}
	if !strings.Contains(err.Error(), "upload_id u1") || !strings.Contains(err.Error(), "300/312") {
		t.Fatalf("cancellation must keep the retained-attempt context: %v", err)
	}
}
