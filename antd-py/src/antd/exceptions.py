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
    """Fork/version conflict detected (HTTP 409 / gRPC ABORTED).

    A gRPC ``ABORTED`` for a partial upload used to map here and now raises
    :class:`PartialUploadError`. The daemon sends ``ABORTED`` only for
    PARTIAL_UPLOAD, so code that caught ``ForkError`` around a finalize
    should catch :class:`PartialUploadError` instead.
    """
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
    (or order the ``except`` clauses) to handle it specifically. Over gRPC a
    partial upload used to raise :class:`ForkError`; the daemon sends
    ``ABORTED`` only for PARTIAL_UPLOAD, so code that caught ``ForkError``
    around a finalize should catch this instead.

    The on-chain payment persists and the stored chunks stay on the network.
    Two flags say how to finish the upload, and ``retryable`` implies
    ``retention_known``:

    - ``retryable``: the daemon kept the paid attempt (payment proofs +
      unstored chunks) under the same ``upload_id``. Call the **same**
      ``finalize_*`` method again with the **same arguments** (the same
      ``upload_id`` and payment artefacts) to store the remainder against the
      same payment -- no re-prepare, no second signature, no double payment.
      Bound the loop: a persistent failure raises this on every call, so cap
      the attempts and treat a ``chunks_failed`` that stops shrinking as
      stuck. The retained attempt expires with the daemon's pending-upload
      TTL. Sent by antd >= 0.14.0.
    - ``retention_known`` and not ``retryable``: the daemon confirmed it kept
      nothing (e.g. a merkle finalize with deliberately unpaid batches).
      Re-preparing the same content skips already-stored chunks, so a retry
      pays only for the remainder.
    - not ``retention_known``: retention is unknown, and the daemon may still
      hold the paid attempt (it records the resume handle before it returns
      the error). Stop automatic recovery, keep the ``upload_id`` and the
      original payment artefacts, and reconcile before re-preparing or paying
      again. Never pay again on this signal alone. Daemons before 0.14.0
      never send ``retryable``, so their REST partial uploads read as unknown,
      as does a gRPC message the SDK could not read.

    Over REST the counts and both flags come from the structured error body.
    Over gRPC they are parsed from the status message
    (``"Partial upload: S/T chunks stored, F failed after retries: <reason>
    (<hint>)"``, where the hint starts ``"paid attempt retained"`` when the
    daemon kept the attempt and ``"stored chunks persist; re-prepare the same
    content"`` when it did not).

    Malformed input is read conservatively and never escapes as a raw
    ``ValueError`` / ``TypeError`` / ``OverflowError``:

    - REST: each count must be a JSON integer in ``0..2**64 - 1`` -- a quoted
      number, bool, float (including ``Infinity``), array, object, negative
      or larger value reads as ``0``. ``retryable`` is True only for the JSON
      literal ``true``, and ``retention_known`` only when ``retryable`` is a
      JSON bool (``true`` or ``false``); absent, ``null`` or any other type
      reads as unknown. Only a string ``code`` equal to ``"PARTIAL_UPLOAD"``
      selects this error; any other body keeps the status mapping (502 ->
      :class:`NetworkError`).
    - gRPC: only an ``ABORTED`` whose status details *start with*
      ``"Partial upload:"`` is a partial upload; any other ``ABORTED`` stays a
      :class:`ForkError`. ``retention_known`` is True only when the message
      starts with the counts pattern above, all three counts fit in a u64,
      and the message ends with one of the two hints; the hint then decides
      ``retryable``. A pattern miss or unconvertible count zeroes the counts
      and both flags. Readable counts with a missing, truncated or
      unrecognised hint keep the counts, but both flags stay False:
      retention unknown, not "nothing retained".

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
        retention_known: bool = False,
    ):
        super().__init__(message, status_code)
        self.chunks_stored = chunks_stored
        self.chunks_failed = chunks_failed
        self.total_chunks = total_chunks
        self.retryable = retryable
        # retryable => retention_known: a retained attempt is a known one.
        self.retention_known = bool(retention_known or retryable)


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

# The daemon closes every PARTIAL_UPLOAD message with one of two parenthesised
# hints (``partial_upload_hint`` in antd/src/error.rs): the retained hint when
# it kept the paid attempt for a same-upload_id retry, the not-retained hint
# when it did not. Daemons before 0.14.0 write only the not-retained hint.
_PARTIAL_UPLOAD_RETAINED_HINT = "paid attempt retained"
_PARTIAL_UPLOAD_NOT_RETAINED_HINT = "stored chunks persist; re-prepare the same content"

# The hint must close the message: "(<hint>...)" at the very end (``\Z``, not
# ``$``, which would also match before a trailing newline). A hint quoted inside
# the failure reason, a truncated tail, or text after the hint does not match.
_PARTIAL_UPLOAD_RETENTION_TAIL = re.compile(
    r"\(("
    + re.escape(_PARTIAL_UPLOAD_RETAINED_HINT)
    + "|"
    + re.escape(_PARTIAL_UPLOAD_NOT_RETAINED_HINT)
    + r")[^()]*\)\Z"
)

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


def parse_partial_upload_message(message: str) -> tuple[int, int, int, bool, bool]:
    """Recover ``(chunks_stored, chunks_failed, total_chunks, retryable,
    retention_known)`` from a PARTIAL_UPLOAD message.

    Used for gRPC, where the status carries no structured detail; REST callers
    get the body fields instead. ``retention_known`` is True only when the
    message starts with
    ``"Partial upload: <stored>/<total> chunks stored, <failed> failed"``, all
    three counts convert (each no larger than u64 max), and the message ends
    with one of the daemon's two hints, ``"(paid attempt retained...)"`` or
    ``"(stored chunks persist; re-prepare the same content...)"``;
    ``retryable`` is then True only for the first. On a pattern miss or any
    count that does not convert the result is ``(0, 0, 0, False, False)``.
    Readable counts with a missing, truncated or unrecognised tail keep the
    counts but leave both flags False. A message the SDK could not fully read
    must never tell a caller to repeat a paid finalize, nor that nothing was
    kept. Never raises.
    """
    if not isinstance(message, str):
        return 0, 0, 0, False, False
    m = _PARTIAL_UPLOAD_COUNTS.match(message)
    if m is None:
        return 0, 0, 0, False, False
    stored, total, failed = (_message_count(g) for g in m.groups())
    if stored is None or total is None or failed is None:
        return 0, 0, 0, False, False
    tail = _PARTIAL_UPLOAD_RETENTION_TAIL.search(message)
    if tail is None:
        return stored, failed, total, False, False
    return stored, failed, total, tail.group(1) == _PARTIAL_UPLOAD_RETAINED_HINT, True


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
      (daemons before 0.14.0) or any other value reads as ``False``;
    - ``retention_known`` is True only when ``retryable`` is a JSON bool
      (``true`` or ``false``). Absent (daemons before 0.14.0), ``null`` or any
      other type reads as ``False``: retention unknown.

    For any non-2xx status this raises an :class:`AntdError` subclass, never a
    raw ``ValueError`` / ``TypeError`` / ``OverflowError``.
    """
    if 200 <= status_code < 300:
        return
    if isinstance(body, dict):
        code = body.get("code")
        if isinstance(code, str) and code == PARTIAL_UPLOAD_CODE:
            retryable = body.get("retryable")
            raise PartialUploadError(
                message,
                status_code,
                chunks_stored=_json_count(body.get("chunks_stored")),
                chunks_failed=_json_count(body.get("chunks_failed")),
                total_chunks=_json_count(body.get("total_chunks")),
                retryable=retryable is True,
                retention_known=isinstance(retryable, bool),
            )
    raise_for_http_status(status_code, message)
