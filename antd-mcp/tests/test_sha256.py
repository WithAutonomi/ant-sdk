"""Tests for ``sha256`` in the upload and manifest tool results (antd 0.17.0).

The tool coroutines run directly with ``_get_ctx`` monkeypatched to a mocked
client, or to a real ``AsyncRestClient`` over ``httpx.MockTransport`` where the
request JSON matters. The last class is a live run, gated on env vars, with no
paid calls.
"""

from __future__ import annotations

import asyncio
import base64
import dataclasses
import functools
import hashlib
import json
import os
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest

from antd import (
    BuiltManifest,
    DataPutPublicResult,
    DataPutResult,
    DecodedManifest,
    FilePutPublicResult,
    FilePutResult,
    FinalizeUploadResult,
    ManifestEntryInfo,
)
from antd._rest import AsyncRestClient
from antd_mcp import manifests, server

SHA = hashlib.sha256(b"hello").hexdigest()
ADDR = "a1" * 32
MANIFEST_BYTES = b"\x00\x01ant-manifest\xff\xfe"
B64 = base64.b64encode(MANIFEST_BYTES).decode()


def _fn(tool):
    return functools.partial(tool, ctx=None)


@pytest.fixture
def mock_client(monkeypatch):
    client = AsyncMock()
    monkeypatch.setattr(server, "_get_ctx", lambda ctx: (client, "test-net"))
    return client


# case name: (tool, client method, tool kwargs, result factory taking sha256=...)
_UPLOAD_CASES = {
    "store_data_private": (
        server.store_data, "data_put", {"text": "hi", "private": True},
        lambda **kw: DataPutResult(data_map="dd", chunks_stored=3, payment_mode_used="single", **kw),
    ),
    "store_data_public": (
        server.store_data, "data_put_public", {"text": "hi"},
        lambda **kw: DataPutPublicResult(address=ADDR, chunks_stored=3, payment_mode_used="single", **kw),
    ),
    "upload_file_private": (
        server.upload_file, "file_put", {"path": "/x", "private": True},
        lambda **kw: FilePutResult("dd", "10", "20", 3, "single", **kw),
    ),
    "upload_file_public": (
        server.upload_file, "file_put_public", {"path": "/x"},
        lambda **kw: FilePutPublicResult(ADDR, "10", "20", 3, "single", **kw),
    ),
    "finalize_upload": (
        server.finalize_upload, "finalize_upload", {"upload_id": "u", "tx_hashes": {"q": "t"}},
        lambda **kw: FinalizeUploadResult(address=ADDR, chunks_stored=3, data_map="dd", **kw),
    ),
    "finalize_merkle_upload": (
        server.finalize_merkle_upload, "finalize_merkle_upload",
        {"upload_id": "u", "winner_pool_hash": "0xab"},
        lambda **kw: FinalizeUploadResult(address=ADDR, chunks_stored=3, data_map="dd", **kw),
    ),
}


class TestUploadResults:
    @pytest.mark.parametrize("case", sorted(_UPLOAD_CASES))
    async def test_sha256_present(self, mock_client, case):
        tool, method, kwargs, make = _UPLOAD_CASES[case]
        getattr(mock_client, method).return_value = make(sha256=SHA)
        out = json.loads(await _fn(tool)(**kwargs))
        assert out["sha256"] == SHA
        assert out["network"] == "test-net"
        assert out["chunks_stored"] == 3  # siblings untouched

    @pytest.mark.parametrize("case", sorted(_UPLOAD_CASES))
    @pytest.mark.parametrize("value", [None, ""], ids=["none", "empty"])
    async def test_sha256_none_and_empty_read_as_null(self, mock_client, case, value):
        tool, method, kwargs, make = _UPLOAD_CASES[case]
        getattr(mock_client, method).return_value = make(sha256=value)
        out = json.loads(await _fn(tool)(**kwargs))
        assert "sha256" in out and out["sha256"] is None

    @pytest.mark.parametrize("case", sorted(_UPLOAD_CASES))
    async def test_sdk_without_the_attribute_reads_as_null(self, mock_client, case):
        """antd-py 0.3.0 results have no ``sha256`` attribute at all."""
        tool, method, kwargs, make = _UPLOAD_CASES[case]
        full = make()
        names = [f.name for f in dataclasses.fields(full) if f.name != "sha256"]
        getattr(mock_client, method).return_value = SimpleNamespace(
            **{n: getattr(full, n) for n in names}
        )
        out = json.loads(await _fn(tool)(**kwargs))
        assert out["sha256"] is None
        assert out["chunks_stored"] == 3

    async def test_through_the_real_rest_client(self, monkeypatch):
        """REST bodies from an antd 0.17.0 and a pre-0.17.0 daemon."""
        bodies = iter(
            [
                {"address": ADDR, "chunks_stored": 1, "payment_mode_used": "single", "sha256": SHA},
                {"address": ADDR, "chunks_stored": 1, "payment_mode_used": "single"},
            ]
        )
        client = AsyncRestClient(base_url="http://test")
        client._http = httpx.AsyncClient(
            base_url="http://test",
            transport=httpx.MockTransport(lambda request: httpx.Response(200, json=next(bodies))),
        )
        monkeypatch.setattr(server, "_get_ctx", lambda ctx: (client, "test-net"))
        new = json.loads(await _fn(server.store_data)(text="hello"))
        old = json.loads(await _fn(server.store_data)(text="hello"))
        assert new["sha256"] == SHA
        assert old["sha256"] is None


def _info(**kw) -> ManifestEntryInfo:
    base = dict(effective_name="a.txt", path="a.txt", kind="public", content_address=ADDR)
    base.update(kw)
    return ManifestEntryInfo(**base)


@pytest.fixture
def manifest_client(monkeypatch):
    client = AsyncMock()
    monkeypatch.setattr(manifests._server(), "_get_ctx", lambda ctx: (client, "test-net"))
    return client


async def _build(**kwargs) -> dict:
    return json.loads(await _fn(manifests.build_manifest)(**kwargs))


async def _decode(**kwargs) -> dict:
    return json.loads(await _fn(manifests.decode_manifest)(**kwargs))


class TestManifestOutputs:
    async def test_build_entries_carry_sha256_or_null(self, manifest_client):
        manifest_client.build_manifest.return_value = BuiltManifest(
            manifest=b"x", entries=[_info(sha256=SHA), _info(sha256=None), _info(sha256="")]
        )
        out = await _build(entries=[{"address": ADDR}])
        assert [e["sha256"] for e in out["entries"]] == [SHA, None, None]

    async def test_decode_entries_carry_sha256_or_null(self, manifest_client):
        manifest_client.decode_manifest_link.return_value = DecodedManifest(
            source="manifest", entries=[_info(sha256=SHA), _info(sha256=None), _info(sha256="")]
        )
        out = await _decode(link="ant://manifest/abc")
        assert [e["sha256"] for e in out["entries"]] == [SHA, None, None]

    def test_entry_without_the_attribute_reads_as_null(self):
        legacy = SimpleNamespace(
            effective_name="a", path=None, size=None, kind="public", content_address=ADDR,
            data_map=None, exact_size=None, error=None,
        )
        assert manifests._entry_dict(legacy)["sha256"] is None


class TestManifestInput:
    async def test_sha256_forwarded_to_the_sdk_as_given(self, manifest_client):
        manifest_client.build_manifest.return_value = BuiltManifest(manifest=b"x")
        upper = SHA.upper()
        await _build(
            entries=[
                {"address": ADDR, "path": "a.txt", "sha256": upper},
                {"address": ADDR, "path": "b.txt"},
                {"address": ADDR, "path": "c.txt", "sha256": ""},
            ]
        )
        a, b, c = manifest_client.build_manifest.call_args.args[0]
        assert a.sha256 == upper  # no lowercasing, no hex check
        assert b.sha256 is None
        assert c.sha256 == ""  # the SDK omits it on the wire

    @pytest.fixture
    def rest(self, monkeypatch):
        seen = []

        def handler(request: httpx.Request) -> httpx.Response:
            body = json.loads(request.content)
            seen.append(body)
            for e in body["entries"]:
                if e.get("sha256") == "zz":
                    return httpx.Response(
                        400,
                        json={"error": "entries[0]: invalid hex sha256: Odd number of digits", "code": "BAD_REQUEST"},
                    )
            return httpx.Response(200, json={
                "manifest": B64, "link": "ant://manifest/abc",
                "entries": [
                    {"effective_name": e.get("path", ""), "kind": "public", "content_address": ADDR,
                     **({"sha256": e["sha256"].lower()} if e.get("sha256") else {})}
                    for e in body["entries"]
                ],
            })

        client = AsyncRestClient(base_url="http://test")
        client._http = httpx.AsyncClient(base_url="http://test", transport=httpx.MockTransport(handler))
        monkeypatch.setattr(manifests._server(), "_get_ctx", lambda ctx: (client, "test-net"))
        return seen

    async def test_request_json_has_sha256_only_when_set(self, rest):
        out = await _build(
            entries=[
                {"address": ADDR, "path": "a.txt", "sha256": SHA},
                {"address": ADDR, "path": "b.txt"},
                {"address": ADDR, "path": "c.txt", "sha256": ""},
            ]
        )
        entries = rest[0]["entries"]
        assert entries[0] == {"address": ADDR, "path": "a.txt", "sha256": SHA}
        assert entries[1] == {"address": ADDR, "path": "b.txt"}
        assert entries[2] == {"address": ADDR, "path": "c.txt"}
        assert [e["sha256"] for e in out["entries"]] == [SHA, None, None]

    async def test_bad_sha256_is_the_daemons_400(self, rest):
        out = await _build(entries=[{"address": ADDR, "sha256": "zz"}])
        assert out["error"] == "BAD_REQUEST"
        assert out["status_code"] == 400
        assert out["message"] == "entries[0]: invalid hex sha256: Odd number of digits"

    async def test_non_string_sha256_refused_like_its_siblings(self, manifest_client):
        out = await _build(entries=[{"address": ADDR, "sha256": 5}])
        assert out["error"] == "BAD_REQUEST"
        assert out["message"] == "entries[0]: sha256 must be a string"
        manifest_client.build_manifest.assert_not_called()

    async def test_sdk_without_the_field_gives_bad_request_not_a_crash(self, manifest_client, monkeypatch):
        @dataclasses.dataclass(frozen=True, kw_only=True)
        class OldInput:
            data_map: str | None = None
            address: str | None = None
            path: str | None = None
            size: int | None = None

        monkeypatch.setattr(manifests, "ManifestEntryInput", OldInput)
        out = await _build(entries=[{"address": ADDR, "sha256": SHA}])
        assert out["error"] == "BAD_REQUEST"
        assert "entries[0]: sha256" in out["message"]
        assert "antd 0.17.0 or later" in out["message"]
        manifest_client.build_manifest.assert_not_called()
        # Entries without sha256 still work on such an SDK.
        manifest_client.build_manifest.return_value = BuiltManifest(manifest=b"x")
        assert "error" not in await _build(entries=[{"address": ADDR}])


class TestDescriptions:
    def test_tools_name_the_daemon_version(self):
        tools = {t.name: t for t in asyncio.run(server.mcp.list_tools())}
        for name in (
            "store_data", "upload_file", "finalize_upload", "finalize_merkle_upload",
            "build_manifest", "decode_manifest",
        ):
            text = " ".join(tools[name].description.split())
            assert "sha256" in text, name
            assert "antd 0.17.0 or later" in text, name


_LIVE_URL = os.environ.get("ANTD_TEST_URL")
_LIVE_LINK = os.environ.get("ANTD_TEST_SHA_LINK")


@pytest.mark.skipif(not (_LIVE_URL and _LIVE_LINK), reason="needs ANTD_TEST_URL and ANTD_TEST_SHA_LINK")
class TestLive:
    """No paid calls: decodes and builds manifests against fixtures."""

    @pytest.fixture
    async def live(self, monkeypatch):
        client = AsyncRestClient(base_url=_LIVE_URL)
        monkeypatch.setattr(manifests._server(), "_get_ctx", lambda ctx: (client, "live"))
        yield client
        await client.close()

    async def test_decode_entries(self, live):
        out = await _decode(link=_LIVE_LINK, resolve=False)
        assert "error" not in out, out
        by_path = {e["path"]: e["sha256"] for e in out["entries"]}
        assert by_path["public.txt"] == os.environ["ANTD_TEST_SHA_PUBLIC_SHA256"]
        assert by_path["private.txt"] == os.environ["ANTD_TEST_SHA_DATA_MAP_SHA256"]
        assert by_path["nohash.txt"] is None

    async def test_build_with_sha256(self, live):
        out = await _build(
            entries=[
                {
                    "address": os.environ["ANTD_TEST_SHA_PUBLIC_ADDRESS"],
                    "path": "a.txt",
                    "sha256": os.environ["ANTD_TEST_SHA_PUBLIC_SHA256"],
                }
            ]
        )
        assert "error" not in out, out
        assert out["entries"][0]["sha256"] == os.environ["ANTD_TEST_SHA_PUBLIC_SHA256"]

    async def test_build_with_bad_sha256(self, live):
        out = await _build(
            entries=[{"address": os.environ["ANTD_TEST_SHA_PUBLIC_ADDRESS"], "path": "a.txt", "sha256": "zz"}]
        )
        assert out["error"] == "BAD_REQUEST"
        assert "entries[0]" in out["message"]
