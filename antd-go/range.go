package antd

import (
	"errors"
	"fmt"
	"io"
	"math"
	"strconv"
	"strings"
)

// RangeToEnd, passed as the length to the *Range download methods, reads from
// the offset to the end of the object.
const RangeToEnd int64 = -1

// RangeReader is a byte-range download stream, returned by DataStreamRange and
// DataStreamPublicRange on both the REST and gRPC clients. Read it like any
// io.ReadCloser and Close it when done. The daemon fetches and decrypts only
// the chunks that overlap the range.
//
// Offset and Length describe the bytes the stream carries, after the daemon
// clamps a length past the end of the object; Size is the whole object's
// plaintext size. A stream that ends before Length bytes signals a failed
// download.
type RangeReader struct {
	io.ReadCloser
	Offset int64
	Length int64
	Size   int64
}

// errNoRangeSupport reports a daemon that answered a range request with the
// whole object, which only a daemon predating byte-range support does.
var errNoRangeSupport = errors.New("antd: the daemon ignored the byte range (it predates range support); upgrade antd")

// rangeHeader validates offset/length and renders them as an HTTP Range value.
func rangeHeader(offset, length int64) (string, error) {
	if err := checkRange(offset, length); err != nil {
		return "", err
	}
	// offset+length-1 would overflow int64 for a huge length; such a range
	// reads to the end anyway.
	if length == RangeToEnd || length > math.MaxInt64-offset {
		return fmt.Sprintf("bytes=%d-", offset), nil
	}
	return fmt.Sprintf("bytes=%d-%d", offset, offset+length-1), nil
}

// checkRange rejects a negative offset and a length that is neither positive
// nor RangeToEnd, before any request is sent.
func checkRange(offset, length int64) error {
	if offset < 0 {
		return fmt.Errorf("antd: range offset must not be negative, got %d", offset)
	}
	if length <= 0 && length != RangeToEnd {
		return fmt.Errorf("antd: range length must be positive or RangeToEnd, got %d", length)
	}
	return nil
}

// parseContentRange parses a satisfied range, "bytes first-last/size", into
// a RangeReader's Offset, Length and Size.
func parseContentRange(value string) (*RangeReader, error) {
	bad := fmt.Errorf("antd: malformed Content-Range %q", value)
	spec, ok := strings.CutPrefix(strings.TrimSpace(value), "bytes ")
	if !ok {
		return nil, bad
	}
	span, size, ok := strings.Cut(spec, "/")
	if !ok {
		return nil, bad
	}
	first, last, ok := strings.Cut(span, "-")
	if !ok {
		return nil, bad
	}
	f, err1 := strconv.ParseInt(first, 10, 64)
	l, err2 := strconv.ParseInt(last, 10, 64)
	s, err3 := strconv.ParseInt(size, 10, 64)
	if err1 != nil || err2 != nil || err3 != nil || f < 0 || l < f || l >= s {
		return nil, bad
	}
	return &RangeReader{Offset: f, Length: l - f + 1, Size: s}, nil
}

// unsatisfiedSize parses the size from a 416's "bytes */size" Content-Range,
// or returns -1 when it is absent or malformed.
func unsatisfiedSize(value string) int64 {
	size, ok := strings.CutPrefix(strings.TrimSpace(value), "bytes */")
	if !ok {
		return -1
	}
	s, err := strconv.ParseInt(size, 10, 64)
	if err != nil || s < 0 {
		return -1
	}
	return s
}
