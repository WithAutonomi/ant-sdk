"""Regression tests for the antd-mcp tool layer after the put/get rename.

Pinned to the antd-py v1.0 surface (PR #117 onward): asserts that store_data /
retrieve_data / upload_file / download_file / get_cost forward to the new
client methods (`data_put`, `data_get`, `file_put`, `file_get`,
`file_put_public`, `file_get_public`) and coerce the wire-format
`payment_mode` string into the typed `PaymentMode` enum at the call boundary.
"""

from __future__ import annotations

import json
from unittest.mock import AsyncMock

import pytest

from antd import PaymentMode
from antd.models import (
    DataPutPublicResult,
    DataPutResult,
    FilePutPublicResult,
    FilePutResult,
    UploadCostEstimate,
)
from antd_mcp import server


def _tool_fn(tool):
    if callable(tool):
        return tool
    fn = getattr(tool, "fn", None)
    if fn is None:
        raise AssertionError(f"Cannot extract coroutine function from MCP tool {tool!r}")
    return fn


@pytest.fixture
def mock_client(monkeypatch):
    client = AsyncMock()
    monkeypatch.setattr(server, "_get_ctx", lambda: (client, "test-net"))
    return client


# ---------------------------------------------------------------------------
# store_data
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_store_data_public_calls_data_put_public_with_typed_payment_mode(mock_client):
    mock_client.data_put_public.return_value = DataPutPublicResult(
        address="0xpublic",
        chunks_stored=3,
        payment_mode_used="single",
    )

    raw = await _tool_fn(server.store_data)(text="hello", payment_mode="merkle")
    payload = json.loads(raw)

    # Forwarded as bytes + PaymentMode enum kwarg.
    mock_client.data_put_public.assert_awaited_once_with(
        b"hello", payment_mode=PaymentMode.MERKLE
    )
    mock_client.data_put.assert_not_awaited()

    assert payload == {
        "address": "0xpublic",
        "chunks_stored": 3,
        "payment_mode_used": "single",
        "network": "test-net",
    }


@pytest.mark.asyncio
async def test_store_data_private_calls_data_put_and_surfaces_data_map_as_address(mock_client):
    mock_client.data_put.return_value = DataPutResult(
        data_map="caller-held-datamap",
        chunks_stored=2,
        payment_mode_used="auto",
    )

    raw = await _tool_fn(server.store_data)(text="secret", private=True)
    payload = json.loads(raw)

    mock_client.data_put.assert_awaited_once_with(b"secret", payment_mode=PaymentMode.AUTO)
    mock_client.data_put_public.assert_not_awaited()

    # Private response surfaces the DataMap under the `address` key (matches
    # the retrieve_data input pattern).
    assert payload["address"] == "caller-held-datamap"
    assert payload["chunks_stored"] == 2
    assert payload["payment_mode_used"] == "auto"


# ---------------------------------------------------------------------------
# retrieve_data
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_retrieve_data_public_calls_data_get_public(mock_client):
    mock_client.data_get_public.return_value = b"hello"
    raw = await _tool_fn(server.retrieve_data)(address="0xpublic")
    payload = json.loads(raw)

    mock_client.data_get_public.assert_awaited_once_with("0xpublic")
    mock_client.data_get.assert_not_awaited()
    assert payload["text"] == "hello"


@pytest.mark.asyncio
async def test_retrieve_data_private_calls_data_get(mock_client):
    mock_client.data_get.return_value = b"secret"
    raw = await _tool_fn(server.retrieve_data)(address="caller-held-datamap", private=True)
    payload = json.loads(raw)

    mock_client.data_get.assert_awaited_once_with("caller-held-datamap")
    mock_client.data_get_public.assert_not_awaited()
    assert payload["text"] == "secret"


# ---------------------------------------------------------------------------
# upload_file
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_upload_file_public_calls_file_put_public(mock_client):
    mock_client.file_put_public.return_value = FilePutPublicResult(
        address="0xfilepub",
        storage_cost_atto="1000",
        gas_cost_wei="42",
        chunks_stored=3,
        payment_mode_used="auto",
    )

    raw = await _tool_fn(server.upload_file)(path="/tmp/foo.txt", payment_mode="single")
    payload = json.loads(raw)

    mock_client.file_put_public.assert_awaited_once_with(
        "/tmp/foo.txt", payment_mode=PaymentMode.SINGLE
    )
    mock_client.file_put.assert_not_awaited()

    assert payload == {
        "address": "0xfilepub",
        "storage_cost_atto": "1000",
        "gas_cost_wei": "42",
        "chunks_stored": 3,
        "payment_mode_used": "auto",
        "network": "test-net",
    }


@pytest.mark.asyncio
async def test_upload_file_private_calls_file_put_and_surfaces_data_map_as_address(mock_client):
    mock_client.file_put.return_value = FilePutResult(
        data_map="caller-held-file-datamap",
        storage_cost_atto="900",
        gas_cost_wei="42",
        chunks_stored=2,
        payment_mode_used="merkle",
    )

    raw = await _tool_fn(server.upload_file)(path="/tmp/secret.txt", private=True)
    payload = json.loads(raw)

    mock_client.file_put.assert_awaited_once_with(
        "/tmp/secret.txt", payment_mode=PaymentMode.AUTO
    )
    mock_client.file_put_public.assert_not_awaited()

    assert payload["address"] == "caller-held-file-datamap"
    assert payload["storage_cost_atto"] == "900"
    assert payload["chunks_stored"] == 2
    assert payload["payment_mode_used"] == "merkle"


# ---------------------------------------------------------------------------
# download_file
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_download_file_public_calls_file_get_public(mock_client):
    raw = await _tool_fn(server.download_file)(address="0xfilepub", dest_path="/tmp/out.txt")
    payload = json.loads(raw)

    mock_client.file_get_public.assert_awaited_once_with("0xfilepub", "/tmp/out.txt")
    mock_client.file_get.assert_not_awaited()
    assert payload["status"] == "downloaded"
    assert payload["dest_path"] == "/tmp/out.txt"


@pytest.mark.asyncio
async def test_download_file_private_calls_file_get(mock_client):
    raw = await _tool_fn(server.download_file)(
        address="caller-held-file-datamap",
        dest_path="/tmp/priv-out.txt",
        private=True,
    )
    payload = json.loads(raw)

    mock_client.file_get.assert_awaited_once_with("caller-held-file-datamap", "/tmp/priv-out.txt")
    mock_client.file_get_public.assert_not_awaited()
    assert payload["status"] == "downloaded"


# ---------------------------------------------------------------------------
# get_cost
# ---------------------------------------------------------------------------


def _cost_est() -> UploadCostEstimate:
    return UploadCostEstimate(
        cost="50",
        file_size=4,
        chunk_count=3,
        estimated_gas_cost_wei="150",
        payment_mode="single",
    )


@pytest.mark.asyncio
async def test_get_cost_data_forwards_payment_mode(mock_client):
    mock_client.data_cost.return_value = _cost_est()

    raw = await _tool_fn(server.get_cost)(text="test", payment_mode="single")
    payload = json.loads(raw)

    mock_client.data_cost.assert_awaited_once_with(b"test", payment_mode=PaymentMode.SINGLE)
    assert payload["type"] == "data"
    assert payload["cost"] == "50"


@pytest.mark.asyncio
async def test_get_cost_file_forwards_payment_mode(mock_client):
    mock_client.file_cost.return_value = _cost_est()

    raw = await _tool_fn(server.get_cost)(file_path="/tmp/foo.txt")
    payload = json.loads(raw)

    mock_client.file_cost.assert_awaited_once_with("/tmp/foo.txt", payment_mode=PaymentMode.AUTO)
    assert payload["type"] == "file"
