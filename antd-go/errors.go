// Package antd provides a Go client for the antd daemon REST API.
package antd

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
)

// AntdError is the base error type for all antd errors.
type AntdError struct {
	StatusCode int
	Message    string
}

func (e *AntdError) Error() string {
	return fmt.Sprintf("antd error %d: %s", e.StatusCode, e.Message)
}

// BadRequestError indicates invalid request parameters (HTTP 400).
type BadRequestError struct{ AntdError }

// PaymentError indicates insufficient funds or payment failure (HTTP 402).
type PaymentError struct{ AntdError }

// NotFoundError indicates the resource was not found on the network (HTTP 404).
type NotFoundError struct{ AntdError }

// AlreadyExistsError indicates the resource already exists (HTTP 409).
type AlreadyExistsError struct{ AntdError }

// ForkError indicates a version conflict or fork was detected (HTTP 409).
type ForkError struct{ AntdError }

// TooLargeError indicates the payload is too large (HTTP 413).
type TooLargeError struct{ AntdError }

// InternalError indicates an internal server error (HTTP 500).
type InternalError struct{ AntdError }

// NetworkError indicates the daemon cannot reach the network (HTTP 502).
type NetworkError struct{ AntdError }

// ServiceUnavailableError indicates the daemon is missing a required
// dependency such as a wallet (HTTP 503).
type ServiceUnavailableError struct{ AntdError }

// PartialUploadError indicates a finalize stored some chunks while others
// remained unstored after the daemon's retries (HTTP 502 with code
// PARTIAL_UPLOAD; gRPC ABORTED). The on-chain payment persists and the
// stored chunks stay on the network. How to finish the upload depends on
// Retryable:
//
//   - Retryable == true: the daemon kept the paid attempt (payment proofs +
//     unstored chunks) under the same upload_id. Call the same Finalize*
//     method again with the same arguments to store the remainder against
//     the same payment — no re-prepare, no second signature, no double
//     payment. Bound the loop: a persistent failure returns this error on
//     every call, so cap the attempts and treat a ChunksFailed that stops
//     shrinking as stuck. The retained attempt expires with the daemon's
//     pending-upload TTL. (antd >= 0.14.0; older daemons never set the
//     flag, so Retryable reads false and the re-prepare path applies.)
//   - Retryable == false: nothing was retained — a daemon-wallet upload
//     (UploadFile / UploadData, where the daemon pays), a merkle finalize
//     with deliberately unpaid batches, or an older daemon. Re-preparing
//     (or re-uploading) the same content skips already-stored chunks, so a
//     retry pays only for the missing remainder.
//
// Over REST the counts and Retryable come from the structured error body,
// read strictly: a count must be a JSON number holding a non-negative
// integer no larger than math.MaxUint64 (anything else reads as 0), and only
// the JSON boolean true sets Retryable. Over gRPC an ABORTED status is a
// partial upload only when its message starts with the daemon's fixed
// "Partial upload:" prefix (any other ABORTED, including one that merely
// embeds that text, maps to the generic AntdError). The counts are then
// parsed from the message, and Retryable is true only when all three counts
// parsed AND the "paid attempt retained" hint is present: a garbled or
// out-of-range count leaves the counts zero and Retryable false, so a
// malformed message falls back to the re-prepare path rather than a
// same-payment retry.
type PartialUploadError struct {
	AntdError
	ChunksStored uint64
	ChunksFailed uint64
	TotalChunks  uint64
	Retryable    bool
}

// partialUploadPrefix opens every PARTIAL_UPLOAD message the daemon emits;
// over gRPC it is the only way to tell a partial upload from any other
// ABORTED status.
const partialUploadPrefix = "Partial upload:"

// isPartialUploadMessage reports whether a gRPC status message is the
// daemon's PARTIAL_UPLOAD text. The check is anchored: the daemon's message
// always starts with the prefix, and an ABORTED that merely contains it (a
// wrapped upstream error, say) keeps the generic mapping.
func isPartialUploadMessage(msg string) bool {
	return strings.HasPrefix(msg, partialUploadPrefix)
}

// partialUploadCounts matches the fixed start of the daemon's PARTIAL_UPLOAD
// message: "Partial upload: <stored>/<total> chunks stored, <failed> failed".
var partialUploadCounts = regexp.MustCompile(`^` + regexp.QuoteMeta(partialUploadPrefix) + ` (\d+)/(\d+) chunks stored, (\d+) failed`)

// partialUploadRetainedHint is the message tail the daemon appends when it
// kept the paid attempt for a same-upload_id retry.
const partialUploadRetainedHint = "paid attempt retained"

// parsePartialUploadMessage recovers the chunk counts and the retryable hint
// from a PARTIAL_UPLOAD message. Used for gRPC, where the status carries no
// structured detail; REST callers get the body fields instead.
//
// The counts gate the retry: retryable is true only when the message matched
// the counts pattern, all three counts fit a uint64, and the "paid attempt
// retained" hint is present. A pattern miss or an out-of-range count yields
// zero counts and false. (strconv.ParseUint returns math.MaxUint64 alongside
// ErrRange on overflow, so its error is checked rather than discarded.)
func parsePartialUploadMessage(msg string) (stored, failed, total uint64, retryable bool) {
	m := partialUploadCounts.FindStringSubmatch(msg)
	if m == nil {
		return 0, 0, 0, false
	}
	var err error
	if stored, err = strconv.ParseUint(m[1], 10, 64); err != nil {
		return 0, 0, 0, false
	}
	if total, err = strconv.ParseUint(m[2], 10, 64); err != nil {
		return 0, 0, 0, false
	}
	if failed, err = strconv.ParseUint(m[3], 10, 64); err != nil {
		return 0, 0, 0, false
	}
	return stored, failed, total, strings.Contains(msg, partialUploadRetainedHint)
}

// errorFromBody maps a non-2xx REST response body onto a typed error. The
// JSON "error" string becomes the message; any other body (not JSON, not an
// object, or a non-string "error") keeps the raw body text as the message.
func errorFromBody(statusCode int, respBytes []byte) error {
	msg := string(respBytes)
	body := decodeErrorBody(respBytes)
	if e, ok := body["error"].(string); ok {
		msg = e
	}
	return errorForResponse(statusCode, msg, body)
}

// decodeErrorBody decodes an error body that is a single JSON object, or
// returns nil. Numbers decode as json.Number so a count keeps its exact
// integer value: a float64 would round anything above 2^53 and turn
// math.MaxUint64 into 2^64.
func decodeErrorBody(respBytes []byte) map[string]any {
	if !json.Valid(respBytes) {
		return nil
	}
	dec := json.NewDecoder(bytes.NewReader(respBytes))
	dec.UseNumber()
	var body map[string]any
	if dec.Decode(&body) != nil {
		return nil
	}
	return body
}

// errorForResponse maps a REST error response onto a typed error, preferring
// the machine-readable `code` over the bare HTTP status where they diverge
// (PARTIAL_UPLOAD arrives as a 502 that would otherwise read as a generic
// NetworkError). body may be nil when the response was not JSON.
//
// The partial-upload fields are read strictly: code must be the JSON string
// "PARTIAL_UPLOAD" (anything else falls back to the status-based error),
// each count goes through jsonCount, and only the JSON boolean true sets
// Retryable. A field of the wrong type reads as its zero value; a malformed
// body never panics or escapes as a raw decoding error.
func errorForResponse(statusCode int, message string, body map[string]any) error {
	if code, ok := body["code"].(string); !ok || code != "PARTIAL_UPLOAD" {
		return errorForStatus(statusCode, message)
	}
	retryable, _ := body["retryable"].(bool)
	return &PartialUploadError{
		AntdError:    AntdError{StatusCode: statusCode, Message: message},
		ChunksStored: jsonCount(body["chunks_stored"]),
		ChunksFailed: jsonCount(body["chunks_failed"]),
		TotalChunks:  jsonCount(body["total_chunks"]),
		Retryable:    retryable,
	}
}

// twoTo64 is 2^64, the first float64 past the uint64 range.
const twoTo64 = float64(1 << 64)

// jsonCount converts a decoded JSON count to a uint64. It accepts only a
// JSON number holding a non-negative integer no larger than math.MaxUint64;
// anything else (a string, bool, array, object or null, or a negative,
// fractional or out-of-range number) reads as 0.
func jsonCount(v any) uint64 {
	switch n := v.(type) {
	case json.Number:
		if u, err := strconv.ParseUint(n.String(), 10, 64); err == nil {
			return u // plain integer literal: exact
		}
		// A sign, fraction or exponent (or a literal past MaxUint64):
		// fall back to the float value under the same range guard.
		f, err := n.Float64()
		if err != nil {
			return 0
		}
		return countFromFloat(f)
	case float64:
		return countFromFloat(n)
	default:
		return 0
	}
}

// countFromFloat converts f to a uint64 only when it is finite, integral and
// in [0, 2^64). Converting a negative, NaN, infinite or >= 2^64 float64 to
// uint64 is implementation-defined in Go, and a fraction would silently
// truncate, so every other value reads as 0.
func countFromFloat(f float64) uint64 {
	if math.IsNaN(f) || math.IsInf(f, 0) || f < 0 || f >= twoTo64 || f != math.Trunc(f) {
		return 0
	}
	return uint64(f)
}

// errorForStatus returns the appropriate error type for an HTTP status code.
func errorForStatus(statusCode int, message string) error {
	base := AntdError{StatusCode: statusCode, Message: message}
	switch statusCode {
	case 400:
		return &BadRequestError{base}
	case 402:
		return &PaymentError{base}
	case 404:
		return &NotFoundError{base}
	case 409:
		return &AlreadyExistsError{base}
	case 413:
		return &TooLargeError{base}
	case 500:
		return &InternalError{base}
	case 502:
		return &NetworkError{base}
	case 503:
		return &ServiceUnavailableError{base}
	default:
		return &base
	}
}
