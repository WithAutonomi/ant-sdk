// Package antd provides a Go client for the antd daemon REST API.
package antd

import (
	"fmt"
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
// Over REST the counts and Retryable come from the structured error body.
// Over gRPC an ABORTED status is treated as a partial upload only when its
// message carries the daemon's fixed "Partial upload:" prefix (any other
// ABORTED maps to the generic AntdError); the counts and the "paid attempt
// retained" hint are then parsed best-effort from that message, and a
// garbled message leaves the counts zero and Retryable false.
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
// daemon's PARTIAL_UPLOAD text (some transports prepend their own code
// decoration, so this is a containment check, not a strict prefix).
func isPartialUploadMessage(msg string) bool {
	return strings.Contains(msg, partialUploadPrefix)
}

// partialUploadCounts matches the fixed prefix of the daemon's PARTIAL_UPLOAD
// message: "Partial upload: <stored>/<total> chunks stored, <failed> failed".
var partialUploadCounts = regexp.MustCompile(partialUploadPrefix + ` (\d+)/(\d+) chunks stored, (\d+) failed`)

// partialUploadRetainedHint is the message tail the daemon appends when it
// kept the paid attempt for a same-upload_id retry.
const partialUploadRetainedHint = "paid attempt retained"

// parsePartialUploadMessage recovers the chunk counts and the retryable hint
// from a PARTIAL_UPLOAD message. Used for gRPC, where the status carries no
// structured detail; REST callers get the body fields instead.
func parsePartialUploadMessage(msg string) (stored, failed, total uint64, retryable bool) {
	if m := partialUploadCounts.FindStringSubmatch(msg); m != nil {
		stored, _ = strconv.ParseUint(m[1], 10, 64)
		total, _ = strconv.ParseUint(m[2], 10, 64)
		failed, _ = strconv.ParseUint(m[3], 10, 64)
	}
	retryable = strings.Contains(msg, partialUploadRetainedHint)
	return stored, failed, total, retryable
}

// errorForResponse maps a REST error response onto a typed error, preferring
// the machine-readable `code` over the bare HTTP status where they diverge
// (PARTIAL_UPLOAD arrives as a 502 that would otherwise read as a generic
// NetworkError). body may be nil when the response was not JSON.
func errorForResponse(statusCode int, message string, body map[string]any) error {
	if code, _ := body["code"].(string); code == "PARTIAL_UPLOAD" {
		e := &PartialUploadError{AntdError: AntdError{StatusCode: statusCode, Message: message}}
		if v, ok := body["chunks_stored"].(float64); ok {
			e.ChunksStored = uint64(v)
		}
		if v, ok := body["chunks_failed"].(float64); ok {
			e.ChunksFailed = uint64(v)
		}
		if v, ok := body["total_chunks"].(float64); ok {
			e.TotalChunks = uint64(v)
		}
		if v, ok := body["retryable"].(bool); ok {
			e.Retryable = v
		}
		return e
	}
	return errorForStatus(statusCode, message)
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
