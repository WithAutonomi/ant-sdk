"""antd-mcp must import and serve against an antd SDK that predates
``PartialUploadError``.

The dependency floor requires antd >= 0.2.0, but an install that bypasses it
(e.g. --no-deps) can still pair the server with an older SDK, so the import
guard stays and is tested here. Both packages live in this checkout, so the
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


# --- An antd SDK without the pointer API (0.2.0 and earlier) ---------------

_POINTER_ERRORS = (
    "PointerFinalError", "PointerForkedError", "ConflictError", "CloseGroupShortfallError",
)


def _import_without_pointer_api(monkeypatch):
    """Strip the pointer API from the SDK the way 0.2.0 lacks it: no pointer
    models, no pointer errors, no client methods."""
    import antd
    from antd._rest import AsyncRestClient

    for name in _POINTER_ERRORS:
        monkeypatch.delattr(antd_exceptions, name, raising=True)
    for name in ("PointerKind", "PointerOp"):
        monkeypatch.delattr(antd, name, raising=True)
    monkeypatch.delattr(AsyncRestClient, "pointer_get", raising=True)
    monkeypatch.delitem(sys.modules, "antd_mcp.errors", raising=False)
    monkeypatch.delitem(sys.modules, "antd_mcp.server", raising=False)
    errors = importlib.import_module("antd_mcp.errors")
    server = importlib.import_module("antd_mcp.server")
    return errors, server


def test_errors_module_imports_without_pointer_errors(monkeypatch):
    errors, _ = _import_without_pointer_api(monkeypatch)
    for name in _POINTER_ERRORS:
        assert getattr(errors, name) is None
    assert not {"POINTER_FINAL", "POINTER_FORKED", "CONFLICT", "CLOSE_GROUP_SHORTFALL"} & set(
        errors._CODE_MAP.values()
    )
    # An older SDK reads the daemon's 409s as AlreadyExistsError, as before.
    payload = errors.format_error(antd_exceptions.AlreadyExistsError("Pointer is final", 409))
    assert payload["error"] == "ALREADY_EXISTS"
    assert "hint" not in payload


def test_server_serves_without_pointer_tools_on_an_older_sdk(monkeypatch):
    import asyncio

    _, server = _import_without_pointer_api(monkeypatch)
    assert server.POINTERS_AVAILABLE is False
    names = {t.name for t in asyncio.run(server.mcp.list_tools())}
    assert len(names) == 21  # 19 storage tools + the 2 manifest tools, no pointer tools
    assert not any(n.startswith("pointer_") for n in names)
    assert {"upload_file", "finalize_upload", "chunk_put"} <= names


def test_server_registers_pointer_tools_on_the_current_sdk():
    import asyncio

    server = importlib.import_module("antd_mcp.server")
    assert server.POINTERS_AVAILABLE is True
    names = {t.name for t in asyncio.run(server.mcp.list_tools())}
    assert sum(n.startswith("pointer_") for n in names) == 10


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


def test_service_unavailable_maps_to_its_own_code_with_a_hint():
    errors = importlib.import_module("antd_mcp.errors")
    payload = errors.format_error(
        antd_exceptions.ServiceUnavailableError("wallet not configured", 503)
    )
    assert payload["error"] == "SERVICE_UNAVAILABLE"
    assert payload["status_code"] == 503
    assert "try again later" in payload["hint"]
