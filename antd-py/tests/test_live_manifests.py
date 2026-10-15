"""Live manifest build and decode against a running antd with a devnet behind it.

Makes no paid call: it only builds and decodes manifests of data that is
already uploaded. Skipped unless ``ANTD_TEST_URL`` and
``ANTD_TEST_MANIFEST_ADDRESSES`` are set; the gRPC test also needs
``ANTD_TEST_GRPC``.

- ``ANTD_TEST_URL``: the daemon's REST base URL, e.g. ``http://127.0.0.1:8082``
- ``ANTD_TEST_GRPC``: its gRPC target, e.g. ``127.0.0.1:50051``
- ``ANTD_TEST_MANIFEST_ADDRESSES``: two comma-separated public data addresses
- ``ANTD_TEST_MANIFEST_SIZES``: their exact plaintext sizes, comma-separated
- ``ANTD_TEST_MANIFEST_DATA_MAP``: a private upload's hex DataMap
- ``ANTD_TEST_MANIFEST_DATA_MAP_SIZE``: its exact plaintext size
- ``ANTD_TEST_MANIFEST_LINK``: an ``ant://manifest/`` link built from the
  three (optional; that check is skipped without it)

Run this file on its own: ``tests/test_integration.py`` also reads
``ANTD_TEST_URL`` and expects a daemon without a wallet.

    ANTD_TEST_URL=... ANTD_TEST_GRPC=... ANTD_TEST_MANIFEST_ADDRESSES=... \\
    python -m pytest -v tests/test_live_manifests.py
"""

from __future__ import annotations

import os

import pytest

from antd import BadRequestError, ManifestEntryInput
from antd._grpc import AsyncGrpcClient, GrpcClient
from antd._rest import AsyncRestClient, RestClient

URL = os.environ.get("ANTD_TEST_URL")
GRPC = os.environ.get("ANTD_TEST_GRPC")
ADDRESSES = [a.strip() for a in os.environ.get("ANTD_TEST_MANIFEST_ADDRESSES", "").split(",") if a.strip()]
SIZES = [int(s) for s in os.environ.get("ANTD_TEST_MANIFEST_SIZES", "").split(",") if s.strip()]
DATA_MAP = os.environ.get("ANTD_TEST_MANIFEST_DATA_MAP", "")
DATA_MAP_SIZE = os.environ.get("ANTD_TEST_MANIFEST_DATA_MAP_SIZE", "")
LINK = os.environ.get("ANTD_TEST_MANIFEST_LINK", "")

pytestmark = pytest.mark.skipif(
    not (URL and len(ADDRESSES) == 2),
    reason="set ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES (two addresses) to run",
)

NAME = "antd-py-live"
PATHS = ["live/one.txt", "live/two.txt", "live/private.txt"]


def _entries() -> list[ManifestEntryInput]:
    assert DATA_MAP, "set ANTD_TEST_MANIFEST_DATA_MAP"
    return [
        ManifestEntryInput(address=ADDRESSES[0], path=PATHS[0]),
        ManifestEntryInput(address=ADDRESSES[1], path=PATHS[1]),
        ManifestEntryInput(data_map=DATA_MAP, path=PATHS[2]),
    ]


def _expected_sizes() -> dict[str, int]:
    assert len(SIZES) == 2 and DATA_MAP_SIZE, "set ANTD_TEST_MANIFEST_SIZES and ANTD_TEST_MANIFEST_DATA_MAP_SIZE"
    return {PATHS[0]: SIZES[0], PATHS[1]: SIZES[1], PATHS[2]: int(DATA_MAP_SIZE)}


def _check_built(built) -> None:
    # Entries come back in encoded order: sorted by effective name.
    assert [e.effective_name for e in built.entries] == sorted(PATHS)
    by_name = {e.effective_name: e for e in built.entries}
    assert [by_name[p].kind for p in PATHS] == ["public", "public", "embedded"]
    assert [by_name[p].content_address for p in PATHS[:2]] == ADDRESSES
    assert all(by_name[p].path == p for p in PATHS)
    # No size was given, so none is recorded.
    assert all(e.size is None for e in built.entries)
    assert built.manifest[:5] == bytes([0xC1, ord("A"), ord("N"), ord("T"), 0x01])
    assert built.link and built.link.startswith("ant://manifest/")


def _check_resolved(decoded) -> None:
    assert (decoded.source, decoded.name) == ("manifest", NAME)
    by_name = {e.effective_name: e for e in decoded.entries}
    assert {n: e.exact_size for n, e in by_name.items()} == _expected_sizes()
    assert all(e.error is None for e in decoded.entries)
    embedded = by_name[PATHS[2]]
    assert embedded.kind == "embedded" and embedded.data_map
    assert all(by_name[p].data_map is None for p in PATHS[:2])


def _check_fixture_link(decoded) -> None:
    assert decoded.source == "manifest"
    kinds = sorted(e.kind for e in decoded.entries)
    assert kinds == ["embedded", "public", "public"]
    public = {e.content_address: e.exact_size for e in decoded.entries if e.kind == "public"}
    assert public == dict(zip(ADDRESSES, SIZES))


def test_live_manifests_rest():
    assert URL is not None
    client = RestClient(base_url=URL, timeout=600.0)
    try:
        built = client.build_manifest(_entries(), name=NAME)
        _check_built(built)
        _check_resolved(client.decode_manifest(built.manifest, resolve=True))
        _check_resolved(client.decode_manifest_link(built.link, resolve=True))

        # Unresolved, a public entry knows no exact size: None, never 0.
        plain = client.decode_manifest(built.manifest)
        assert {e.effective_name: e.exact_size for e in plain.entries if e.kind == "public"} == {
            PATHS[0]: None, PATHS[1]: None}

        if LINK:
            _check_fixture_link(client.decode_manifest_link(LINK, resolve=True))

        # A bare address decodes as a one-entry file link.
        bare = client.decode_manifest_link(ADDRESSES[0], resolve=True)
        assert bare.source == "file_link" and [e.exact_size for e in bare.entries] == [SIZES[0]]

        # Refused before sending, and by the daemon.
        with pytest.raises(BadRequestError) as info:
            client.build_manifest([ManifestEntryInput(data_map=DATA_MAP, address=ADDRESSES[0])])
        assert info.value.status_code == 0 and "entries[0]" in str(info.value)
        with pytest.raises(BadRequestError) as info:
            client.build_manifest([ManifestEntryInput(address=ADDRESSES[0], path="../x")])
        assert info.value.status_code == 400 and "entries[0]" in str(info.value)
        with pytest.raises(BadRequestError):
            client.decode_manifest(b"not a manifest")
    finally:
        client.close()


@pytest.mark.asyncio
async def test_live_manifests_async_rest():
    assert URL is not None
    client = AsyncRestClient(base_url=URL, timeout=600.0)
    try:
        built = await client.build_manifest(_entries(), name=NAME)
        _check_built(built)
        _check_resolved(await client.decode_manifest_link(built.link, resolve=True))
        with pytest.raises(BadRequestError, match=r"entries\[0\]"):
            await client.build_manifest([ManifestEntryInput(address=ADDRESSES[0], path="../x")])
    finally:
        await client.close()


@pytest.mark.skipif(not GRPC, reason="set ANTD_TEST_GRPC to run over gRPC")
def test_live_manifests_grpc():
    assert GRPC is not None
    client = GrpcClient(target=GRPC)
    rest = RestClient(base_url=URL, timeout=600.0)
    try:
        built = client.build_manifest(_entries(), name=NAME)
        _check_built(built)
        # The two transports agree byte for byte.
        assert built.manifest == rest.build_manifest(_entries(), name=NAME).manifest
        _check_resolved(client.decode_manifest(built.manifest, resolve=True))
        _check_resolved(client.decode_manifest_link(built.link, resolve=True))
        if LINK:
            _check_fixture_link(client.decode_manifest_link(LINK, resolve=True))
        with pytest.raises(BadRequestError) as info:
            client.build_manifest([ManifestEntryInput(address=ADDRESSES[0], path="../x")])
        assert "entries[0]" in str(info.value)
        with pytest.raises(BadRequestError):
            client.decode_manifest(b"not a manifest")
    finally:
        client.close()
        rest.close()


@pytest.mark.skipif(not GRPC, reason="set ANTD_TEST_GRPC to run over gRPC")
@pytest.mark.asyncio
async def test_live_manifests_async_grpc():
    assert GRPC is not None
    client = AsyncGrpcClient(target=GRPC)
    try:
        built = await client.build_manifest(_entries(), name=NAME)
        _check_built(built)
        _check_resolved(await client.decode_manifest(built.manifest, resolve=True))
        with pytest.raises(BadRequestError, match=r"entries\[0\]"):
            await client.build_manifest([ManifestEntryInput(address=ADDRESSES[0], path="../x")])
    finally:
        await client.close()
