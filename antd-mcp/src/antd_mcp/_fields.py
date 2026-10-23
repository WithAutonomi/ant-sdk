"""Small helpers for reading optional SDK fields defensively."""

from __future__ import annotations


def sha256_of(obj: object) -> str | None:
    """The plaintext's SHA-256 (hex) carried by an upload result or manifest
    entry, or None.

    antd-mcp's floor is still an antd SDK that predates the field (it needs
    antd 0.17.0 or later on the daemon, and the matching SDK release), so the
    attribute may not exist at all. An empty string (gRPC's zero value) is
    also none.
    """
    value = getattr(obj, "sha256", None)
    return value or None
