// Package antd provides a Go client for the antd daemon REST API.
package antd

import "fmt"

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
// failed quorum or belonged to unpaid batches (HTTP 502 with code
// PARTIAL_UPLOAD; gRPC ABORTED). The on-chain payment persists and the
// stored chunks stay on the network: re-preparing the same content skips
// them, so a retry pays only for the missing remainder.
//
// The chunk counts are populated from the REST error body; over gRPC they
// only appear in the message text and the fields stay zero.
type PartialUploadError struct {
	AntdError
	ChunksStored uint64
	ChunksFailed uint64
	TotalChunks  uint64
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
