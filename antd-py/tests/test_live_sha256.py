"""Live ``sha256`` checks against a running antd 0.17.0 or later with a devnet
behind it. Skipped unless ``ANTD_TEST_URL`` and ``ANTD_TEST_SHA_LINK`` are
set; the gRPC tests also need ``ANTD_TEST_GRPC``.

One paid call per transport: a public data upload of a few bytes.

- ``ANTD_TEST_URL``: the daemon's REST base URL
- ``ANTD_TEST_GRPC``: its gRPC target
- ``ANTD_TEST_SHA_LINK``: an ``ant://manifest/`` link with entries
  ``public.txt`` and ``private.txt`` (both with a sha256) and ``nohash.txt``
  (none)
- ``ANTD_TEST_SHA_PUBLIC_ADDRESS`` / ``ANTD_TEST_SHA_PUBLIC_SHA256``: a public
  upload and its plaintext's SHA-256
- ``ANTD_TEST_SHA_DATA_MAP_SHA256``: the SHA-256 recorded for ``private.txt``

Run this file on its own: ``tests/test_integration.py`` also reads
``ANTD_TEST_URL`` and expects a daemon without a wallet.

    ANTD_TEST_URL=... ANTD_TEST_GRPC=... ANTD_TEST_SHA_LINK=... \\
    python -m pytest -v tests/test_live_sha256.py
"""

from __future__ import annotations

import hashlib
import os
import time

import pytest

from antd import BadRequestError, ManifestEntryInput
from antd._grpc import AsyncGrpcClient, GrpcClient
from antd._rest import AsyncRestClient, RestClient

URL = os.environ.get("ANTD_TEST_URL")
GRPC = os.environ.get("ANTD_TEST_GRPC")
LINK = os.environ.get("ANTD_TEST_SHA_LINK", "")
PUBLIC_ADDRESS = os.environ.get("ANTD_TEST_SHA_PUBLIC_ADDRESS", "")
PUBLIC_SHA256 = os.environ.get("ANTD_TEST_SHA_PUBLIC_SHA256", "")
DATA_MAP_SHA256 = os.environ.get("ANTD_TEST_SHA_DATA_MAP_SHA256", "")

pytestmark = pytest.mark.skipif(
    not (URL and LINK),
    reason="set ANTD_TEST_URL and ANTD_TEST_SHA_LINK to run",
)

needs_grpc = pytest.mark.skipif(not GRPC, reason="set ANTD_TEST_GRPC to run over gRPC")


def _payload(transport: str) -> bytes:
    return f"sha-fanout py {transport} {int(time.time())}".encode()


def _check_link(decoded) -> None:
    by_name = {e.effective_name: e for e in decoded.entries}
    assert by_name["public.txt"].sha256 == PUBLIC_SHA256
    assert by_name["private.txt"].sha256 == DATA_MAP_SHA256
    assert by_name["nohash.txt"].sha256 is None


def _check_built(built) -> None:
    assert [(e.path, e.sha256) for e in built.entries] == [("a.txt", PUBLIC_SHA256)]


def _entry() -> list[ManifestEntryInput]:
    return [ManifestEntryInput(address=PUBLIC_ADDRESS, path="a.txt", sha256=PUBLIC_SHA256)]


def _bad() -> list[ManifestEntryInput]:
    return [ManifestEntryInput(address=PUBLIC_ADDRESS, path="a.txt", sha256="zz")]


def test_live_sha256_rest():
    assert URL is not None
    client = RestClient(base_url=URL, timeout=600.0)
    try:
        _check_link(client.decode_manifest_link(LINK, resolve=False))
        _check_built(client.build_manifest(_entry()))
        with pytest.raises(BadRequestError, match="sha256") as info:
            client.build_manifest(_bad())
        assert info.value.status_code == 400

        payload = _payload("rest")
        res = client.data_put_public(payload)
        assert res.sha256 == hashlib.sha256(payload).hexdigest()
    finally:
        client.close()


@pytest.mark.asyncio
async def test_live_sha256_async_rest():
    assert URL is not None
    client = AsyncRestClient(base_url=URL, timeout=600.0)
    try:
        _check_link(await client.decode_manifest_link(LINK, resolve=False))
        _check_built(await client.build_manifest(_entry()))
        with pytest.raises(BadRequestError, match="sha256"):
            await client.build_manifest(_bad())
    finally:
        await client.close()


@needs_grpc
def test_live_sha256_grpc():
    assert GRPC is not None
    client = GrpcClient(target=GRPC)
    try:
        _check_link(client.decode_manifest_link(LINK, resolve=False))
        _check_built(client.build_manifest(_entry()))
        with pytest.raises(BadRequestError, match="sha256"):
            client.build_manifest(_bad())

        payload = _payload("grpc")
        res = client.data_put_public(payload)
        assert res.sha256 == hashlib.sha256(payload).hexdigest()
    finally:
        client.close()


@needs_grpc
@pytest.mark.asyncio
async def test_live_sha256_async_grpc():
    assert GRPC is not None
    client = AsyncGrpcClient(target=GRPC)
    try:
        _check_link(await client.decode_manifest_link(LINK, resolve=False))
        _check_built(await client.build_manifest(_entry()))
        with pytest.raises(BadRequestError, match="sha256"):
            await client.build_manifest(_bad())
    finally:
        await client.close()
