"""Manifest tools: build and decode ADR-0006 ``.ant`` files and ``ant://`` links.

Kept in its own module so it stays clear of server.py. server.py calls
``register(mcp)`` once, after its own tools, and the tools are registered only
when the installed antd SDK has the manifest API (0.3.0 or later). Against an
older SDK the server still starts and serves every other tool.

Neither tool pays or uploads anything, so neither asks for confirmation.
"""

from __future__ import annotations

import base64
import binascii
import json

from mcp.server.mcpserver import Context, MCPServer
from mcp.types import ToolAnnotations

from antd.exceptions import AntdError, BadRequestError

from ._fields import sha256_of

try:
    from antd import ManifestEntryInfo, ManifestEntryInput
    from antd._rest import AsyncRestClient as _AsyncRestClient
except ImportError:  # antd SDK without the manifest API
    ManifestEntryInfo = None  # type: ignore[assignment,misc]
    ManifestEntryInput = None  # type: ignore[assignment,misc]
    MANIFESTS_AVAILABLE = False
else:
    MANIFESTS_AVAILABLE = hasattr(_AsyncRestClient, "build_manifest")

_ENTRY_KEYS = ("path", "size", "data_map", "address", "sha256")


def _server():
    # Imported lazily: server.py imports this module, and tests monkeypatch
    # ``server._get_ctx``.
    from . import server

    return server


def _entry_input(i: int, raw: object) -> "ManifestEntryInput":
    """One tool-argument entry as a ManifestEntryInput. Problems read as the
    daemon's own ``entries[i]: ...`` wording. The SDK still makes the
    both-or-neither and size checks."""
    if not isinstance(raw, dict):
        raise BadRequestError(f"entries[{i}]: must be an object with path, size, data_map or address")
    unknown = sorted(set(raw) - set(_ENTRY_KEYS))
    if unknown:
        raise BadRequestError(
            f"entries[{i}]: unknown field {unknown[0]!r} (allowed: {', '.join(_ENTRY_KEYS)})"
        )
    for key in ("path", "data_map", "address", "sha256"):
        value = raw.get(key)
        if value is not None and not isinstance(value, str):
            raise BadRequestError(f"entries[{i}]: {key} must be a string")
    kwargs = {}
    if raw.get("sha256") is not None:
        # Passed through as given (no hex, length or case check): the daemon
        # validates it. Built as a keyword only when set, so an SDK without
        # the field still accepts every other entry.
        kwargs["sha256"] = raw["sha256"]
    try:
        return ManifestEntryInput(
            data_map=raw.get("data_map"),
            address=raw.get("address"),
            path=raw.get("path"),
            size=raw.get("size"),
            **kwargs,
        )
    except TypeError:
        if not kwargs:
            raise
        # The installed antd SDK predates the sha256 field.
        raise BadRequestError(
            f"entries[{i}]: sha256 needs antd SDK 0.4.0 or later (and antd 0.17.0 or later on the daemon)"
        ) from None


def _entry_dict(e: "ManifestEntryInfo") -> dict:
    """An entry as JSON. Sizes are plain numbers (never near 2^53); an unset
    size or exact_size is null, never 0, and so is an unset sha256."""
    return {
        "effective_name": e.effective_name,
        "path": e.path,
        "size": e.size,
        "kind": e.kind,
        "content_address": e.content_address,
        "data_map": e.data_map,
        "exact_size": e.exact_size,
        "error": e.error,
        "sha256": sha256_of(e),
    }


def _bad_request(message: str, network: str) -> str:
    d = _server().format_error(BadRequestError(message))
    d["network"] = network
    return json.dumps(d)


_BUILD_ANNOTATIONS = ToolAnnotations(
    title="Build a manifest",
    read_only_hint=True,
    destructive_hint=False,
    idempotent_hint=True,
    open_world_hint=True,
)
_DECODE_ANNOTATIONS = ToolAnnotations(
    title="Decode a manifest",
    read_only_hint=True,
    destructive_hint=False,
    idempotent_hint=True,
    open_world_hint=True,
)


async def build_manifest(
    ctx: Context,
    entries: list[dict],
    name: str | None = None,
    torrent_info_hashes: list[str] | None = None,
    embed_roots: bool = True,
) -> str:
    """Build a manifest (a ``.ant`` file) that bundles several already-uploaded
    files into one shareable thing. Free: nothing is uploaded and nothing is paid.

    A manifest lists files, each with an optional relative path, and says where
    to fetch each from the Autonomi network. The ``link`` (``ant://manifest/...``)
    is what you share: anyone with it can fetch the files. The ``.ant`` bytes
    are the same manifest as a file, for when the link does not fit.

    Upload the files first, then pass what the upload returned. Use
    ``store_data`` or ``upload_file`` (public) to get an ``address``, or the
    same tools with private storage to get a ``data_map``. This tool only
    records them.

    Args:
        entries: The files, in any order. Each is an object with:
            ``data_map`` (hex DataMap from a private upload, embedded in the
            manifest, so the manifest is then the key to the file) OR
            ``address`` (hex address of a public upload): give exactly one;
            ``path`` (optional relative path such as ``notes/one.txt``; without
            one the entry is named by its content address);
            ``size`` (optional plaintext size in bytes to record; omit it
            rather than passing 0 unless the file is empty);
            ``sha256`` (optional hex SHA-256 of the file's plaintext to
            record; requires antd 0.17.0 or later. Passed to the daemon
            as given, which rejects a malformed one with ``BAD_REQUEST``
            naming ``entries[i]``).
        name: Optional suggested root directory name.
        torrent_info_hashes: Optional BitTorrent info-hashes (hex) to record.
        embed_roots: Default true: embed each file's root DataMap so readers
            learn its exact size and need not fetch it. Set false to keep the
            manifest smaller.

    Returns:
        JSON with ``manifest_base64`` (the ``.ant`` bytes, base64), ``link``
        (the ``ant://manifest/`` link, or null when the manifest does not fit
        the recommended 1,500 bytes; share the file instead) and ``entries``
        (``effective_name``, ``path``, ``size``, ``kind`` "embedded" or
        "public", ``content_address``, ``data_map``, ``exact_size``,
        ``error``, ``sha256`` as hex or null), or error details. A bad entry
        returns ``BAD_REQUEST`` with a message naming ``entries[i]``; fix it
        and call again.
    """
    client, network = _server()._get_ctx(ctx)
    try:
        if isinstance(entries, (str, dict)) or not isinstance(entries, (list, tuple)):
            raise BadRequestError("entries must be a list of objects")
        inputs = [_entry_input(i, e) for i, e in enumerate(entries)]
        if torrent_info_hashes is not None and (
            isinstance(torrent_info_hashes, str)
            or not all(isinstance(h, str) for h in torrent_info_hashes)
        ):
            raise BadRequestError("torrent_info_hashes must be a list of hex strings")
        built = await client.build_manifest(
            inputs,
            name=name or None,
            torrent_info_hashes=torrent_info_hashes or None,
            embed_roots=embed_roots,
        )
        return _server()._ok(
            {
                "manifest_base64": base64.b64encode(built.manifest).decode("ascii"),
                "link": built.link,
                "entries": [_entry_dict(e) for e in built.entries],
            },
            network,
        )
    except AntdError as exc:
        return _server()._err_antd(exc, network)
    except Exception as exc:
        return _server()._err(exc, network)


async def decode_manifest(
    ctx: Context,
    manifest_base64: str | None = None,
    link: str | None = None,
    resolve: bool = False,
) -> str:
    """Read a manifest: list the files it holds. Free: nothing is uploaded or paid.

    A manifest (a ``.ant`` file or an ``ant://manifest/`` link) bundles files
    on the Autonomi network, each with an optional relative path. Give exactly
    one of ``manifest_base64`` (the ``.ant`` bytes, as ``build_manifest``
    returns them) or ``link``. A link may be an ``ant://manifest/`` link, an
    ``ant://file/`` link, or a bare public address (these last two read as
    one entry with no path). To fetch an entry afterwards use
    ``retrieve_data`` or ``download_file`` with its ``content_address``
    (public) or ``data_map`` (embedded).

    Args:
        manifest_base64: The ``.ant`` bytes, base64-encoded.
        link: An ``ant://manifest/`` link, ``ant://file/`` link or bare address.
        resolve: Default false: read the manifest alone. If true, also fetch
            each entry's root from the network to fill in ``exact_size`` where
            the manifest does not already carry it. Needs the network and can
            time out; retrying is safe. One entry that fails to resolve is
            reported in that entry's ``error``, not as a failed call.

    Returns:
        JSON with ``source`` ("manifest" or "file_link"), ``name`` (suggested
        root directory name, or null), ``torrent_info_hash_v1``,
        ``torrent_info_hash_v2`` (hex or null) and ``entries``
        (``effective_name``, ``path``, ``size`` as recorded by the creator,
        ``kind`` "embedded" or "public", ``content_address``, ``data_map``
        for embedded entries, ``exact_size``, ``error``, ``sha256`` (the
        file's plaintext SHA-256 as hex, when the creator recorded one;
        requires antd 0.17.0 or later); unset values are null, never 0),
        or error details. Invalid input returns
        ``BAD_REQUEST``.
    """
    client, network = _server()._get_ctx(ctx)
    try:
        if (manifest_base64 is None) == (link is None):
            return _bad_request("give exactly one of manifest_base64 or link", network)
        if link is not None:
            decoded = await client.decode_manifest_link(link, resolve=resolve)
        else:
            try:
                raw = base64.b64decode(manifest_base64, validate=True)
            except (binascii.Error, ValueError, TypeError):
                return _bad_request("manifest_base64 is not valid base64", network)
            decoded = await client.decode_manifest(raw, resolve=resolve)
        return _server()._ok(
            {
                "source": decoded.source,
                "name": decoded.name,
                "torrent_info_hash_v1": decoded.torrent_info_hash_v1,
                "torrent_info_hash_v2": decoded.torrent_info_hash_v2,
                "entries": [_entry_dict(e) for e in decoded.entries],
            },
            network,
        )
    except AntdError as exc:
        return _server()._err_antd(exc, network)
    except Exception as exc:
        return _server()._err(exc, network)


def register(mcp: MCPServer) -> None:
    """Register the manifest tools, if the installed antd SDK has the API."""
    if not MANIFESTS_AVAILABLE:
        return
    mcp.tool(annotations=_BUILD_ANNOTATIONS)(build_manifest)
    mcp.tool(annotations=_DECODE_ANNOTATIONS)(decode_manifest)
