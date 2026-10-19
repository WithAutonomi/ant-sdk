"""MCP server exposing Autonomi network operations as tools."""

from __future__ import annotations

import base64
import json
import os
import sys
from contextlib import asynccontextmanager

from mcp.server.mcpserver import Context, MCPServer
from mcp.types import ToolAnnotations

from antd import AsyncAntdClient, PaymentMode
from antd.exceptions import AntdError
from .discover import discover_daemon_url
from .errors import format_error, format_unexpected_error

# The pointer tools need an antd SDK with the pointer API (newer than 0.2.0).
# Against an older SDK the server still starts and serves every other tool;
# the pointer tools are simply not registered (see ``_pointer_tool``).
try:
    from antd import PointerKind, PointerOp
    from antd._rest import AsyncRestClient as _AsyncRestClient
except ImportError:  # antd SDK without the pointer API
    PointerKind = None  # type: ignore[assignment,misc]
    PointerOp = None  # type: ignore[assignment,misc]
    POINTERS_AVAILABLE = False
else:
    POINTERS_AVAILABLE = hasattr(_AsyncRestClient, "pointer_get")

# ---------------------------------------------------------------------------
# Lifespan — create/close a single AsyncRestClient for the server's lifetime
# ---------------------------------------------------------------------------

_DEFAULT_BASE_URL = "http://127.0.0.1:8082"


@asynccontextmanager
async def lifespan(server: MCPServer):
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


mcp = MCPServer(
    "antd-autonomi",
    instructions="Autonomi network operations via antd daemon",
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _get_ctx(ctx: Context):
    """Return (client, network) from the lifespan context.

    mcp 2.x injects ``ctx`` into any tool that declares a ``Context``-typed
    parameter (it is stripped from the tool's input schema); the 1.x
    ``mcp.get_context()`` accessor no longer exists.
    """
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
    ctx: Context,
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
    client, network = _get_ctx(ctx)
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
    ctx: Context,
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
    client, network = _get_ctx(ctx)
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
    ctx: Context,
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
    client, network = _get_ctx(ctx)
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
    ctx: Context,
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
    client, network = _get_ctx(ctx)
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
# Tool: stream_download_file
# ---------------------------------------------------------------------------


@mcp.tool()
async def stream_download_file(
    ctx: Context,
    address: str,
    dest_path: str,
    private: bool = False,
) -> str:
    """Download a network object to a local path, streaming with constant memory.

    Unlike ``download_file`` (which asks the daemon to write the file
    server-side, requiring the daemon and this MCP server to share a
    filesystem), this tool streams the raw bytes back to the MCP server process
    and writes them to ``dest_path`` on **this** host, one chunk at a time. It
    never buffers the whole object in memory, so it suits large objects.

    Args:
        address: The on-network address (public) or the caller-held DataMap
            (private).
        dest_path: Local path (on the MCP server host) to write the bytes to.
        private: If True, treat ``address`` as a caller-held DataMap and stream
            the private object. Default: public.

    Returns:
        JSON with ``status``, ``dest_path``, and ``bytes_written``, or error
        details.
    """
    client, network = _get_ctx(ctx)
    try:
        bytes_written = 0
        if private:
            stream_cm = client.data_stream(address)
        else:
            stream_cm = client.data_stream_public(address)
        with open(dest_path, "wb") as out:
            async with stream_cm as chunks:
                async for chunk in chunks:
                    out.write(chunk)
                    bytes_written += len(chunk)
        return _ok(
            {
                "status": "downloaded",
                "dest_path": dest_path,
                "bytes_written": bytes_written,
            },
            network,
        )
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 5: get_cost
# ---------------------------------------------------------------------------


@mcp.tool()
async def get_cost(
    ctx: Context,
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
    client, network = _get_ctx(ctx)
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
async def check_health(ctx: Context) -> str:
    """Check antd daemon health and network status.

    Returns:
        JSON with health, network, and (when reported by antd >= 0.4.0)
        diagnostic fields: version, evm_network, uptime_seconds,
        build_commit, payment_token_address, payment_vault_address.
    """
    client, network = _get_ctx(ctx)
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
async def wallet_address(ctx: Context) -> str:
    """Get the wallet's public address from the antd daemon.

    Returns:
        JSON with the wallet address (e.g. "0x..."), or error details.
        Returns an error if no wallet is configured.
    """
    client, network = _get_ctx(ctx)
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
async def wallet_balance(ctx: Context) -> str:
    """Get the wallet's token and gas balances from the antd daemon.

    Returns:
        JSON with balance (token balance) and gas_balance (gas token balance),
        both as strings in atto units. Returns an error if no wallet is configured.
    """
    client, network = _get_ctx(ctx)
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
    ctx: Context,
    data: str,
) -> str:
    """Store a raw chunk on the Autonomi network.

    Args:
        data: Base64-encoded chunk data.

    Returns:
        JSON with chunk address and cost, or error details.
    """
    client, network = _get_ctx(ctx)
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
    ctx: Context,
    address: str,
) -> str:
    """Retrieve a raw chunk from the Autonomi network.

    Args:
        address: Hex address of the chunk.

    Returns:
        JSON with base64-encoded chunk data, or error details.
    """
    client, network = _get_ctx(ctx)
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
async def wallet_approve(ctx: Context) -> str:
    """Approve the wallet to spend tokens on payment contracts.

    This is a one-time operation required before any storage operations.
    Must be called after configuring a wallet but before storing data.

    Returns:
        JSON with approved boolean, or error details.
    """
    client, network = _get_ctx(ctx)
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
    ctx: Context,
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
    client, network = _get_ctx(ctx)
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
    ctx: Context,
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
    client, network = _get_ctx(ctx)
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
    ctx: Context,
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
    client, network = _get_ctx(ctx)
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
    ctx: Context,
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

    Errors:
        ``error: "PARTIAL_UPLOAD"`` means the payment went through but only
        some chunks stored (``chunks_stored`` / ``chunks_failed`` /
        ``total_chunks``). The stored chunks and the payment persist.
        ``retryable`` true: the daemon kept the paid attempt under this
        ``upload_id``; call this same tool again with the same arguments to
        store the remainder against the same payment (no re-prepare, no
        second payment). Bound the retries -- stop after a few attempts or
        when ``chunks_failed`` stops shrinking.
        ``retention_known`` true and ``retryable`` false: the daemon
        confirmed it kept nothing; re-run the prepare step for the same
        content (already-stored chunks are skipped, so only the remainder is
        paid for).
        ``retention_known`` false: retention is unknown and the daemon may
        still hold the paid attempt. Stop, keep the ``upload_id`` and the
        payment details you passed, and reconcile before preparing or paying
        again. Never pay again on this signal alone.
    """
    client, network = _get_ctx(ctx)
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
    ctx: Context,
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

    Errors:
        ``error: "PARTIAL_UPLOAD"`` means the payment went through but only
        some chunks stored (``chunks_stored`` / ``chunks_failed`` /
        ``total_chunks``). The stored chunks and the payment persist.
        ``retryable`` true: the daemon kept the paid attempt under this
        ``upload_id``; call this same tool again with the same arguments to
        store the remainder against the same payment (no re-prepare, no
        second payment). Bound the retries -- stop after a few attempts or
        when ``chunks_failed`` stops shrinking.
        ``retention_known`` true and ``retryable`` false: the daemon
        confirmed it kept nothing; re-run the prepare step for the same
        content (already-stored chunks are skipped, so only the remainder is
        paid for).
        ``retention_known`` false: retention is unknown and the daemon may
        still hold the paid attempt. Stop, keep the ``upload_id`` and the
        payment details you passed, and reconcile before preparing or paying
        again. Never pay again on this signal alone.
    """
    client, network = _get_ctx(ctx)
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
    ctx: Context,
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
    client, network = _get_ctx(ctx)
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
    ctx: Context,
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
    client, network = _get_ctx(ctx)
    try:
        address = await client.finalize_chunk_upload(upload_id, tx_hashes)
        return _ok({"address": address}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Pointers
# ---------------------------------------------------------------------------
#
# A pointer is a small, owner-signed, mutable reference. Its address never
# changes; its target (a chunk, such as a public data or file address, or
# another pointer) can be moved by its owner. antd holds the owner keys
# (``antd --pointer-keys``), so a write names the pointer by its address.
#
# The writes pay from the daemon wallet with the same posture as the upload
# tools: no confirmation step, no cost pre-check, and no retry. A transfer is
# irreversible, so pointer_transfer additionally refuses to run unless the
# caller passes ``confirm_irreversible=true``.
#
# Counters leave as decimal strings, never JSON numbers: a final pointer sits
# at 2**64-1, which clients that read JSON numbers as doubles (and LLMs)
# round.


def _pointer_tool(**kwargs):
    """``mcp.tool(**kwargs)`` when the antd SDK has the pointer API.

    Against an older SDK the function stays defined but unregistered, so the
    server lists only the tools it can serve.
    """

    def register(fn):
        return mcp.tool(**kwargs)(fn) if POINTERS_AVAILABLE else fn

    return register


def _pk(kind: str):
    """Coerce a wire-format pointer kind string to the PointerKind enum.

    Raises ValueError if the string is not "chunk" or "pointer" (reported as
    an error before anything is sent), like ``_pm`` for payment modes.
    """
    return PointerKind(kind)


def _counter(value: int | None) -> str | None:
    """A pointer counter as a decimal string; unset stays ``None``."""
    return None if value is None else str(value)


def _pointer_write_to_dict(result) -> dict:
    """Convert a PointerWriteResult to a JSON-safe dict."""
    return {
        "address": result.address,
        "state_id": result.state_id,
        "counter": _counter(result.counter),
    }


def _final_state_to_dict(state) -> dict | None:
    """Convert a PointerFinalState (or None) to a JSON-safe dict."""
    if state is None:
        return None
    return {
        "state_id": state.state_id,
        "kind": state.kind,
        "kind_tag": state.kind_tag,
        "target": state.target,
        "holders": state.holders,
        "transferred_to": state.transferred_to,
    }


def _finality_to_dict(finality) -> dict | None:
    """Convert a PointerFinality (or None) to a JSON-safe dict."""
    if finality is None:
        return None
    return {
        "address": finality.address,
        "status": finality.status.value,
        "raw_status": finality.raw_status,
        "is_final": finality.is_final,
        "group": finality.group,
        "answered": finality.answered,
        "counter": _counter(finality.counter),
        "state": _final_state_to_dict(finality.state),
        "states": [_final_state_to_dict(s) for s in finality.states],
        "majority": _final_state_to_dict(finality.majority),
        "transferred_to": finality.transferred_to,
    }


def _pointer_prepare_result_to_dict(result) -> dict:
    """Convert a PointerPrepareResult to a JSON-safe dict."""
    return {
        "upload_id": result.upload_id,
        "op": result.op,
        "address": result.address,
        "state_id": result.state_id,
        "counter": _counter(result.counter),
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


# ---------------------------------------------------------------------------
# Tool: pointer_keys
# ---------------------------------------------------------------------------


@_pointer_tool()
async def pointer_keys(ctx: Context) -> str:
    """List the pointers this antd daemon can write. Free.

    antd signs pointer writes with owner keys it loaded at startup
    (``antd --pointer-keys``). Every pointer write names the pointer by its
    address (``owner``), and only the addresses listed here can be written
    through this daemon.

    Returns:
        JSON with ``keys``: the writable pointer addresses (64-char hex), or
        error details.
    """
    client, network = _get_ctx(ctx)
    try:
        keys = await client.pointer_keys()
        return _ok({"keys": keys}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool: pointer_get
# ---------------------------------------------------------------------------


@_pointer_tool()
async def pointer_get(
    ctx: Context,
    address: str,
    include_owner_key: bool = False,
) -> str:
    """Read a pointer's current state from the Autonomi network. Free.

    A pointer is a small, owner-signed, mutable reference: its address never
    changes, and its owner can move its target (a chunk, such as a public
    data or file address, or another pointer).

    Counters are decimal strings, not JSON numbers: a final pointer's counter
    is "18446744073709551615" (2^64-1), which JSON number parsing rounds.
    Compare counters as strings of digits or as big integers.

    Args:
        address: The pointer's address (64-char hex, ``0x`` optional).
        include_owner_key: If True, also return ``owner``, the owner's
            ML-DSA-65 public key (about 3,900 hex characters). Default: left
            out.

    Returns:
        JSON with ``address``, ``counter`` (decimal string), ``target``,
        ``kind`` ("chunk", "pointer", or "unknown" for a kind the daemon does
        not know), ``kind_tag``, ``state_id``, ``is_final`` (true once
        transferred or frozen: nothing can change it again) and
        ``transferred_to`` (the pointer it was handed over to, or null), or
        error details (``NOT_FOUND`` when no pointer exists there).
    """
    client, network = _get_ctx(ctx)
    try:
        record = await client.pointer_get(address)
        d = {
            "address": record.address,
            "counter": _counter(record.counter),
            "target": record.target,
            "kind": record.kind,
            "kind_tag": record.kind_tag,
            "state_id": record.state_id,
            "is_final": record.is_final,
            "transferred_to": record.transferred_to,
        }
        if include_owner_key:
            d["owner"] = record.owner
        return _ok(d, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool: pointer_resolve
# ---------------------------------------------------------------------------


@_pointer_tool()
async def pointer_resolve(
    ctx: Context,
    address: str,
) -> str:
    """Follow a chain of pointers to the target at its end. Free.

    Follows forwardings (pointers that point at pointers) and transfers
    alike. When ``kind`` is "chunk", ``target`` is an address that
    ``retrieve_data`` / ``download_file`` can fetch, if it was stored as
    public data or a public file.

    Args:
        address: The pointer's address (64-char hex, ``0x`` optional).

    Returns:
        JSON with ``target`` (hex), ``kind`` and ``kind_tag``, or error
        details (``NOT_FOUND`` when a pointer on the chain does not exist).
    """
    client, network = _get_ctx(ctx)
    try:
        target = await client.pointer_resolve(address)
        return _ok(
            {"target": target.target, "kind": target.kind, "kind_tag": target.kind_tag},
            network,
        )
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool: pointer_finality
# ---------------------------------------------------------------------------


@_pointer_tool()
async def pointer_finality(
    ctx: Context,
    address: str,
) -> str:
    """Ask a pointer's whole close group where it stands. Free.

    Check this before relying on a transfer: only ``status`` "final"
    (``is_final`` true) means one final state, held by a majority, with every
    peer answering and no rival seen.

    ``status`` is one of:
    - "open": no peer holds a final state; the owner can still move it.
    - "settling": one final state, not yet held by a majority.
    - "unconfirmed": one final state held by a majority, but not every peer
      answered. Ask again.
    - "final": beyond dispute.
    - "forked": the owner signed two or more different final states.
    - "unknown": a status this server does not know; ``raw_status`` has the
      daemon's string.

    Args:
        address: The pointer's address (64-char hex, ``0x`` optional).

    Returns:
        JSON with ``status``, ``raw_status``, ``is_final``, ``group`` (peers
        in the close group), ``answered``, ``counter`` (decimal string, "open"
        only; null otherwise), ``state`` (the one final state seen: settling,
        unconfirmed, final), ``states`` and ``majority`` (forked), and
        ``transferred_to`` (set once a transfer is final), or error details.
    """
    client, network = _get_ctx(ctx)
    try:
        finality = await client.pointer_finality(address)
        return _ok(_finality_to_dict(finality), network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool: pointer_controller
# ---------------------------------------------------------------------------


@_pointer_tool()
async def pointer_controller(
    ctx: Context,
    address: str,
) -> str:
    """Find whose pointer now decides what an address resolves to. Free.

    Follows every transfer from ``address`` to the pointer at the end of the
    hand-overs; that pointer's owner is the one who can move the target.

    Args:
        address: The pointer's address (64-char hex, ``0x`` optional).

    Returns:
        JSON with ``pointer`` (the deciding pointer's address), ``transfers``
        (every pointer handed over to, in order) and ``frozen`` (true when
        ``pointer`` is final without having been handed over: nobody can move
        it), or error details.
    """
    client, network = _get_ctx(ctx)
    try:
        controller = await client.pointer_controller(address)
        return _ok(
            {
                "pointer": controller.pointer,
                "transfers": list(controller.transfers),
                "frozen": controller.frozen,
            },
            network,
        )
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool: pointer_create
# ---------------------------------------------------------------------------


@_pointer_tool()
async def pointer_create(
    ctx: Context,
    owner: str,
    target: str,
    kind: str = "chunk",
) -> str:
    """Create a pointer on the Autonomi network, pointing at ``target``.

    Pays from the daemon wallet, about the price of one chunk. Every call
    pays again and this tool never retries: do not repeat a failed call
    without checking the pointer first (``pointer_get``).

    Args:
        owner: The pointer's address (64-char hex). The daemon must hold its
            key (see ``pointer_keys``).
        target: The address to point at (hex), e.g. the ``address`` from a
            public ``store_data`` or ``upload_file``.
        kind: "chunk" (default) for an immutable chunk such as a public data
            or file address, or "pointer" to forward to another pointer.

    Returns:
        JSON with ``address``, ``state_id`` and ``counter`` (decimal string),
        or error details. ``ALREADY_EXISTS``: the pointer exists (refused
        before paying); use ``pointer_update``. ``CONFLICT``: a prepared
        write to it awaits payment.
    """
    client, network = _get_ctx(ctx)
    try:
        result = await client.pointer_create(owner, target, _pk(kind))
        return _ok(_pointer_write_to_dict(result), network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool: pointer_update
# ---------------------------------------------------------------------------


@_pointer_tool()
async def pointer_update(
    ctx: Context,
    owner: str,
    target: str,
    kind: str = "chunk",
) -> str:
    """Point an existing pointer at a new target (creates it if missing).

    Pays from the daemon wallet, about the price of one chunk. Every call
    pays again and this tool never retries: do not repeat a failed call
    without checking the pointer first (``pointer_get``).

    Args:
        owner: The pointer's address (64-char hex). The daemon must hold its
            key (see ``pointer_keys``).
        target: The new address to point at (hex).
        kind: "chunk" (default) for an immutable chunk such as a public data
            or file address, or "pointer" to forward to another pointer (a
            forwarding the owner can still change).

    Returns:
        JSON with ``address``, ``state_id`` and ``counter`` (decimal string,
        one higher than before), or error details. ``POINTER_FINAL``: the
        pointer was transferred or frozen and can never change (usually
        refused before paying). ``CONFLICT``: a prepared write to it awaits
        payment (refused before paying), or the update lost to a newer state
        (possibly after paying); the ``hint`` says which.
    """
    client, network = _get_ctx(ctx)
    try:
        result = await client.pointer_update(owner, target, _pk(kind))
        return _ok(_pointer_write_to_dict(result), network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool: pointer_transfer
# ---------------------------------------------------------------------------


@_pointer_tool(
    annotations=ToolAnnotations(
        title="Transfer a pointer (irreversible)",
        read_only_hint=False,
        destructive_hint=True,
        idempotent_hint=False,
        open_world_hint=True,
    ),
)
async def pointer_transfer(
    ctx: Context,
    owner: str,
    recipient: str,
    confirm_irreversible: bool = False,
) -> str:
    """IRREVERSIBLE: hand the pointer at ``owner`` over to ``recipient`` forever.

    A transfer makes the pointer at ``owner`` final for good. Nobody can ever
    update or transfer it again, including its owner. Readers of ``owner``'s
    address are sent on to the pointer at ``recipient``, which only the
    recipient's owner can move. There is no undo.

    Pays from the daemon wallet, about the price of one chunk. Every call
    pays again and this tool never retries.

    Only call this after the user has explicitly confirmed this exact
    transfer, both addresses included. Unless ``confirm_irreversible`` is
    true the tool sends and pays nothing, and returns
    ``CONFIRMATION_REQUIRED``.

    Args:
        owner: The address of the pointer to hand over. The daemon must hold
            its key (see ``pointer_keys``).
        recipient: The address of the pointer to hand it to. It must exist
            and must not lead back to ``owner``.
        confirm_irreversible: Must be true to proceed. Set it only once the
            user has confirmed the transfer.

    Returns:
        JSON with ``address``, ``state_id`` and ``finality`` (the close
        group's view, shaped as ``pointer_finality`` returns it). When that
        check failed, ``finality`` is null and ``finality_error`` says why;
        the transfer is stored and final either way, so ask again with
        ``pointer_finality`` and do not call this again. Errors:
        ``POINTER_FINAL`` (already final; usually refused before paying),
        ``BAD_REQUEST``
        (``recipient`` missing or leads back).
    """
    client, network = _get_ctx(ctx)
    if confirm_irreversible is not True:
        return _ok(
            {
                "error": "CONFIRMATION_REQUIRED",
                "message": (
                    f"pointer_transfer would hand the pointer {owner} over to "
                    f"{recipient} forever: it becomes final, can never be "
                    "updated or transferred again, and its readers are sent "
                    "to the recipient's pointer. It also pays from the daemon "
                    "wallet. Nothing was sent or paid. Confirm with the user, "
                    "then call again with confirm_irreversible=true."
                ),
            },
            network,
        )
    try:
        result = await client.pointer_transfer(owner, recipient)
        return _ok(
            {
                "address": result.address,
                "state_id": result.state_id,
                "finality": _finality_to_dict(result.finality),
                "finality_error": result.finality_error,
            },
            network,
        )
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool: pointer_prepare
# ---------------------------------------------------------------------------


@_pointer_tool()
async def pointer_prepare(
    ctx: Context,
    owner: str,
    op: str,
    target: str | None = None,
    kind: str | None = None,
    recipient: str | None = None,
) -> str:
    """Prepare a pointer write for external signing (two-phase, like
    ``prepare_upload``).

    The daemon signs the write with the owner key it holds and quotes it. It
    pays nothing itself and needs no daemon wallet. Pay ``payments`` with
    ``payForQuotes()``, then call ``pointer_finalize`` with the tx hashes.
    Until the write is finalized or expires (one hour), other writes to the
    pointer fail with ``CONFLICT``.

    Args:
        owner: The pointer's address (64-char hex). The daemon must hold its
            key (see ``pointer_keys``).
        op: "create" or "update" (pass ``target``, and optionally ``kind``),
            or "transfer" (pass ``recipient``). A finalized transfer is
            IRREVERSIBLE: the pointer becomes final forever and its readers
            are sent on to ``recipient``'s pointer.
        target: For create / update: the address to point at (hex).
        kind: For create / update: "chunk" (the daemon's default) or
            "pointer".
        recipient: For transfer: the address of the pointer to hand it to.

    Returns:
        JSON with ``upload_id``, ``op``, ``address``, ``state_id``,
        ``counter`` (decimal string), ``payment_type`` ("wave_batch"),
        ``total_amount``, ``payments`` (``quote_hash``, ``rewards_address``,
        ``amount``), ``payment_vault_address``, ``payment_token_address`` and
        ``rpc_url``, or error details. The checks a daemon-wallet write makes
        before paying are made here, so ``ALREADY_EXISTS``,
        ``POINTER_FINAL`` and ``BAD_REQUEST`` arrive before any quote.
    """
    client, network = _get_ctx(ctx)
    try:
        result = await client.pointer_prepare(
            owner,
            PointerOp(op),
            target=target,
            kind=None if kind is None else _pk(kind),
            recipient=recipient,
        )
        return _ok(_pointer_prepare_result_to_dict(result), network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool: pointer_finalize
# ---------------------------------------------------------------------------


@_pointer_tool()
async def pointer_finalize(
    ctx: Context,
    upload_id: str,
    tx_hashes: dict[str, str],
) -> str:
    """Store a prepared pointer write after the external signer has paid.

    A finalized transfer is irreversible. This tool never retries.

    Args:
        upload_id: The upload ID returned by ``pointer_prepare``.
        tx_hashes: Map of quote_hash to tx_hash for each payment.

    Returns:
        JSON with ``address``, ``state_id``, ``counter`` (decimal string) and
        ``finality`` (for a transfer, shaped as ``pointer_finality`` returns
        it; null otherwise), or error details.

    Errors:
        ``CLOSE_GROUP_SHORTFALL`` with ``retryable`` true: retry the
        finalize, the payment was kept. Call this same tool again with the
        same ``upload_id`` (``tx_hashes`` is ignored on a repeat) to store
        the paid state against the same payment, with no second payment.
        Stop after a few attempts; the kept attempt expires after one hour.
        With ``retryable`` false nothing was kept.
        ``BAD_REQUEST``: the hashes do not match the payment. The session is
        kept, so correct them and call again.
        ``NOT_FOUND``: the ``upload_id`` expired or was already finalized.
    """
    client, network = _get_ctx(ctx)
    try:
        result = await client.pointer_finalize(upload_id, tx_hashes)
        return _ok(
            {
                "address": result.address,
                "state_id": result.state_id,
                "counter": _counter(result.counter),
                "finality": _finality_to_dict(result.finality),
            },
            network,
        )
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main():
    transport = "stdio"
    if "--http" in sys.argv:
        transport = "streamable-http"
    elif "--sse" in sys.argv:
        transport = "sse"
    mcp.run(transport=transport)


if __name__ == "__main__":
    main()
