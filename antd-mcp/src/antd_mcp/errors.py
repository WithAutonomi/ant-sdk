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
    PaymentError,
    TooLargeError,
)

# ``PartialUploadError`` arrived in the antd SDK together with the daemon's
# resumable finalize. The MCP server's dependency floor still admits older SDK
# releases that predate it, so the import is guarded: against such an SDK the
# server keeps starting and serving, and a partial upload simply surfaces as
# the ``NETWORK_ERROR`` it always was (with the daemon's message text).
try:
    from antd.exceptions import PartialUploadError
except ImportError:  # antd SDK without the typed partial-upload error
    PartialUploadError = None  # type: ignore[assignment,misc]

_CODE_MAP: dict[type[AntdError], str] = {
    NotFoundError: "NOT_FOUND",
    AlreadyExistsError: "ALREADY_EXISTS",
    ForkError: "VERSION_CONFLICT",
    BadRequestError: "BAD_REQUEST",
    PaymentError: "PAYMENT_FAILED",
    NetworkError: "NETWORK_ERROR",
    TooLargeError: "TOO_LARGE",
    InternalError: "INTERNAL_ERROR",
}
if PartialUploadError is not None:
    _CODE_MAP[PartialUploadError] = "PARTIAL_UPLOAD"


def format_error(exc: AntdError) -> dict:
    """Convert an AntdError to a structured error dict.

    ``PARTIAL_UPLOAD`` additionally carries ``chunks_stored``,
    ``chunks_failed``, ``total_chunks`` and ``retryable`` so an agent can
    decide whether to call the same finalize tool again (``retryable``: the
    daemon kept the paid attempt under the same ``upload_id``) or to
    re-prepare the content (already-stored chunks are skipped).

    Those fields are copied from the SDK's typed error, which reads the
    daemon's response strictly: a malformed count reads as ``0`` and
    ``retryable`` is True only when the daemon unambiguously said so (the
    JSON literal ``true``). A malformed partial-upload body therefore reaches
    here as ``PARTIAL_UPLOAD`` or ``NETWORK_ERROR``, never as an unexpected
    exception.
    """
    code = _CODE_MAP.get(type(exc), "UNKNOWN")
    d = {
        "error": code,
        "message": str(exc),
        "status_code": exc.status_code,
    }
    if PartialUploadError is not None and isinstance(exc, PartialUploadError):
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
