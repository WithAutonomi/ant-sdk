"""antd-mcp must import and serve against an antd SDK that predates
``PartialUploadError``.

The MCP server's dependency floor admits older ``antd`` releases than the
one it is developed against. Both packages live in this checkout, so the
regular suite always runs head against head and cannot see an incompatible
allowed dependency. These tests simulate the older SDK by removing the
symbol before importing the error module. ``monkeypatch.undo()`` restores
both the SDK attribute and the original ``sys.modules`` entries, so the
rest of the suite keeps seeing the normal modules.
"""

from __future__ import annotations

import importlib
import sys

import antd.exceptions as antd_exceptions
from antd.exceptions import NetworkError


def _import_errors_without_partial_upload(monkeypatch):
    monkeypatch.delattr(antd_exceptions, "PartialUploadError", raising=True)
    # Drop the cached modules so the guarded import runs again from scratch.
    monkeypatch.delitem(sys.modules, "antd_mcp.errors", raising=False)
    monkeypatch.delitem(sys.modules, "antd_mcp.server", raising=False)
    return importlib.import_module("antd_mcp.errors")


def test_errors_module_imports_without_partial_upload_error(monkeypatch):
    errors = _import_errors_without_partial_upload(monkeypatch)
    assert errors.PartialUploadError is None
    assert "PARTIAL_UPLOAD" not in errors._CODE_MAP.values()


def test_format_error_degrades_to_network_error_without_partial_upload(monkeypatch):
    errors = _import_errors_without_partial_upload(monkeypatch)
    payload = errors.format_error(
        NetworkError("Partial upload: 300/312 chunks stored, 12 failed", 502)
    )
    assert payload["error"] == "NETWORK_ERROR"
    assert payload["status_code"] == 502
    assert "retryable" not in payload
    assert "chunks_stored" not in payload


def test_server_module_imports_without_partial_upload_error(monkeypatch):
    # The startup path: ``antd_mcp.server`` imports the error module at import
    # time, so this is what an older-SDK install would hit first.
    _import_errors_without_partial_upload(monkeypatch)
    server = importlib.import_module("antd_mcp.server")
    assert hasattr(server, "main")


def test_normal_import_still_maps_partial_upload():
    # Sanity check that the guarded import is the real one in this checkout.
    errors = importlib.import_module("antd_mcp.errors")
    assert errors.PartialUploadError is antd_exceptions.PartialUploadError
    assert errors._CODE_MAP[errors.PartialUploadError] == "PARTIAL_UPLOAD"


def test_format_error_without_retention_known_attribute():
    # An antd release that has PartialUploadError but predates the retention
    # flag: the payload reads retention as unknown, except that retryable
    # implies a known retention.
    errors = importlib.import_module("antd_mcp.errors")

    old = antd_exceptions.PartialUploadError(
        "Partial upload: 1/3 chunks stored, 2 failed", 502,
        chunks_stored=1, chunks_failed=2, total_chunks=3,
    )
    del old.retention_known
    payload = errors.format_error(old)
    assert payload["error"] == "PARTIAL_UPLOAD"
    assert (payload["retryable"], payload["retention_known"]) == (False, False)

    old_retryable = antd_exceptions.PartialUploadError(
        "Partial upload: 1/3 chunks stored, 2 failed (paid attempt retained)", 502,
        chunks_stored=1, chunks_failed=2, total_chunks=3, retryable=True,
    )
    del old_retryable.retention_known
    payload = errors.format_error(old_retryable)
    assert (payload["retryable"], payload["retention_known"]) == (True, True)
