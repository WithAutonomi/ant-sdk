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

# ``PartialUploadError`` arrived in the antd SDK (0.2.0) together with the
# daemon's resumable finalize, and the MCP server's dependency floor now
# requires it. The import stays guarded for an environment that bypasses the
# floor (e.g. installed with --no-deps): against an older SDK the server keeps
# starting and serving, and a partial upload simply surfaces as the
# ``NETWORK_ERROR`` it always was (with the daemon's message text).
try:
    from antd.exceptions import PartialUploadError
except ImportError:  # antd SDK without the typed partial-upload error
    PartialUploadError = None  # type: ignore[assignment,misc]

# The pointer-era errors arrived in the antd SDK together with the pointer
# API. Guarded like ``PartialUploadError``: against an older SDK the server
# starts without the pointer tools (see server.py) and these codes never
# appear.
try:
    from antd.exceptions import (
        CloseGroupShortfallError,
        ConflictError,
        PointerFinalError,
        PointerForkedError,
    )
except ImportError:  # antd SDK without the pointer API
    CloseGroupShortfallError = None  # type: ignore[assignment,misc]
    ConflictError = None  # type: ignore[assignment,misc]
    PointerFinalError = None  # type: ignore[assignment,misc]
    PointerForkedError = None  # type: ignore[assignment,misc]

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

# What an agent should do next, for the codes where the wrong move costs
# money. The lookup is by exact type, like _CODE_MAP, so PointerForkedError
# (a ForkError subclass) gets its own entry rather than VERSION_CONFLICT.
_HINTS: dict[type[AntdError], str] = {}
if PointerFinalError is not None:
    _CODE_MAP[PointerFinalError] = "POINTER_FINAL"
    _HINTS[PointerFinalError] = (
        "The pointer is final (transferred or frozen): nothing can update or "
        "transfer it again. Nothing was paid. Do not retry; pointer_controller "
        "shows the pointer that now decides what this address resolves to."
    )
if PointerForkedError is not None:
    _CODE_MAP[PointerForkedError] = "POINTER_FORKED"
    _HINTS[PointerForkedError] = (
        "The pointer's owner signed two different final states and no "
        "majority of its close group holds either, so the network has no "
        "answer for it. Do not retry; pointer_finality lists the rival states."
    )
if ConflictError is not None:
    _CODE_MAP[ConflictError] = "CONFLICT"
    _HINTS[ConflictError] = (
        "Another write to this pointer is in the way: a prepared write awaits "
        "payment (finalize it, or wait up to an hour for it to expire), or "
        "this update lost to a newer state. Nothing was paid. Read the pointer "
        "again with pointer_get before deciding whether to write."
    )
if CloseGroupShortfallError is not None:
    _CODE_MAP[CloseGroupShortfallError] = "CLOSE_GROUP_SHORTFALL"

_SHORTFALL_RETRYABLE_HINT = (
    "Retry the finalize, the payment was kept: call pointer_finalize again "
    "with the same upload_id to store the paid state against the same "
    "payment. No second payment is made. Stop after a few attempts; the kept "
    "attempt expires after one hour."
)
_SHORTFALL_HINT = (
    "Too few of the close group answered or stored. A read is free to retry "
    "later. Do not repeat a paid write automatically: it may already have "
    "been paid for and a repeat pays again. Check the pointer with "
    "pointer_get or pointer_finality first, and ask the user before paying "
    "again."
)


def format_error(exc: AntdError) -> dict:
    """Convert an AntdError to a structured error dict.

    ``PARTIAL_UPLOAD`` additionally carries ``chunks_stored``,
    ``chunks_failed``, ``total_chunks``, ``retryable`` and
    ``retention_known`` so an agent can pick one of three paths:
    ``retryable`` -- the daemon kept the paid attempt, so call the same
    finalize tool again with the same arguments; ``retention_known`` and not
    ``retryable`` -- the daemon kept nothing, so re-prepare (already-stored
    chunks are skipped); not ``retention_known`` -- the daemon may still hold
    the paid attempt, so stop and reconcile before preparing or paying again.
    ``retryable`` implies ``retention_known``.

    Those fields are copied from the SDK's typed error, which reads the
    daemon's response strictly: a malformed count reads as ``0`` and
    ``retryable`` is True only when the daemon unambiguously said so (the
    JSON literal ``true``). A malformed partial-upload body therefore reaches
    here as ``PARTIAL_UPLOAD`` or ``NETWORK_ERROR``, never as an unexpected
    exception.

    The pointer-era codes (``POINTER_FINAL``, ``POINTER_FORKED``,
    ``CONFLICT``, ``CLOSE_GROUP_SHORTFALL``) carry a ``hint`` saying what to
    do next. ``CLOSE_GROUP_SHORTFALL`` also carries ``retryable``: True only
    for a pointer finalize whose paid state the daemon kept, so the agent
    retries that finalize and pays nothing more.
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
        # antd releases before the retention flag lack the attribute: read it
        # as unknown, except that retryable implies a known retention.
        d["retention_known"] = (
            bool(getattr(exc, "retention_known", False)) or exc.retryable is True
        )
    if CloseGroupShortfallError is not None and isinstance(exc, CloseGroupShortfallError):
        d["retryable"] = exc.retryable is True
        d["hint"] = _SHORTFALL_RETRYABLE_HINT if d["retryable"] else _SHORTFALL_HINT
    elif type(exc) in _HINTS:
        d["hint"] = _HINTS[type(exc)]
    return d


def format_unexpected_error(exc: Exception) -> dict:
    """Convert an unexpected exception to a structured error dict."""
    return {
        "error": "UNEXPECTED",
        "message": str(exc),
    }
