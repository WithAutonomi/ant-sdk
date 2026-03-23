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

// NotImplementedError indicates the endpoint is not implemented (HTTP 501).
type NotImplementedError struct{ AntdError }

// NetworkError indicates the daemon cannot reach the network (HTTP 502).
type NetworkError struct{ AntdError }

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
	case 501:
		return &NotImplementedError{base}
	case 502:
		return &NetworkError{base}
	default:
		return &base
	}
}
