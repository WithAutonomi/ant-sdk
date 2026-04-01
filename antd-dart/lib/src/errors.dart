/// Base error type for all antd errors.
class AntdError implements Exception {
  /// The HTTP status code.
  final int statusCode;

  /// The error message.
  final String message;

  const AntdError(this.statusCode, this.message);

  @override
  String toString() => 'antd error $statusCode: $message';
}

/// Invalid request parameters (HTTP 400).
class BadRequestError extends AntdError {
  const BadRequestError(String message) : super(400, message);
}

/// Insufficient funds or payment failure (HTTP 402).
class PaymentError extends AntdError {
  const PaymentError(String message) : super(402, message);
}

/// Resource not found on the network (HTTP 404).
class NotFoundError extends AntdError {
  const NotFoundError(String message) : super(404, message);
}

/// Resource already exists (HTTP 409).
class AlreadyExistsError extends AntdError {
  const AlreadyExistsError(String message) : super(409, message);
}

/// Version conflict or fork detected (HTTP 409).
class ForkError extends AntdError {
  const ForkError(String message) : super(409, message);
}

/// Payload too large (HTTP 413).
class TooLargeError extends AntdError {
  const TooLargeError(String message) : super(413, message);
}

/// Internal server error (HTTP 500).
class InternalError extends AntdError {
  const InternalError(String message) : super(500, message);
}

/// Daemon cannot reach the network (HTTP 502).
class NetworkError extends AntdError {
  const NetworkError(String message) : super(502, message);
}

/// Service unavailable, e.g. wallet not configured (HTTP 503).
class ServiceUnavailableError extends AntdError {
  const ServiceUnavailableError(String message) : super(503, message);
}

/// Returns the appropriate error type for an HTTP status code.
AntdError errorForStatus(int statusCode, String message) {
  switch (statusCode) {
    case 400:
      return BadRequestError(message);
    case 402:
      return PaymentError(message);
    case 404:
      return NotFoundError(message);
    case 409:
      return AlreadyExistsError(message);
    case 413:
      return TooLargeError(message);
    case 500:
      return InternalError(message);
    case 502:
      return NetworkError(message);
    case 503:
      return ServiceUnavailableError(message);
    default:
      return AntdError(statusCode, message);
  }
}
