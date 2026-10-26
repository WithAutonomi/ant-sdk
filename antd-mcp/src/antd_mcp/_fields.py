"""Small helpers for reading optional SDK fields defensively."""

from __future__ import annotations


def sha256_of(obj: object) -> str | None:
    """The plaintext's SHA-256 (hex) carried by an upload result or manifest
    entry, or None.

    The field needs antd 0.17.0 or later on the daemon and antd SDK 0.4.0
    (antd-mcp's floor). An install that bypasses the floor (e.g. --no-deps)
    can pair the server with an older SDK whose results have no such
    attribute, so it is read defensively. An empty string (gRPC's zero
    value) is also none.
    """
    value = getattr(obj, "sha256", None)
    return value or None
