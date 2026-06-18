"""Unit tests for the antd-mcp tool surface.

These tests bypass the FastMCP transport machinery and exercise the tool
coroutines directly. ``server._get_ctx`` is monkeypatched to return a fully
mocked ``AsyncRestClient`` so we can verify the tool layer's wiring without a
running daemon.
"""

from __future__ import annotations

import base64
import json
from unittest.mock import AsyncMock

import pytest

from antd.models import (
    FinalizeUploadResult,
    PaymentInfo,
    PrepareChunkResult,
    PrepareUploadResult,
)
from antd_mcp import server


def _tool_fn(tool):
    """Return the raw coroutine function for a FastMCP-decorated tool.

    FastMCP versions differ:
    - Older releases return the original function from ``@mcp.tool()``.
    - Newer releases wrap it in a ``FunctionTool`` exposing ``.fn``.
    """
    if callable(tool):
        return tool
    fn = getattr(tool, "fn", None)
    if fn is None:
        raise AssertionError(
            f"Cannot extract coroutine function from MCP tool object {tool!r}"
        )
    return fn


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_client(monkeypatch):
    """Replace ``server._get_ctx`` with one that returns an AsyncMock client."""
    client = AsyncMock()
    monkeypatch.setattr(server, "_get_ctx", lambda: (client, "test-net"))
    return client


def _wave_batch_prepare_result() -> PrepareUploadResult:
    """Canned wave-batch PrepareUploadResult for use in mocks."""
    return PrepareUploadResult(
        upload_id="upload-abc",
        payments=[
            PaymentInfo(
                quote_hash="0xquote1",
                rewards_address="0xreward1",
                amount="1000",
            )
        ],
        total_amount="1000",
        payment_vault_address="0xvault",
        payment_token_address="0xtoken",
        rpc_url="http://rpc.example",
        payment_type="wave_batch",
        total_chunks=4,
        already_stored_count=2,
    )


# ---------------------------------------------------------------------------
# prepare_upload
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_prepare_upload_default_does_not_forward_visibility(mock_client):
    """When called without visibility, the MCP tool must call
    ``client.prepare_upload(path)`` with a single positional arg — NOT pass
    ``visibility=None`` (the antd-py layer defaults visibility to ``None``
    itself; keeping the call shape one-arg preserves backward compatibility)."""
    mock_client.prepare_upload.return_value = _wave_batch_prepare_result()

    raw = await _tool_fn(server.prepare_upload)(path="/tmp/foo.bin")
    payload = json.loads(raw)

    # Forwarded path with NO visibility kwarg.
    mock_client.prepare_upload.assert_awaited_once_with("/tmp/foo.bin")
    assert payload["upload_id"] == "upload-abc"
    assert payload["network"] == "test-net"
    # already-stored preflight (added in antd 0.10.0)
    assert payload["total_chunks"] == 4
    assert payload["already_stored_count"] == 2


@pytest.mark.asyncio
async def test_prepare_upload_public_visibility_forwarded(mock_client):
    """visibility="public" must be forwarded as a keyword argument."""
    mock_client.prepare_upload.return_value = _wave_batch_prepare_result()

    raw = await _tool_fn(server.prepare_upload)(path="/tmp/foo.bin", visibility="public")
    payload = json.loads(raw)

    mock_client.prepare_upload.assert_awaited_once_with(
        "/tmp/foo.bin", visibility="public"
    )
    assert payload["network"] == "test-net"


# ---------------------------------------------------------------------------
# prepare_upload_public
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_prepare_upload_public_calls_helper(mock_client):
    """The dedicated tool must call the underlying ``prepare_upload_public``
    helper on the client (not re-do the visibility forwarding itself)."""
    mock_client.prepare_upload_public.return_value = _wave_batch_prepare_result()

    raw = await _tool_fn(server.prepare_upload_public)(path="/tmp/foo.bin")
    payload = json.loads(raw)

    mock_client.prepare_upload_public.assert_awaited_once_with("/tmp/foo.bin")
    # The generic prepare_upload should NOT have been called.
    mock_client.prepare_upload.assert_not_awaited()
    assert payload["upload_id"] == "upload-abc"
    assert payload["network"] == "test-net"


# ---------------------------------------------------------------------------
# finalize_upload — data_map / data_map_address surfaced
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_finalize_upload_includes_data_map_fields(mock_client):
    mock_client.finalize_upload.return_value = FinalizeUploadResult(
        address="0xfinaladdr",
        chunks_stored=7,
        data_map="aabbccddee",
        data_map_address="0xdmapaddr",
    )

    raw = await _tool_fn(server.finalize_upload)(
        upload_id="upload-abc",
        tx_hashes={"0xquote1": "0xtx1"},
    )
    payload = json.loads(raw)

    mock_client.finalize_upload.assert_awaited_once_with(
        "upload-abc", {"0xquote1": "0xtx1"}
    )
    assert payload["address"] == "0xfinaladdr"
    assert payload["chunks_stored"] == 7
    assert payload["data_map"] == "aabbccddee"
    assert payload["data_map_address"] == "0xdmapaddr"
    assert payload["network"] == "test-net"


# ---------------------------------------------------------------------------
# prepare_chunk_upload — both branches
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_prepare_chunk_upload_already_stored_branch(mock_client):
    """If the chunk is already on-network, payment fields are absent."""
    mock_client.prepare_chunk_upload.return_value = PrepareChunkResult(
        address="0xchunkaddr",
        already_stored=True,
    )

    raw_bytes = b"\x00\x01\x02\x03"
    b64 = base64.b64encode(raw_bytes).decode()
    raw = await _tool_fn(server.prepare_chunk_upload)(data_base64=b64)
    payload = json.loads(raw)

    # Bytes were base64-decoded before forwarding.
    mock_client.prepare_chunk_upload.assert_awaited_once_with(raw_bytes)

    # Minimal shape: no payment fields.
    assert payload["address"] == "0xchunkaddr"
    assert payload["already_stored"] is True
    assert "upload_id" not in payload
    assert "payments" not in payload
    assert "payment_vault_address" not in payload
    assert payload["network"] == "test-net"


@pytest.mark.asyncio
async def test_prepare_chunk_upload_wave_batch_branch(mock_client):
    """Wave-batch path must emit the full payment-intent shape."""
    mock_client.prepare_chunk_upload.return_value = PrepareChunkResult(
        address="0xchunkaddr",
        already_stored=False,
        upload_id="chunk-upload-1",
        payment_type="wave_batch",
        payments=[
            PaymentInfo(
                quote_hash="0xq1",
                rewards_address="0xr1",
                amount="500",
            )
        ],
        total_amount="500",
        payment_vault_address="0xvault",
        payment_token_address="0xtoken",
        rpc_url="http://rpc.example",
    )

    raw_bytes = b"hello"
    b64 = base64.b64encode(raw_bytes).decode()
    raw = await _tool_fn(server.prepare_chunk_upload)(data_base64=b64)
    payload = json.loads(raw)

    mock_client.prepare_chunk_upload.assert_awaited_once_with(raw_bytes)

    # Full shape.
    assert payload["address"] == "0xchunkaddr"
    assert payload["already_stored"] is False
    assert payload["upload_id"] == "chunk-upload-1"
    assert payload["payment_type"] == "wave_batch"
    assert payload["total_amount"] == "500"
    assert payload["payment_vault_address"] == "0xvault"
    assert payload["payment_token_address"] == "0xtoken"
    assert payload["rpc_url"] == "http://rpc.example"
    assert payload["payments"] == [
        {
            "quote_hash": "0xq1",
            "rewards_address": "0xr1",
            "amount": "500",
        }
    ]
    assert payload["network"] == "test-net"


# ---------------------------------------------------------------------------
# finalize_chunk_upload
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_finalize_chunk_upload_forwards_args_and_returns_address(mock_client):
    mock_client.finalize_chunk_upload.return_value = "0xstoredaddr"

    tx_hashes = {"0xq1": "0xtx1"}
    raw = await _tool_fn(server.finalize_chunk_upload)(
        upload_id="chunk-upload-1",
        tx_hashes=tx_hashes,
    )
    payload = json.loads(raw)

    # Both args forwarded positionally.
    mock_client.finalize_chunk_upload.assert_awaited_once_with(
        "chunk-upload-1", tx_hashes
    )
    assert payload == {"address": "0xstoredaddr", "network": "test-net"}
