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
    body. Over gRPC they are parsed from the status message
    (``"Partial upload: S/T chunks stored, F failed ..."`` with a
    ``"paid attempt retained"`` hint when retryable).

    Malformed input is read conservatively and never escapes as a raw
    ``ValueError`` / ``TypeError`` / ``OverflowError``:

    - REST: each count must be a JSON integer in ``0..2**64 - 1`` -- a quoted
      number, bool, float (including ``Infinity``), array, object, negative
      or larger value reads as ``0``. ``retryable`` is True only for the JSON
      literal ``true``. Only a string ``code`` equal to ``"PARTIAL_UPLOAD"``
      selects this error; any other body keeps the status mapping (502 ->
      :class:`NetworkError`).
    - gRPC: only an ``ABORTED`` whose status details *start with*
      ``"Partial upload:"`` is a partial upload; any other ``ABORTED`` stays a
      :class:`ForkError`. The counts gate the retry: ``retryable`` is True
      only when the message matches the pattern above, all three counts fit
      in a u64, and the hint is present. Otherwise the counts are zero and
      ``retryable`` is False.

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
# Over gRPC (no structured detail) this prefix is what tells a PARTIAL_UPLOAD
# ``ABORTED`` apart from any other ``ABORTED`` the daemon may send.
PARTIAL_UPLOAD_MESSAGE_PREFIX = "Partial upload:"

# ASCII-only: Python's ``\d`` otherwise matches any Unicode decimal digit,
# which ``int()`` would then accept. The daemon only ever writes ASCII digits.
_PARTIAL_UPLOAD_COUNTS = re.compile(
    re.escape(PARTIAL_UPLOAD_MESSAGE_PREFIX) + r" (\d+)/(\d+) chunks stored, (\d+) failed",
    re.ASCII,
)

# Message tail the daemon appends when it kept the paid attempt for a
# same-upload_id retry.
_PARTIAL_UPLOAD_RETAINED_HINT = "paid attempt retained"

# The daemon's counts are Rust ``u64``s, so nothing larger is a real count.
_U64_MAX = 2**64 - 1


def _json_count(value: object) -> int:
    """Read one REST body count: a JSON integer in ``0..=u64::MAX``, else ``0``.

    ``bool`` is rejected explicitly because ``isinstance(True, int)`` is True
    in Python. Floats (``1.5``, ``1.0``, ``Infinity``, ``NaN``), quoted
    numbers, arrays, objects, ``null``, negatives and values above u64 max all
    read as ``0``. Never raises.
    """
    if isinstance(value, bool) or not isinstance(value, int):
        return 0
    return value if 0 <= value <= _U64_MAX else 0


def _message_count(digits: str) -> int | None:
    """Convert one count captured from a gRPC message, or ``None`` when it
    does not convert: above u64 max, or too long for ``int()`` (Python
    >= 3.11 raises ``ValueError`` past 4300 digits). Never raises."""
    try:
        value = int(digits)
    except ValueError:
        return None
    return value if value <= _U64_MAX else None


def is_partial_upload_message(details: object) -> bool:
    """True when gRPC status details are the daemon's PARTIAL_UPLOAD message.

    Anchored: the raw details must *start with* ``"Partial upload:"``. An
    ``ABORTED`` that only embeds the phrase (e.g. ``"upstream error: Partial
    upload: 1/3 chunks stored, 2 failed"``) is some other failure and keeps
    its previous mapping.
    """
    return isinstance(details, str) and details.startswith(PARTIAL_UPLOAD_MESSAGE_PREFIX)


def parse_partial_upload_message(message: str) -> tuple[int, int, int, bool]:
    """Recover ``(chunks_stored, chunks_failed, total_chunks, retryable)`` from
    a PARTIAL_UPLOAD message.

    Used for gRPC, where the status carries no structured detail; REST callers
    get the body fields instead. The counts gate the retry: ``retryable`` is
    True only when the message matches
    ``"Partial upload: <stored>/<total> chunks stored, <failed> failed"``, all
    three counts convert (each no larger than u64 max), **and** the
    ``"paid attempt retained"`` hint is present. On a pattern miss or any
    count that does not convert the result is ``(0, 0, 0, False)``: a message
    the SDK could not read must never tell a caller to repeat a paid
    finalize. Never raises.
    """
    if not isinstance(message, str):
        return 0, 0, 0, False
    m = _PARTIAL_UPLOAD_COUNTS.search(message)
    if m is None:
        return 0, 0, 0, False
    stored, total, failed = (_message_count(g) for g in m.groups())
    if stored is None or total is None or failed is None:
        return 0, 0, 0, False
    return stored, failed, total, _PARTIAL_UPLOAD_RETAINED_HINT in message


def raise_for_http_error(status_code: int, message: str, body: object) -> None:
    """Raise the typed error for a REST error response, preferring the body's
    machine-readable ``code`` over the bare status where they diverge.

    ``PARTIAL_UPLOAD`` arrives as a 502 that :func:`raise_for_http_status`
    would read as a plain :class:`NetworkError`; every other code keeps the
    status-based mapping. ``body`` is the decoded JSON (``None`` when the
    response was not JSON) and is read strictly, since it may be malformed:

    - only a JSON object whose ``code`` is the string ``"PARTIAL_UPLOAD"``
      selects :class:`PartialUploadError`; a body that is not an object, or a
      ``code`` that is missing, not a string or spelled differently, keeps
      the status mapping;
    - each count must be a JSON integer in ``0..=u64::MAX``; anything else
      (quoted number, bool, float including ``Infinity``, array, object,
      negative, larger value) reads as ``0``;
    - ``retryable`` is True only for the JSON literal ``true``; an absent flag
      (daemons before 0.14.0) or any other value reads as ``False``.

    For any non-2xx status this raises an :class:`AntdError` subclass, never a
    raw ``ValueError`` / ``TypeError`` / ``OverflowError``.
    """
    if 200 <= status_code < 300:
        return
    if isinstance(body, dict):
        code = body.get("code")
        if isinstance(code, str) and code == PARTIAL_UPLOAD_CODE:
            raise PartialUploadError(
                message,
                status_code,
                chunks_stored=_json_count(body.get("chunks_stored")),
                chunks_failed=_json_count(body.get("chunks_failed")),
                total_chunks=_json_count(body.get("total_chunks")),
                retryable=body.get("retryable") is True,
            )
    raise_for_http_status(status_code, message)
