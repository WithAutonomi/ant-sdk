"""MCP server exposing Autonomi network operations as tools."""

from __future__ import annotations

import base64
import json
import os
import sys
from contextlib import asynccontextmanager

from mcp.server.fastmcp import FastMCP

from antd import AsyncAntdClient, PaymentMode
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


def _pm(payment_mode: str) -> PaymentMode:
    """Coerce a wire-format payment_mode string to the PaymentMode enum.

    Raises ValueError if the string is not one of "auto", "merkle", "single" —
    propagated to the caller as an MCP error.
    """
    return PaymentMode(payment_mode)


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
        private: If True, store as private (encrypted). The returned ``address``
            is the caller-held DataMap and is NOT itself stored on-network —
            keep it safe. Default: public (DataMap stored on-network at
            ``address``).
        payment_mode: Payment strategy — "auto" (default, uses merkle for 64+
            chunks), "merkle" (force batch payments, min 2 chunks), or "single"
            (per-chunk payments).

    Returns:
        JSON with ``address`` (on-network address when public, caller-held
        DataMap when private), ``chunks_stored``, ``payment_mode_used``, or
        error details.
    """
    client, network = _get_ctx()
    data = text.encode("utf-8")
    try:
        pm = _pm(payment_mode)
        if private:
            result = await client.data_put(data, payment_mode=pm)
            address = result.data_map
        else:
            result = await client.data_put_public(data, payment_mode=pm)
            address = result.address
        return _ok(
            {
                "address": address,
                "chunks_stored": result.chunks_stored,
                "payment_mode_used": result.payment_mode_used,
            },
            network,
        )
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
        address: The on-network address (public) or the caller-held DataMap
            (private).
        private: If True, retrieve as private (decrypted). Default: public.

    Returns:
        JSON with the retrieved text, or error details.
    """
    client, network = _get_ctx()
    try:
        if private:
            raw = await client.data_get(address)
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
    private: bool = False,
    payment_mode: str = "auto",
) -> str:
    """Upload a local file to the Autonomi network.

    Args:
        path: Absolute path to the local file.
        private: If True, upload as private (encrypted). The returned
            ``address`` is the caller-held DataMap and is NOT stored
            on-network — keep it safe. Default: public (DataMap stored
            on-network at ``address``).
        payment_mode: Payment strategy — "auto" (default, uses merkle for 64+
            chunks), "merkle" (force batch payments, min 2 chunks), or "single"
            (per-chunk payments).

    Returns:
        JSON with ``address`` (on-network address when public, caller-held
        DataMap when private), ``storage_cost_atto``, ``gas_cost_wei``,
        ``chunks_stored``, and ``payment_mode_used``, or error details.
    """
    client, network = _get_ctx()
    try:
        pm = _pm(payment_mode)
        if private:
            result = await client.file_put(path, payment_mode=pm)
            address = result.data_map
        else:
            result = await client.file_put_public(path, payment_mode=pm)
            address = result.address
        return _ok(
            {
                "address": address,
                "storage_cost_atto": result.storage_cost_atto,
                "gas_cost_wei": result.gas_cost_wei,
                "chunks_stored": result.chunks_stored,
                "payment_mode_used": result.payment_mode_used,
            },
            network,
        )
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
    private: bool = False,
) -> str:
    """Download a file from the Autonomi network to a local path.

    Args:
        address: The on-network address (public) or the caller-held DataMap
            (private).
        dest_path: Local path to save to.
        private: If True, download as private (decrypted). Default: public.

    Returns:
        JSON confirming success, or error details.
    """
    client, network = _get_ctx()
    try:
        if private:
            await client.file_get(address, dest_path)
        else:
            await client.file_get_public(address, dest_path)
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
    payment_mode: str = "auto",
) -> str:
    """Estimate storage cost before committing data to the network.

    Provide exactly one of text or file_path.

    Args:
        text: Text content to estimate cost for.
        file_path: Local file path to estimate cost for.
        payment_mode: Payment strategy the estimate should reflect — "auto"
            (default), "merkle", or "single".

    Returns:
        JSON with cost estimate in atto tokens, or error details.
    """
    client, network = _get_ctx()
    try:
        pm = _pm(payment_mode)
        if text is not None:
            est = await client.data_cost(text.encode("utf-8"), payment_mode=pm)
            return _ok(
                {
                    "type": "data",
                    "cost": est.cost,
                    "file_size": est.file_size,
                    "chunk_count": est.chunk_count,
                    "estimated_gas_cost_wei": est.estimated_gas_cost_wei,
                    "payment_mode": est.payment_mode,
                },
                network,
            )
        elif file_path is not None:
            est = await client.file_cost(file_path, payment_mode=pm)
            return _ok(
                {
                    "type": "file",
                    "cost": est.cost,
                    "file_size": est.file_size,
                    "chunk_count": est.chunk_count,
                    "estimated_gas_cost_wei": est.estimated_gas_cost_wei,
                    "payment_mode": est.payment_mode,
                },
                network,
            )
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
        JSON with health, network, and (when reported by antd >= 0.4.0)
        diagnostic fields: version, evm_network, uptime_seconds,
        build_commit, payment_token_address, payment_vault_address.
    """
    client, network = _get_ctx()
    try:
        status = await client.health()
        return _ok(
            {
                "healthy": status.ok,
                "network": status.network,
                "version": status.version,
                "evm_network": status.evm_network,
                "uptime_seconds": status.uptime_seconds,
                "build_commit": status.build_commit,
                "payment_token_address": status.payment_token_address,
                "payment_vault_address": status.payment_vault_address,
            },
            network,
        )
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


def _prepare_result_to_dict(result) -> dict:
    """Convert a PrepareUploadResult to a JSON-safe dict."""
    d: dict = {
        "upload_id": result.upload_id,
        "payment_type": result.payment_type or "wave_batch",
        "total_amount": result.total_amount,
        "payment_token_address": result.payment_token_address,
        "rpc_url": result.rpc_url,
        # Already-stored preflight (added in antd 0.10.0). 0 on older daemons.
        "total_chunks": getattr(result, "total_chunks", 0),
        "already_stored_count": getattr(result, "already_stored_count", 0),
    }
    d["payment_vault_address"] = result.payment_vault_address
    if result.payment_type == "merkle":
        d["depth"] = result.depth
        d["merkle_payment_timestamp"] = result.merkle_payment_timestamp
        d["pool_commitments"] = [
            {
                "pool_hash": pc.pool_hash,
                "candidates": [
                    {"rewards_address": c.rewards_address, "amount": c.amount}
                    for c in pc.candidates
                ],
            }
            for pc in result.pool_commitments
        ]
    else:
        d["payments"] = [
            {
                "quote_hash": p.quote_hash,
                "rewards_address": p.rewards_address,
                "amount": p.amount,
            }
            for p in result.payments
        ]
    return d


@mcp.tool()
async def prepare_upload(
    path: str,
    visibility: str | None = None,
) -> str:
    """Prepare a file upload for external signing (two-phase upload).

    Returns payment details with a payment_type discriminator:
    - "wave_batch": per-quote payments for payForQuotes() (< 64 chunks)
    - "merkle": depth, pool_commitments, timestamp for payForMerkleTree() (>= 64 chunks)

    For wave_batch, call finalize_upload with tx_hashes.
    For merkle, call finalize_merkle_upload with winner_pool_hash.

    Args:
        path: Absolute path to the local file to upload.
        visibility: ``"public"`` to bundle the DataMap chunk into the same
            external-signer payment batch (the ``data_map_address`` on
            ``finalize_upload`` becomes the shareable retrieval handle).
            ``"private"`` or ``None`` keeps the existing private-only
            behaviour.

    Returns:
        JSON with upload_id, payment_type, and type-specific payment fields.
    """
    client, network = _get_ctx()
    try:
        if visibility is None:
            result = await client.prepare_upload(path)
        else:
            result = await client.prepare_upload(path, visibility=visibility)
        return _ok(_prepare_result_to_dict(result), network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool: prepare_upload_public
# ---------------------------------------------------------------------------


@mcp.tool()
async def prepare_upload_public(
    path: str,
) -> str:
    """Prepare a *public* file upload for external signing (two-phase upload).

    Convenience wrapper equivalent to ``prepare_upload(path, visibility="public")``.
    The DataMap chunk is bundled into the same external-signer payment batch,
    so the ``data_map_address`` returned by ``finalize_upload`` is the
    shareable retrieval handle.

    Args:
        path: Absolute path to the local file to upload.

    Returns:
        JSON with upload_id, payment_type, and type-specific payment fields.
    """
    client, network = _get_ctx()
    try:
        result = await client.prepare_upload_public(path)
        return _ok(_prepare_result_to_dict(result), network)
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

    Takes base64-encoded data and returns payment details with a payment_type
    discriminator ("wave_batch" or "merkle"). See prepare_upload for details.

    Args:
        data: Base64-encoded bytes to upload.

    Returns:
        JSON with upload_id, payment_type, and type-specific payment fields.
    """
    client, network = _get_ctx()
    try:
        raw = base64.b64decode(data)
        result = await client.prepare_data_upload(raw)
        return _ok(_prepare_result_to_dict(result), network)
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
        JSON with ``address`` (hex), ``chunks_stored`` count, ``data_map``
        (hex-encoded msgpack DataMap — always returned), and
        ``data_map_address`` (set when prepare used ``visibility="public"``,
        empty otherwise).
    """
    client, network = _get_ctx()
    try:
        result = await client.finalize_upload(upload_id, tx_hashes)
        return _ok(
            {
                "address": result.address,
                "chunks_stored": result.chunks_stored,
                "data_map": result.data_map,
                "data_map_address": result.data_map_address,
            },
            network,
        )
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 15: finalize_merkle_upload
# ---------------------------------------------------------------------------


@mcp.tool()
async def finalize_merkle_upload(
    upload_id: str,
    winner_pool_hash: str,
) -> str:
    """Finalize a merkle two-phase upload after the merkle payment transaction.

    Use this instead of finalize_upload when prepare_upload returned
    payment_type "merkle". The winner_pool_hash comes from the
    MerklePaymentMade event emitted by the on-chain payForMerkleTree call.

    Args:
        upload_id: The upload ID returned by prepare_upload.
        winner_pool_hash: The bytes32 winner pool hash from MerklePaymentMade event (hex with 0x prefix).

    Returns:
        JSON with ``address`` (hex), ``chunks_stored`` count, ``data_map``
        (hex-encoded msgpack DataMap — always returned), and
        ``data_map_address`` (set when prepare used ``visibility="public"``,
        empty otherwise).
    """
    client, network = _get_ctx()
    try:
        result = await client.finalize_merkle_upload(upload_id, winner_pool_hash)
        return _ok(
            {
                "address": result.address,
                "chunks_stored": result.chunks_stored,
                "data_map": result.data_map,
                "data_map_address": result.data_map_address,
            },
            network,
        )
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool: prepare_chunk_upload
# ---------------------------------------------------------------------------


def _prepare_chunk_result_to_dict(result) -> dict:
    """Convert a PrepareChunkResult to a JSON-safe dict.

    Covers both branches:
    - ``already_stored=True``: returns the minimal shape (address only).
    - wave-batch payment intent: returns the full payment shape.
    """
    if result.already_stored:
        return {
            "address": result.address,
            "already_stored": True,
        }
    return {
        "address": result.address,
        "already_stored": False,
        "upload_id": result.upload_id,
        "payment_type": result.payment_type or "wave_batch",
        "total_amount": result.total_amount,
        "payment_vault_address": result.payment_vault_address,
        "payment_token_address": result.payment_token_address,
        "rpc_url": result.rpc_url,
        "payments": [
            {
                "quote_hash": p.quote_hash,
                "rewards_address": p.rewards_address,
                "amount": p.amount,
            }
            for p in result.payments
        ],
    }


@mcp.tool()
async def prepare_chunk_upload(
    data_base64: str,
) -> str:
    """Prepare a single raw chunk for external-signer publish.

    The returned JSON has one of two shapes:
    - ``already_stored=True``: chunk is already on-network. No payment or
      finalize step is needed; ``address`` is the network address.
    - ``already_stored=False``: a wave-batch payment intent with ``upload_id``,
      ``payments``, payment contract addresses, and ``rpc_url``. After the
      external signer pays, call ``finalize_chunk_upload`` with the tx hashes.

    Args:
        data_base64: Base64-encoded chunk bytes.

    Returns:
        JSON with the prepare-chunk result, or error details.
    """
    client, network = _get_ctx()
    try:
        raw = base64.b64decode(data_base64)
        result = await client.prepare_chunk_upload(raw)
        return _ok(_prepare_chunk_result_to_dict(result), network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool: finalize_chunk_upload
# ---------------------------------------------------------------------------


@mcp.tool()
async def finalize_chunk_upload(
    upload_id: str,
    tx_hashes: dict[str, str],
) -> str:
    """Submit a prepared chunk to the network after external payment.

    Args:
        upload_id: The upload ID returned by ``prepare_chunk_upload``.
        tx_hashes: Map of quote_hash to tx_hash for the wave-batch payments.

    Returns:
        JSON with ``address`` (hex) — the network address of the stored chunk.
    """
    client, network = _get_ctx()
    try:
        address = await client.finalize_chunk_upload(upload_id, tx_hashes)
        return _ok({"address": address}, network)
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
