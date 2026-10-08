package antd

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/http/httptest"
	"testing"

	pb "github.com/WithAutonomi/ant-sdk/antd-go/proto/antd/v1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

func TestRangeHeader(t *testing.T) {
	for _, tc := range []struct {
		offset, length int64
		want           string
	}{
		{0, 10, "bytes=0-9"},
		{5, 1, "bytes=5-5"},
		{7, RangeToEnd, "bytes=7-"},
		{1, math.MaxInt64, "bytes=1-"},
	} {
		got, err := rangeHeader(tc.offset, tc.length)
		if err != nil || got != tc.want {
			t.Errorf("rangeHeader(%d, %d) = %q, %v; want %q", tc.offset, tc.length, got, err, tc.want)
		}
	}
	for _, tc := range [][2]int64{{-1, 10}, {0, 0}, {0, -2}} {
		if _, err := rangeHeader(tc[0], tc[1]); err == nil {
			t.Errorf("rangeHeader(%d, %d) accepted an invalid range", tc[0], tc[1])
		}
	}
}

func TestParseContentRange(t *testing.T) {
	r, err := parseContentRange("bytes 100-199/1000")
	if err != nil || r.Offset != 100 || r.Length != 100 || r.Size != 1000 {
		t.Fatalf("got %+v, %v", r, err)
	}
	for _, bad := range []string{"", "bytes */1000", "bytes 5-4/10", "bytes 0-10/10", "items 0-1/2", "bytes 0-1"} {
		if _, err := parseContentRange(bad); err == nil {
			t.Errorf("parseContentRange(%q) accepted a malformed value", bad)
		}
	}
	if unsatisfiedSize("bytes */1234") != 1234 || unsatisfiedSize("") != -1 {
		t.Error("unsatisfiedSize")
	}
}

// rangeServer serves payload on both stream routes the way the daemon does:
// 206 + Content-Range for a satisfiable Range, 416 + "bytes */size" past the
// end. legacy makes it ignore Range and answer 200, like an old daemon.
func rangeServer(t *testing.T, payload string, legacy bool) (*Client, *string) {
	t.Helper()
	var gotRange string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotRange = r.Header.Get("Range")
		if legacy {
			_, _ = io.WriteString(w, payload)
			return
		}
		var start, last int64
		size := int64(len(payload))
		if n, _ := fmt.Sscanf(gotRange, "bytes=%d-%d", &start, &last); n == 1 {
			last = size - 1
		}
		if start >= size {
			w.Header().Set("Content-Range", fmt.Sprintf("bytes */%d", size))
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusRequestedRangeNotSatisfiable)
			_, _ = io.WriteString(w, `{"error":"Range not satisfiable","code":"RANGE_NOT_SATISFIABLE"}`)
			return
		}
		last = min(last, size-1)
		w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, last, size))
		w.WriteHeader(http.StatusPartialContent)
		_, _ = io.WriteString(w, payload[start:last+1])
	}))
	t.Cleanup(srv.Close)
	return NewClient(srv.URL), &gotRange
}

func readRange(t *testing.T, r *RangeReader, err error) string {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()
	data, err := io.ReadAll(r)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestDataStreamRange(t *testing.T) {
	c, gotRange := rangeServer(t, "0123456789", false)
	r, err := c.DataStreamRange(context.Background(), "dm", 2, 3)
	if got := readRange(t, r, err); got != "234" || *gotRange != "bytes=2-4" {
		t.Fatalf("got %q with Range %q", got, *gotRange)
	}
	if r.Offset != 2 || r.Length != 3 || r.Size != 10 {
		t.Fatalf("unexpected range metadata %+v", r)
	}

	// Clamped past the end, and to the end.
	r, err = c.DataStreamPublicRange(context.Background(), "addr", 8, 100)
	if got := readRange(t, r, err); got != "89" || r.Length != 2 {
		t.Fatalf("clamped: got %q, %+v", got, r)
	}
	r, err = c.DataStreamRange(context.Background(), "dm", 7, RangeToEnd)
	if got := readRange(t, r, err); got != "789" || *gotRange != "bytes=7-" {
		t.Fatalf("to end: got %q with Range %q", got, *gotRange)
	}
}

func TestDataStreamRangeNotSatisfiable(t *testing.T) {
	c, _ := rangeServer(t, "0123456789", false)
	_, err := c.DataStreamRange(context.Background(), "dm", 10, 1)
	var rerr *RangeNotSatisfiableError
	if !errors.As(err, &rerr) || rerr.Size != 10 || rerr.StatusCode != 416 {
		t.Fatalf("want *RangeNotSatisfiableError with Size 10, got %#v", err)
	}
}

func TestDataStreamRangeRejectsIgnoredRange(t *testing.T) {
	c, _ := rangeServer(t, "0123456789", true)
	if _, err := c.DataStreamRange(context.Background(), "dm", 2, 3); !errors.Is(err, errNoRangeSupport) {
		t.Fatalf("a 200 must not pass for a range: got %v", err)
	}
}

func TestDataStreamRangeValidatesBeforeSending(t *testing.T) {
	c, gotRange := rangeServer(t, "0123456789", false)
	if _, err := c.DataStreamRange(context.Background(), "dm", 0, 0); err == nil || *gotRange != "" {
		t.Fatalf("zero length must fail client-side: err %v, sent Range %q", err, *gotRange)
	}
}

// serveMockRange answers a ranged mock stream like the daemon: x-content-range
// metadata and only the requested bytes, or OUT_OF_RANGE past the end. It
// reports whether the request was ranged. The data map / address "legacy"
// ignores the range, like an old daemon.
func serveMockRange(payload string, key string, offset, length *uint64, srv grpc.ServerStreamingServer[pb.DataChunk]) (bool, error) {
	if (offset == nil && length == nil) || key == "legacy" {
		return false, nil
	}
	size := uint64(len(payload))
	start := uint64(0)
	if offset != nil {
		start = *offset
	}
	if start >= size {
		return true, status.Errorf(codes.OutOfRange, "Range not satisfiable: the object is %d bytes", size)
	}
	end := size
	if length != nil {
		end = min(start+*length, size)
	}
	_ = srv.SetHeader(metadata.Pairs(
		"x-content-length", fmt.Sprint(end-start),
		"x-content-range", fmt.Sprintf("bytes %d-%d/%d", start, end-1, size),
	))
	// One byte per frame, so the reader's frame buffering is exercised.
	for i := start; i < end; i++ {
		if err := srv.Send(&pb.DataChunk{Kind: &pb.DataChunk_Data{Data: []byte{payload[i]}}}); err != nil {
			return true, err
		}
	}
	return true, nil
}

func TestGrpcDataStreamRange(t *testing.T) {
	c := startMockServer(t)
	r, err := c.DataStreamRange(context.Background(), "dm123", 1, 3)
	if got := readRange(t, r, err); got != "ecr" || r.Offset != 1 || r.Length != 3 || r.Size != 6 {
		t.Fatalf("got %q, %+v", got, r)
	}
	r, err = c.DataStreamPublicRange(context.Background(), "abc123", 3, RangeToEnd)
	if got := readRange(t, r, err); got != "lo" || r.Size != 5 {
		t.Fatalf("public to end: got %q, %+v", got, r)
	}
}

func TestGrpcDataStreamRangeOutOfRange(t *testing.T) {
	c := startMockServer(t)
	_, err := c.DataStreamRange(context.Background(), "dm123", 6, RangeToEnd)
	var rerr *RangeNotSatisfiableError
	if !errors.As(err, &rerr) || rerr.StatusCode != 416 {
		t.Fatalf("want *RangeNotSatisfiableError, got %#v", err)
	}
}

func TestGrpcDataStreamRangeRejectsIgnoredRange(t *testing.T) {
	c := startMockServer(t)
	if _, err := c.DataStreamRange(context.Background(), "legacy", 1, 3); !errors.Is(err, errNoRangeSupport) {
		t.Fatalf("a stream without x-content-range must not pass for a range: got %v", err)
	}
}
