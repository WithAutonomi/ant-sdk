"""MCP server exposing Autonomi network operations as tools."""

from __future__ import annotations

import base64
import json
import os
import sys
from contextlib import asynccontextmanager

from mcp.server.fastmcp import FastMCP

from antd import AsyncAntdClient
from antd.exceptions import AntdError
from .discover import discover_daemon_url
from .errors import format_error, format_unexpected_error

# ---------------------------------------------------------------------------
# Lifespan — create/close a single AsyncRestClient for the server's lifetime
# ---------------------------------------------------------------------------

_DEFAULT_BASE_URL = "http://127.0.0.1:8082"


@asynccontextmanager
async def lifespan(server: FastMCP):
    # Priority: env var > port-file discovery > default
    base_url = os.environ.get("ANTD_BASE_URL") or discover_daemon_url() or _DEFAULT_BASE_URL
    client = AsyncAntdClient(transport="rest", base_url=base_url)
    # Query the daemon's network on startup
    network = "unknown"
    try:
        status = await client.health()
        network = status.network
    except Exception:
        pass
    try:
        yield {"client": client, "network": network}
    finally:
        await client.close()


mcp = FastMCP(
    "antd-autonomi",
    instructions="Autonomi network operations via antd daemon",
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _get_ctx():
    """Return (client, network) from the lifespan context."""
    ctx = mcp.get_context()
    lc = ctx.request_context.lifespan_context
    return lc["client"], lc["network"]


def _ok(data: dict, network: str) -> str:
    data["network"] = network
    return json.dumps(data)


def _err_antd(exc: AntdError, network: str) -> str:
    d = format_error(exc)
    d["network"] = network
    return json.dumps(d)


def _err(exc: Exception, network: str) -> str:
    d = format_unexpected_error(exc)
    d["network"] = network
    return json.dumps(d)


# ---------------------------------------------------------------------------
# Tool 1: store_data
# ---------------------------------------------------------------------------


@mcp.tool()
async def store_data(
    text: str,
    private: bool = False,
    payment_mode: str = "auto",
) -> str:
    """Store text on the Autonomi network.

    Args:
        text: The text content to store.
        private: If True, store as private (encrypted). Default: public.
        payment_mode: Payment strategy — "auto" (default, uses merkle for 64+
            chunks), "merkle" (force batch payments, min 2 chunks), or "single"
            (per-chunk payments).

    Returns:
        JSON with address and cost, or error details.
    """
    client, network = _get_ctx()
    data = text.encode("utf-8")
    try:
        if private:
            result = await client.data_put_private(data, payment_mode=payment_mode)
        else:
            result = await client.data_put_public(data, payment_mode=payment_mode)
        return _ok({"address": result.address, "cost": result.cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 2: retrieve_data
# ---------------------------------------------------------------------------


@mcp.tool()
async def retrieve_data(
    address: str,
    private: bool = False,
) -> str:
    """Retrieve data from the Autonomi network by address.

    Args:
        address: The hex address (or data map for private data).
        private: If True, retrieve as private (decrypted). Default: public.

    Returns:
        JSON with the retrieved text, or error details.
    """
    client, network = _get_ctx()
    try:
        if private:
            raw = await client.data_get_private(address)
        else:
            raw = await client.data_get_public(address)
        return _ok({"text": raw.decode("utf-8", errors="replace")}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 3: upload_file
# ---------------------------------------------------------------------------


@mcp.tool()
async def upload_file(
    path: str,
    is_directory: bool = False,
    payment_mode: str = "auto",
) -> str:
    """Upload a local file or directory to the Autonomi network (public).

    Args:
        path: Absolute path to the local file or directory.
        is_directory: Set True if path is a directory.
        payment_mode: Payment strategy — "auto" (default, uses merkle for 64+
            chunks), "merkle" (force batch payments, min 2 chunks), or "single"
            (per-chunk payments).

    Returns:
        JSON with address and cost, or error details.
    """
    client, network = _get_ctx()
    try:
        if is_directory:
            result = await client.dir_upload_public(path, payment_mode=payment_mode)
        else:
            result = await client.file_upload_public(path, payment_mode=payment_mode)
        return _ok({"address": result.address, "cost": result.cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 4: download_file
# ---------------------------------------------------------------------------


@mcp.tool()
async def download_file(
    address: str,
    dest_path: str,
    is_directory: bool = False,
) -> str:
    """Download a file or directory from the Autonomi network to a local path.

    Args:
        address: The network address of the file/directory.
        dest_path: Local path to save to.
        is_directory: Set True if the address points to a directory.

    Returns:
        JSON confirming success, or error details.
    """
    client, network = _get_ctx()
    try:
        if is_directory:
            await client.dir_download_public(address, dest_path)
        else:
            await client.file_download_public(address, dest_path)
        return _ok({"status": "downloaded", "dest_path": dest_path}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 5: get_cost
# ---------------------------------------------------------------------------


@mcp.tool()
async def get_cost(
    text: str | None = None,
    file_path: str | None = None,
) -> str:
    """Estimate storage cost before committing data to the network.

    Provide exactly one of text or file_path.

    Args:
        text: Text content to estimate cost for.
        file_path: Local file path to estimate cost for.

    Returns:
        JSON with cost estimate in atto tokens, or error details.
    """
    client, network = _get_ctx()
    try:
        if text is not None:
            cost = await client.data_cost(text.encode("utf-8"))
            return _ok({"cost": cost, "type": "data"}, network)
        elif file_path is not None:
            cost = await client.file_cost(file_path)
            return _ok({"cost": cost, "type": "file"}, network)
        else:
            return _ok({"error": "BAD_REQUEST", "message": "Provide text or file_path"}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 6: check_health
# ---------------------------------------------------------------------------


@mcp.tool()
async def check_health() -> str:
    """Check antd daemon health and network status.

    Returns:
        JSON with health status and network name, or error details.
    """
    client, network = _get_ctx()
    try:
        status = await client.health()
        return _ok({"healthy": status.ok, "network": status.network}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 7: wallet_address
# ---------------------------------------------------------------------------


@mcp.tool()
async def wallet_address() -> str:
    """Get the wallet's public address from the antd daemon.

    Returns:
        JSON with the wallet address (e.g. "0x..."), or error details.
        Returns an error if no wallet is configured.
    """
    client, network = _get_ctx()
    try:
        result = await client.wallet_address()
        return _ok({"address": result.address}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 8: wallet_balance
# ---------------------------------------------------------------------------


@mcp.tool()
async def wallet_balance() -> str:
    """Get the wallet's token and gas balances from the antd daemon.

    Returns:
        JSON with balance (token balance) and gas_balance (gas token balance),
        both as strings in atto units. Returns an error if no wallet is configured.
    """
    client, network = _get_ctx()
    try:
        result = await client.wallet_balance()
        return _ok({"balance": result.balance, "gas_balance": result.gas_balance}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 9: chunk_put
# ---------------------------------------------------------------------------


@mcp.tool()
async def chunk_put(
    data: str,
) -> str:
    """Store a raw chunk on the Autonomi network.

    Args:
        data: Base64-encoded chunk data.

    Returns:
        JSON with chunk address and cost, or error details.
    """
    client, network = _get_ctx()
    try:
        raw = base64.b64decode(data)
        result = await client.chunk_put(raw)
        return _ok({"address": result.address, "cost": result.cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 10: chunk_get
# ---------------------------------------------------------------------------


@mcp.tool()
async def chunk_get(
    address: str,
) -> str:
    """Retrieve a raw chunk from the Autonomi network.

    Args:
        address: Hex address of the chunk.

    Returns:
        JSON with base64-encoded chunk data, or error details.
    """
    client, network = _get_ctx()
    try:
        raw = await client.chunk_get(address)
        return _ok({"data": base64.b64encode(raw).decode()}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 11: wallet_approve
# ---------------------------------------------------------------------------


@mcp.tool()
async def wallet_approve() -> str:
    """Approve the wallet to spend tokens on payment contracts.

    This is a one-time operation required before any storage operations.
    Must be called after configuring a wallet but before storing data.

    Returns:
        JSON with approved boolean, or error details.
    """
    client, network = _get_ctx()
    try:
        result = await client.wallet_approve()
        return _ok({"approved": result}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 12: prepare_upload
# ---------------------------------------------------------------------------


@mcp.tool()
async def prepare_upload(
    path: str,
) -> str:
    """Prepare a file upload for external signing (two-phase upload).

    Returns payment details including contract addresses, quote hashes, and
    amounts that an external signer must process before calling finalize_upload.

    Args:
        path: Absolute path to the local file to upload.

    Returns:
        JSON with upload_id, payments array (quote_hash, rewards_address, amount),
        total_amount, data_payments_address, payment_token_address, and rpc_url.
    """
    client, network = _get_ctx()
    try:
        result = await client.prepare_upload(path)
        return _ok({
            "upload_id": result.upload_id,
            "payments": [
                {
                    "quote_hash": p.quote_hash,
                    "rewards_address": p.rewards_address,
                    "amount": p.amount,
                }
                for p in result.payments
            ],
            "total_amount": result.total_amount,
            "data_payments_address": result.data_payments_address,
            "payment_token_address": result.payment_token_address,
            "rpc_url": result.rpc_url,
        }, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 13: prepare_data_upload
# ---------------------------------------------------------------------------


@mcp.tool()
async def prepare_data_upload(
    data: str,
) -> str:
    """Prepare a data upload for external signing (two-phase upload).

    Takes base64-encoded data and returns payment details including contract
    addresses, quote hashes, and amounts that an external signer must process
    before calling finalize_upload.

    Args:
        data: Base64-encoded bytes to upload.

    Returns:
        JSON with upload_id, payments array (quote_hash, rewards_address, amount),
        total_amount, data_payments_address, payment_token_address, and rpc_url.
    """
    client, network = _get_ctx()
    try:
        raw = base64.b64decode(data)
        result = await client.prepare_data_upload(raw)
        return _ok({
            "upload_id": result.upload_id,
            "payments": [
                {
                    "quote_hash": p.quote_hash,
                    "rewards_address": p.rewards_address,
                    "amount": p.amount,
                }
                for p in result.payments
            ],
            "total_amount": result.total_amount,
            "data_payments_address": result.data_payments_address,
            "payment_token_address": result.payment_token_address,
            "rpc_url": result.rpc_url,
        }, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 14: finalize_upload
# ---------------------------------------------------------------------------


@mcp.tool()
async def finalize_upload(
    upload_id: str,
    tx_hashes: dict[str, str],
) -> str:
    """Finalize a two-phase upload after payment transactions are submitted.

    Args:
        upload_id: The upload ID returned by prepare_upload.
        tx_hashes: Map of quote_hash to tx_hash for each payment.

    Returns:
        JSON with address (hex) and chunks_stored count.
    """
    client, network = _get_ctx()
    try:
        result = await client.finalize_upload(upload_id, tx_hashes)
        return _ok({"address": result.address, "chunks_stored": result.chunks_stored}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main():
    transport = "stdio"
    if "--sse" in sys.argv:
        transport = "sse"
    mcp.run(transport=transport)


if __name__ == "__main__":
    main()
