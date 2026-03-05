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


def format_error(exc: AntdError) -> dict:
    """Convert an AntdError to a structured error dict."""
    code = _CODE_MAP.get(type(exc), "UNKNOWN")
    return {
        "error": code,
        "message": str(exc),
        "status_code": exc.status_code,
    }


def format_unexpected_error(exc: Exception) -> dict:
    """Convert an unexpected exception to a structured error dict."""
    return {
        "error": "UNEXPECTED",
        "message": str(exc),
    }
