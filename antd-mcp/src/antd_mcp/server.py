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
from antd.models import GraphDescendant, PointerTarget

from .errors import format_error, format_unexpected_error

# ---------------------------------------------------------------------------
# Lifespan — create/close a single AsyncRestClient for the server's lifetime
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(server: FastMCP):
    base_url = os.environ.get("ANTD_BASE_URL", "http://localhost:8080")
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
) -> str:
    """Store text on the Autonomi network.

    Args:
        text: The text content to store.
        private: If True, store as private (encrypted). Default: public.

    Returns:
        JSON with address and cost, or error details.
    """
    client, network = _get_ctx()
    data = text.encode("utf-8")
    try:
        if private:
            result = await client.data_put_private(data)
        else:
            result = await client.data_put_public(data)
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
) -> str:
    """Upload a local file or directory to the Autonomi network (public).

    Args:
        path: Absolute path to the local file or directory.
        is_directory: Set True if path is a directory.

    Returns:
        JSON with address and cost, or error details.
    """
    client, network = _get_ctx()
    try:
        if is_directory:
            result = await client.dir_upload_public(path)
        else:
            result = await client.file_upload_public(path)
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
        is_directory: Set True if the address points to a directory archive.

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
# Tool 5: create_pointer
# ---------------------------------------------------------------------------


@mcp.tool()
async def create_pointer(
    owner_secret_key: str,
    target_kind: str,
    target_address: str,
) -> str:
    """Create a mutable pointer on the Autonomi network.

    Args:
        owner_secret_key: Hex-encoded secret key of the pointer owner.
        target_kind: Type of target — "chunk", "graph_entry", "pointer", or "scratchpad".
        target_address: Hex address of the target.

    Returns:
        JSON with pointer address and cost, or error details.
    """
    client, network = _get_ctx()
    try:
        target = PointerTarget(kind=target_kind, address=target_address)
        result = await client.pointer_create(owner_secret_key, target)
        return _ok({"address": result.address, "cost": result.cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 6: update_pointer
# ---------------------------------------------------------------------------


@mcp.tool()
async def update_pointer(
    owner_secret_key: str,
    target_kind: str,
    target_address: str,
) -> str:
    """Update an existing pointer's target.

    Args:
        owner_secret_key: Hex-encoded secret key of the pointer owner.
        target_kind: New target type — "chunk", "graph_entry", "pointer", or "scratchpad".
        target_address: New target hex address.

    Returns:
        JSON confirming success, or error details.
    """
    client, network = _get_ctx()
    try:
        target = PointerTarget(kind=target_kind, address=target_address)
        await client.pointer_update(owner_secret_key, target)
        return _ok({"status": "updated"}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 7: create_scratchpad
# ---------------------------------------------------------------------------


@mcp.tool()
async def create_scratchpad(
    owner_secret_key: str,
    content_type: int,
    data: str,
) -> str:
    """Create a versioned scratchpad on the Autonomi network.

    Args:
        owner_secret_key: Hex-encoded secret key of the scratchpad owner.
        content_type: Integer encoding type for the data.
        data: Base64-encoded data to store.

    Returns:
        JSON with scratchpad address and cost, or error details.
    """
    client, network = _get_ctx()
    try:
        raw = base64.b64decode(data)
        result = await client.scratchpad_create(owner_secret_key, content_type, raw)
        return _ok({"address": result.address, "cost": result.cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 8: update_scratchpad
# ---------------------------------------------------------------------------


@mcp.tool()
async def update_scratchpad(
    owner_secret_key: str,
    content_type: int,
    data: str,
) -> str:
    """Update an existing scratchpad's contents.

    Args:
        owner_secret_key: Hex-encoded secret key of the scratchpad owner.
        content_type: Integer encoding type for the data.
        data: Base64-encoded new data.

    Returns:
        JSON confirming success, or error details.
    """
    client, network = _get_ctx()
    try:
        raw = base64.b64decode(data)
        await client.scratchpad_update(owner_secret_key, content_type, raw)
        return _ok({"status": "updated"}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 9: get_cost
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
# Tool 10: check_balance
# ---------------------------------------------------------------------------


@mcp.tool()
async def check_balance() -> str:
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
# Tool 11: chunk_put
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
# Tool 12: chunk_get
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
# Tool 13: get_pointer
# ---------------------------------------------------------------------------


@mcp.tool()
async def get_pointer(
    address: str,
) -> str:
    """Read a pointer's current target from the Autonomi network.

    Args:
        address: Hex address of the pointer.

    Returns:
        JSON with pointer details (address, owner, counter, target), or error details.
    """
    client, network = _get_ctx()
    try:
        p = await client.pointer_get(address)
        return _ok({
            "address": p.address,
            "owner": p.owner,
            "counter": p.counter,
            "target": {"kind": p.target.kind, "address": p.target.address},
        }, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 14: pointer_exists
# ---------------------------------------------------------------------------


@mcp.tool()
async def pointer_exists(
    address: str,
) -> str:
    """Check if a pointer exists on the Autonomi network.

    Args:
        address: Hex address of the pointer.

    Returns:
        JSON with exists boolean, or error details.
    """
    client, network = _get_ctx()
    try:
        exists = await client.pointer_exists(address)
        return _ok({"exists": exists}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 15: pointer_cost
# ---------------------------------------------------------------------------


@mcp.tool()
async def pointer_cost(
    public_key: str,
) -> str:
    """Estimate the cost to create a pointer.

    Args:
        public_key: Hex-encoded public key of the pointer owner.

    Returns:
        JSON with cost in atto tokens, or error details.
    """
    client, network = _get_ctx()
    try:
        cost = await client.pointer_cost(public_key)
        return _ok({"cost": cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 16: get_scratchpad
# ---------------------------------------------------------------------------


@mcp.tool()
async def get_scratchpad(
    address: str,
) -> str:
    """Read a scratchpad's contents from the Autonomi network.

    Args:
        address: Hex address of the scratchpad.

    Returns:
        JSON with scratchpad details (address, data_encoding, data as base64, counter),
        or error details.
    """
    client, network = _get_ctx()
    try:
        s = await client.scratchpad_get(address)
        return _ok({
            "address": s.address,
            "data_encoding": s.data_encoding,
            "data": base64.b64encode(s.data).decode(),
            "counter": s.counter,
        }, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 17: scratchpad_exists
# ---------------------------------------------------------------------------


@mcp.tool()
async def scratchpad_exists(
    address: str,
) -> str:
    """Check if a scratchpad exists on the Autonomi network.

    Args:
        address: Hex address of the scratchpad.

    Returns:
        JSON with exists boolean, or error details.
    """
    client, network = _get_ctx()
    try:
        exists = await client.scratchpad_exists(address)
        return _ok({"exists": exists}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 18: scratchpad_cost
# ---------------------------------------------------------------------------


@mcp.tool()
async def scratchpad_cost(
    public_key: str,
) -> str:
    """Estimate the cost to create a scratchpad.

    Args:
        public_key: Hex-encoded public key of the scratchpad owner.

    Returns:
        JSON with cost in atto tokens, or error details.
    """
    client, network = _get_ctx()
    try:
        cost = await client.scratchpad_cost(public_key)
        return _ok({"cost": cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 19: create_graph_entry
# ---------------------------------------------------------------------------


@mcp.tool()
async def create_graph_entry(
    owner_secret_key: str,
    content: str,
    parents: list[str] | None = None,
    descendants: list[dict] | None = None,
) -> str:
    """Create a graph entry (DAG node) on the Autonomi network.

    Args:
        owner_secret_key: Hex-encoded secret key of the graph entry owner.
        content: Hex-encoded content (32 bytes).
        parents: List of parent graph entry addresses. Default: empty.
        descendants: List of descendant objects, each with "public_key" and "content" (hex).
            Default: empty.

    Returns:
        JSON with graph entry address and cost, or error details.
    """
    client, network = _get_ctx()
    try:
        desc = [
            GraphDescendant(public_key=d["public_key"], content=d["content"])
            for d in (descendants or [])
        ]
        result = await client.graph_entry_put(
            owner_secret_key, parents or [], content, desc,
        )
        return _ok({"address": result.address, "cost": result.cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 20: get_graph_entry
# ---------------------------------------------------------------------------


@mcp.tool()
async def get_graph_entry(
    address: str,
) -> str:
    """Read a graph entry from the Autonomi network.

    Args:
        address: Hex address of the graph entry.

    Returns:
        JSON with graph entry details (owner, parents, content, descendants),
        or error details.
    """
    client, network = _get_ctx()
    try:
        g = await client.graph_entry_get(address)
        return _ok({
            "owner": g.owner,
            "parents": g.parents,
            "content": g.content,
            "descendants": [
                {"public_key": d.public_key, "content": d.content}
                for d in g.descendants
            ],
        }, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 21: graph_entry_exists
# ---------------------------------------------------------------------------


@mcp.tool()
async def graph_entry_exists(
    address: str,
) -> str:
    """Check if a graph entry exists on the Autonomi network.

    Args:
        address: Hex address of the graph entry.

    Returns:
        JSON with exists boolean, or error details.
    """
    client, network = _get_ctx()
    try:
        exists = await client.graph_entry_exists(address)
        return _ok({"exists": exists}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 22: graph_entry_cost
# ---------------------------------------------------------------------------


@mcp.tool()
async def graph_entry_cost(
    public_key: str,
) -> str:
    """Estimate the cost to create a graph entry.

    Args:
        public_key: Hex-encoded public key of the graph entry owner.

    Returns:
        JSON with cost in atto tokens, or error details.
    """
    client, network = _get_ctx()
    try:
        cost = await client.graph_entry_cost(public_key)
        return _ok({"cost": cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 23: create_register
# ---------------------------------------------------------------------------


@mcp.tool()
async def create_register(
    owner_secret_key: str,
    initial_value: str,
) -> str:
    """Create a register on the Autonomi network.

    Args:
        owner_secret_key: Hex-encoded secret key of the register owner.
        initial_value: Hex-encoded initial value (32 bytes).

    Returns:
        JSON with register address and cost, or error details.
    """
    client, network = _get_ctx()
    try:
        result = await client.register_create(owner_secret_key, initial_value)
        return _ok({"address": result.address, "cost": result.cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 24: get_register
# ---------------------------------------------------------------------------


@mcp.tool()
async def get_register(
    address: str,
) -> str:
    """Read a register's value from the Autonomi network.

    Args:
        address: Hex address of the register.

    Returns:
        JSON with the register value (hex), or error details.
    """
    client, network = _get_ctx()
    try:
        r = await client.register_get(address)
        return _ok({"value": r.value}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 25: update_register
# ---------------------------------------------------------------------------


@mcp.tool()
async def update_register(
    owner_secret_key: str,
    new_value: str,
) -> str:
    """Update a register's value on the Autonomi network.

    Args:
        owner_secret_key: Hex-encoded secret key of the register owner.
        new_value: Hex-encoded new value (32 bytes).

    Returns:
        JSON with cost, or error details.
    """
    client, network = _get_ctx()
    try:
        result = await client.register_update(owner_secret_key, new_value)
        return _ok({"cost": result.cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 26: register_cost
# ---------------------------------------------------------------------------


@mcp.tool()
async def register_cost(
    public_key: str,
) -> str:
    """Estimate the cost to create a register.

    Args:
        public_key: Hex-encoded public key of the register owner.

    Returns:
        JSON with cost in atto tokens, or error details.
    """
    client, network = _get_ctx()
    try:
        cost = await client.register_cost(public_key)
        return _ok({"cost": cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 27: vault_put
# ---------------------------------------------------------------------------


@mcp.tool()
async def vault_put(
    secret_key: str,
    data: str,
    content_type: int,
) -> str:
    """Store data in a vault on the Autonomi network.

    Args:
        secret_key: Hex-encoded secret key for the vault.
        data: Base64-encoded data to store.
        content_type: Integer content type identifier.

    Returns:
        JSON with cost, or error details.
    """
    client, network = _get_ctx()
    try:
        raw = base64.b64decode(data)
        cost = await client.vault_put(secret_key, raw, content_type)
        return _ok({"cost": cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 28: vault_get
# ---------------------------------------------------------------------------


@mcp.tool()
async def vault_get(
    secret_key: str,
) -> str:
    """Retrieve data from a vault on the Autonomi network.

    Args:
        secret_key: Hex-encoded secret key for the vault.

    Returns:
        JSON with base64-encoded data and content_type, or error details.
    """
    client, network = _get_ctx()
    try:
        v = await client.vault_get(secret_key)
        return _ok({
            "data": base64.b64encode(v.data).decode(),
            "content_type": v.content_type,
        }, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 29: vault_cost
# ---------------------------------------------------------------------------


@mcp.tool()
async def vault_cost(
    secret_key: str,
    max_size: int,
) -> str:
    """Estimate the cost to store data in a vault.

    Args:
        secret_key: Hex-encoded secret key for the vault.
        max_size: Maximum data size in bytes.

    Returns:
        JSON with cost in atto tokens, or error details.
    """
    client, network = _get_ctx()
    try:
        cost = await client.vault_cost(secret_key, max_size)
        return _ok({"cost": cost}, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 30: archive_get
# ---------------------------------------------------------------------------


@mcp.tool()
async def archive_get(
    address: str,
) -> str:
    """List files in a public archive on the Autonomi network.

    Args:
        address: Hex address of the archive.

    Returns:
        JSON with list of archive entries (path, address, created, modified, size),
        or error details.
    """
    client, network = _get_ctx()
    try:
        archive = await client.archive_get_public(address)
        return _ok({
            "entries": [
                {
                    "path": e.path,
                    "address": e.address,
                    "created": e.created,
                    "modified": e.modified,
                    "size": e.size,
                }
                for e in archive.entries
            ],
        }, network)
    except AntdError as exc:
        return _err_antd(exc, network)
    except Exception as exc:
        return _err(exc, network)


# ---------------------------------------------------------------------------
# Tool 31: archive_put
# ---------------------------------------------------------------------------


@mcp.tool()
async def archive_put(
    entries: list[dict],
) -> str:
    """Create a public archive from a list of file entries.

    Args:
        entries: List of entry objects, each with "path", "address", "created",
            "modified", and "size" fields.

    Returns:
        JSON with archive address and cost, or error details.
    """
    client, network = _get_ctx()
    try:
        from antd.models import Archive, ArchiveEntry
        archive = Archive(entries=[
            ArchiveEntry(
                path=e["path"],
                address=e["address"],
                created=e["created"],
                modified=e["modified"],
                size=e["size"],
            )
            for e in entries
        ])
        result = await client.archive_put_public(archive)
        return _ok({"address": result.address, "cost": result.cost}, network)
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
