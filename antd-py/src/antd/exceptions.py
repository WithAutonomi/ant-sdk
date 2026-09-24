"""Exception hierarchy for antd SDK, mapped from HTTP/gRPC error codes."""

from __future__ import annotations

import re


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


class PartialUploadError(NetworkError):
    """A finalize stored some chunks while others stayed unstored after the
    daemon's retries (HTTP 502 with ``code: "PARTIAL_UPLOAD"`` / gRPC ``ABORTED``).

    Subclasses :class:`NetworkError` because it rides the same 502 status, so
    an existing ``except NetworkError`` still catches it; check ``isinstance``
    (or order the ``except`` clauses) to handle it specifically.

    The on-chain payment persists and the stored chunks stay on the network.
    How to finish the upload depends on ``retryable``:

    - ``True``: the daemon kept the paid attempt (payment proofs + unstored
      chunks) under the same ``upload_id``. Call the **same** ``finalize_*``
      method again with the **same arguments** to store the remainder against
      the same payment — no re-prepare, no second signature, no double
      payment. Bound the loop: a persistent failure raises this on every
      call, so cap the attempts and treat a ``chunks_failed`` that stops
      shrinking as stuck. The retained attempt expires with the daemon's
      pending-upload TTL. Sent by antd >= 0.14.0; older daemons never send
      the flag, so it reads ``False`` and the re-prepare path applies.
    - ``False``: nothing was retained (older daemon, or a merkle finalize
      with deliberately unpaid batches). Re-preparing the same content skips
      already-stored chunks, so a retry pays only for the remainder.

    Over REST the counts and ``retryable`` come from the structured error
    body. Over gRPC they are parsed best-effort from the status message
    (``"Partial upload: S/T chunks stored, F failed ..."`` with a
    ``"paid attempt retained"`` hint when retryable); an unrecognised message
    leaves the counts at zero and ``retryable`` False.

    See ``docs/external-signer-flow.md`` section 6 for the full contract.
    """

    def __init__(
        self,
        message: str,
        status_code: int = 0,
        *,
        chunks_stored: int = 0,
        chunks_failed: int = 0,
        total_chunks: int = 0,
        retryable: bool = False,
    ):
        super().__init__(message, status_code)
        self.chunks_stored = chunks_stored
        self.chunks_failed = chunks_failed
        self.total_chunks = total_chunks
        self.retryable = retryable


class ServiceUnavailableError(AntdError):
    """Service unavailable, e.g. wallet not configured (HTTP 503 / gRPC UNAVAILABLE)."""
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
    503: ServiceUnavailableError,
}


def raise_for_http_status(status_code: int, message: str) -> None:
    """Raise the appropriate AntdError subclass for an HTTP status code."""
    if 200 <= status_code < 300:
        return
    exc_class = HTTP_STATUS_MAP.get(status_code, AntdError)
    raise exc_class(message, status_code)


# Machine-readable code the daemon puts in the error body of a partial store.
PARTIAL_UPLOAD_CODE = "PARTIAL_UPLOAD"

# Fixed prefix of the daemon's PARTIAL_UPLOAD message:
# "Partial upload: <stored>/<total> chunks stored, <failed> failed ...".
_PARTIAL_UPLOAD_COUNTS = re.compile(r"Partial upload: (\d+)/(\d+) chunks stored, (\d+) failed")

# Message tail the daemon appends when it kept the paid attempt for a
# same-upload_id retry.
_PARTIAL_UPLOAD_RETAINED_HINT = "paid attempt retained"


def parse_partial_upload_message(message: str) -> tuple[int, int, int, bool]:
    """Recover ``(chunks_stored, chunks_failed, total_chunks, retryable)`` from
    a PARTIAL_UPLOAD message.

    Used for gRPC, where the status carries no structured detail; REST callers
    get the body fields instead. An unrecognised message yields zero counts
    and ``retryable=False``.
    """
    stored = failed = total = 0
    m = _PARTIAL_UPLOAD_COUNTS.search(message)
    if m:
        stored, total, failed = int(m.group(1)), int(m.group(2)), int(m.group(3))
    retryable = _PARTIAL_UPLOAD_RETAINED_HINT in message
    return stored, failed, total, retryable


def raise_for_http_error(status_code: int, message: str, body: dict | None) -> None:
    """Raise the typed error for a REST error response, preferring the body's
    machine-readable ``code`` over the bare status where they diverge.

    ``PARTIAL_UPLOAD`` arrives as a 502 that :func:`raise_for_http_status`
    would read as a plain :class:`NetworkError`; every other code keeps the
    status-based mapping. ``body`` may be ``None`` when the response was not
    JSON. ``retryable`` is absent on daemons before 0.14.0 and defaults to
    ``False``.
    """
    if 200 <= status_code < 300:
        return
    if isinstance(body, dict) and body.get("code") == PARTIAL_UPLOAD_CODE:
        raise PartialUploadError(
            message,
            status_code,
            chunks_stored=int(body.get("chunks_stored") or 0),
            chunks_failed=int(body.get("chunks_failed") or 0),
            total_chunks=int(body.get("total_chunks") or 0),
            retryable=bool(body.get("retryable", False)),
        )
    raise_for_http_status(status_code, message)
