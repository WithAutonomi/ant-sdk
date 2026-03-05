"""Exception hierarchy for antd SDK, mapped from HTTP/gRPC error codes."""


class AntdError(Exception):
    """Base exception for all antd errors."""

    def __init__(self, message: str, status_code: int = 0):
        super().__init__(message)
        self.status_code = status_code


class NotFoundError(AntdError):
    """Resource not found (HTTP 404 / gRPC NOT_FOUND)."""
    pass


class AlreadyExistsError(AntdError):
    """Resource already exists (HTTP 409 / gRPC ALREADY_EXISTS)."""
    pass


class ForkError(AntdError):
    """Fork/version conflict detected (HTTP 409 / gRPC ABORTED)."""
    pass


class BadRequestError(AntdError):
    """Invalid request (HTTP 400 / gRPC INVALID_ARGUMENT)."""
    pass


class PaymentError(AntdError):
    """Payment or wallet error (HTTP 402 / gRPC FAILED_PRECONDITION)."""
    pass


class NetworkError(AntdError):
    """Network communication error (HTTP 502 / gRPC UNAVAILABLE)."""
    pass


class TooLargeError(AntdError):
    """Payload too large (HTTP 413 / gRPC RESOURCE_EXHAUSTED)."""
    pass


class InternalError(AntdError):
    """Internal server error (HTTP 500 / gRPC INTERNAL)."""
    pass


# HTTP status code -> exception class mapping
HTTP_STATUS_MAP: dict[int, type[AntdError]] = {
    400: BadRequestError,
    402: PaymentError,
    404: NotFoundError,
    409: AlreadyExistsError,  # also ForkError, distinguished by message
    413: TooLargeError,
    500: InternalError,
    502: NetworkError,
}


def raise_for_http_status(status_code: int, message: str) -> None:
    """Raise the appropriate AntdError subclass for an HTTP status code."""
    if 200 <= status_code < 300:
        return
    exc_class = HTTP_STATUS_MAP.get(status_code, AntdError)
    raise exc_class(message, status_code)
