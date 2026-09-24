"""Structured error formatting for MCP tool responses."""

from __future__ import annotations

from antd.exceptions import (
    AntdError,
    AlreadyExistsError,
    BadRequestError,
    ForkError,
    InternalError,
    NetworkError,
    NotFoundError,
    PartialUploadError,
    PaymentError,
    TooLargeError,
)

_CODE_MAP: dict[type[AntdError], str] = {
    NotFoundError: "NOT_FOUND",
    AlreadyExistsError: "ALREADY_EXISTS",
    ForkError: "VERSION_CONFLICT",
    BadRequestError: "BAD_REQUEST",
    PaymentError: "PAYMENT_FAILED",
    NetworkError: "NETWORK_ERROR",
    PartialUploadError: "PARTIAL_UPLOAD",
    TooLargeError: "TOO_LARGE",
    InternalError: "INTERNAL_ERROR",
}


def format_error(exc: AntdError) -> dict:
    """Convert an AntdError to a structured error dict.

    ``PARTIAL_UPLOAD`` additionally carries ``chunks_stored``,
    ``chunks_failed``, ``total_chunks`` and ``retryable`` so an agent can
    decide whether to call the same finalize tool again (``retryable``: the
    daemon kept the paid attempt under the same ``upload_id``) or to
    re-prepare the content (already-stored chunks are skipped).
    """
    code = _CODE_MAP.get(type(exc), "UNKNOWN")
    d = {
        "error": code,
        "message": str(exc),
        "status_code": exc.status_code,
    }
    if isinstance(exc, PartialUploadError):
        d["chunks_stored"] = exc.chunks_stored
        d["chunks_failed"] = exc.chunks_failed
        d["total_chunks"] = exc.total_chunks
        d["retryable"] = exc.retryable
    return d


def format_unexpected_error(exc: Exception) -> dict:
    """Convert an unexpected exception to a structured error dict."""
    return {
        "error": "UNEXPECTED",
        "message": str(exc),
    }
