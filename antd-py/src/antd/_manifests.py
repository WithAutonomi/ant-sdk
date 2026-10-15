"""Manifest request/response mapping shared by the REST and gRPC clients
(ADR-0006 ``.ant`` files and ``ant://`` links, V2-1580).

The daemon builds and decodes manifests through ant-core, so nothing here
knows the format: it only converts between the models and the two wire
forms. Over REST the ``.ant`` bytes travel as base64 in JSON (``manifest`` in
the build response and the decode request); over gRPC they are raw
``bytes``. Callers only ever see raw bytes.

The REST helpers build and read the daemon's JSON; the ``*_from_pb``
converters read the ManifestService messages by attribute, so this module
never imports grpc or the generated stubs and the REST-only install keeps
working.

Unset values read as ``None`` on both transports. REST omits the field. gRPC
leaves a proto3 ``optional`` unset, so sizes are read by presence
(``HasField``), never by value: 0 is the size of an empty file. Unset strings
arrive from gRPC as ``""`` and read as ``None`` too.
"""

from __future__ import annotations

import base64
import binascii
from collections.abc import Sequence

from .exceptions import BadRequestError, InternalError
from .models import BuiltManifest, DecodedManifest, ManifestEntryInfo, ManifestEntryInput

_U64_MAX = 2**64 - 1


# --- Checks made before sending -------------------------------------------
#
# These raise BadRequestError, the error the daemon's 400 / INVALID_ARGUMENT
# maps to, so one ``except`` covers an entry refused here and one refused by
# the daemon. Nothing was sent, so ``status_code`` is 0.


def check_entries(entries: Sequence[ManifestEntryInput]) -> None:
    """Refuse an entry with both or neither of ``data_map`` and ``address``
    (as antd-go's ``checkManifestEntries`` does), or a ``size`` that is not a
    u64. An empty string counts as unset, as it does for the daemon. The
    messages name ``entries[i]`` in the daemon's own words."""
    for i, e in enumerate(entries):
        has_data_map, has_address = bool(e.data_map), bool(e.address)
        if has_data_map and has_address:
            raise BadRequestError(f"entries[{i}]: give data_map or address, not both")
        if not has_data_map and not has_address:
            raise BadRequestError(f"entries[{i}]: needs a data_map or an address")
        if e.size is not None and not _is_u64(e.size):
            raise BadRequestError(f"entries[{i}]: size must be an int from 0 to 2**64 - 1, got {e.size!r}")


def check_torrent_info_hashes(hashes: Sequence[str] | None) -> list[str]:
    """The hashes as a list (empty when none). A bare string would otherwise
    be split into characters."""
    if hashes is None:
        return []
    if isinstance(hashes, str):
        raise TypeError("torrent_info_hashes takes a sequence of hex hashes, not a string")
    return list(hashes)


def manifest_bytes(manifest: bytes | bytearray | memoryview) -> bytes:
    """The ``.ant`` bytes to decode, refusing an empty input before sending."""
    if isinstance(manifest, str):
        raise TypeError(
            "decode_manifest takes the .ant bytes; use decode_manifest_link for a link or address"
        )
    data = bytes(manifest)
    if not data:
        raise BadRequestError("manifest is empty")
    return data


def check_link(link: str) -> str:
    """The link to decode, refusing an empty one before sending."""
    if not isinstance(link, str):
        raise TypeError(
            "decode_manifest_link takes an ant:// link or address; use decode_manifest for .ant bytes"
        )
    if not link:
        raise BadRequestError("link is empty")
    return link


def _is_u64(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= _U64_MAX


# --- Request bodies (REST) -----------------------------------------------


def build_body(
    entries: Sequence[ManifestEntryInput],
    name: str | None,
    torrent_info_hashes: list[str],
    embed_roots: bool,
) -> dict:
    """The ``POST /v1/manifests/build`` body. Unset fields are omitted;
    ``embed_roots`` is always sent (the daemon's default is true too)."""
    wire = []
    for e in entries:
        m: dict = {}
        if e.path:
            m["path"] = e.path
        if e.size is not None:
            m["size"] = e.size
        if e.data_map:
            m["data_map"] = e.data_map
        else:
            m["address"] = e.address
        wire.append(m)
    body: dict = {"entries": wire, "embed_roots": bool(embed_roots)}
    if name:
        body["name"] = name
    if torrent_info_hashes:
        body["torrent_info_hashes"] = torrent_info_hashes
    return body


def decode_bytes_body(manifest: bytes, resolve: bool) -> dict:
    """The ``POST /v1/manifests/decode`` body for ``.ant`` bytes (base64)."""
    return {"manifest": base64.b64encode(manifest).decode("ascii"), "resolve": bool(resolve)}


def decode_link_body(link: str, resolve: bool) -> dict:
    """The ``POST /v1/manifests/decode`` body for a link or bare address."""
    return {"link": link, "resolve": bool(resolve)}


# --- REST responses --------------------------------------------------------


def _str(j: dict, key: str) -> str:
    value = j.get(key)
    return value if isinstance(value, str) else ""


def _opt_str(value: object) -> str | None:
    """Absent, ``null`` and ``""`` all read as ``None``."""
    return value if isinstance(value, str) and value else None


def _opt_u64(value: object) -> int | None:
    """A JSON integer in ``0..=u64::MAX``; absent (or anything else) reads as
    ``None``, never 0."""
    return value if _is_u64(value) else None


def _dicts(value: object) -> list[dict]:
    return [v for v in value if isinstance(v, dict)] if isinstance(value, list) else []


def _unb64(value: object) -> bytes:
    """Strict base64: a malformed ``manifest`` raises rather than decoding to
    the wrong bytes."""
    if value is None:
        value = ""
    if not isinstance(value, str):
        raise InternalError(f"build_manifest: manifest is not a base64 string: {value!r:.80}")
    try:
        return base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as e:
        raise InternalError(f"build_manifest: manifest is not valid base64: {e}") from e


def entry_from_json(j: dict) -> ManifestEntryInfo:
    return ManifestEntryInfo(
        effective_name=_str(j, "effective_name"),
        path=_opt_str(j.get("path")),
        size=_opt_u64(j.get("size")),
        kind=_str(j, "kind"),
        content_address=_str(j, "content_address"),
        data_map=_opt_str(j.get("data_map")),
        exact_size=_opt_u64(j.get("exact_size")),
        error=_opt_str(j.get("error")),
    )


def _object(j: object) -> dict:
    """A JSON object; anything else reads as an empty one."""
    return j if isinstance(j, dict) else {}


def built_from_json(j: object) -> BuiltManifest:
    j = _object(j)
    return BuiltManifest(
        manifest=_unb64(j.get("manifest")),
        link=_opt_str(j.get("link")),
        entries=[entry_from_json(e) for e in _dicts(j.get("entries"))],
    )


def decoded_from_json(j: object) -> DecodedManifest:
    j = _object(j)
    return DecodedManifest(
        source=_str(j, "source"),
        name=_opt_str(j.get("name")),
        torrent_info_hash_v1=_opt_str(j.get("torrent_info_hash_v1")),
        torrent_info_hash_v2=_opt_str(j.get("torrent_info_hash_v2")),
        entries=[entry_from_json(e) for e in _dicts(j.get("entries"))],
    )


# --- gRPC responses (read by attribute) ------------------------------------


def _pb_opt_u64(msg, field: str) -> int | None:
    """A proto3 ``optional uint64``: by presence, so a recorded 0 stays 0 and
    an unset field reads as ``None``."""
    return getattr(msg, field) if msg.HasField(field) else None


def entry_from_pb(e) -> ManifestEntryInfo:
    return ManifestEntryInfo(
        effective_name=e.effective_name,
        path=_opt_str(e.path) if e.HasField("path") else None,
        size=_pb_opt_u64(e, "size"),
        kind=e.kind,
        content_address=e.content_address,
        data_map=_opt_str(e.data_map),
        exact_size=_pb_opt_u64(e, "exact_size"),
        error=_opt_str(e.error),
    )


def built_from_pb(resp) -> BuiltManifest:
    return BuiltManifest(
        manifest=bytes(resp.manifest),
        link=_opt_str(resp.link),
        entries=[entry_from_pb(e) for e in resp.entries],
    )


def decoded_from_pb(resp) -> DecodedManifest:
    return DecodedManifest(
        source=resp.source,
        name=_opt_str(resp.name) if resp.HasField("name") else None,
        torrent_info_hash_v1=_opt_str(resp.torrent_info_hash_v1),
        torrent_info_hash_v2=_opt_str(resp.torrent_info_hash_v2),
        entries=[entry_from_pb(e) for e in resp.entries],
    )
