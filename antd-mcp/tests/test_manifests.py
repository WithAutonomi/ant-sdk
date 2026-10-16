"""Unit tests for the antd-mcp manifest tools.

Same approach as ``test_server.py``: the tool coroutines run directly, with
``server._get_ctx`` monkeypatched to a mocked client (or a real
``AsyncRestClient`` over ``httpx.MockTransport`` where the SDK's own wire
handling matters). The last test class is a live run, gated on env vars.
"""

from __future__ import annotations

import asyncio
import base64
import functools
import importlib
import json
import os
from unittest.mock import AsyncMock

import httpx
import pytest

from antd import BuiltManifest, DecodedManifest, ManifestEntryInfo
from antd._rest import AsyncRestClient
from antd.exceptions import BadRequestError, NetworkError
from antd_mcp import manifests, server

ADDR_1 = "a1" * 32
ADDR_2 = "a2" * 32
MANIFEST_BYTES = b"\x00\x01ant-manifest\xff\xfe"
B64 = base64.b64encode(MANIFEST_BYTES).decode()
LINK = "ant://manifest/abc"

MANIFEST_TOOLS = {"build_manifest", "decode_manifest"}


def _fn(tool):
    return functools.partial(tool, ctx=None)


@pytest.fixture
def mock_client(monkeypatch):
    client = AsyncMock()
    monkeypatch.setattr(manifests._server(), "_get_ctx", lambda ctx: (client, "test-net"))
    return client


async def _build(**kwargs) -> dict:
    return json.loads(await _fn(manifests.build_manifest)(**kwargs))


async def _decode(**kwargs) -> dict:
    return json.loads(await _fn(manifests.decode_manifest)(**kwargs))


def _info(**kw) -> ManifestEntryInfo:
    base = dict(effective_name="notes/one.txt", path="notes/one.txt", kind="public", content_address=ADDR_1)
    base.update(kw)
    return ManifestEntryInfo(**base)


class TestBuild:
    async def test_forwards_and_returns_base64(self, mock_client):
        mock_client.build_manifest.return_value = BuiltManifest(
            manifest=MANIFEST_BYTES, link=LINK, entries=[_info(size=5)]
        )
        out = await _build(
            entries=[{"path": "notes/one.txt", "address": ADDR_1, "size": 5}],
            name="demo",
            torrent_info_hashes=["ab" * 20],
        )
        assert out["manifest_base64"] == B64
        assert out["link"] == LINK
        assert out["network"] == "test-net"
        assert out["entries"][0]["effective_name"] == "notes/one.txt"
        assert out["entries"][0]["size"] == 5
        assert out["entries"][0]["exact_size"] is None
        args, kwargs = mock_client.build_manifest.call_args
        (inp,) = args[0]
        assert (inp.address, inp.data_map, inp.path, inp.size) == (ADDR_1, None, "notes/one.txt", 5)
        assert kwargs == {"name": "demo", "torrent_info_hashes": ["ab" * 20], "embed_roots": True}

    async def test_embed_roots_default_true_and_overridable(self, mock_client):
        mock_client.build_manifest.return_value = BuiltManifest(manifest=b"x")
        await _build(entries=[{"address": ADDR_1}])
        assert mock_client.build_manifest.call_args.kwargs["embed_roots"] is True
        await _build(entries=[{"address": ADDR_1}], embed_roots=False)
        assert mock_client.build_manifest.call_args.kwargs["embed_roots"] is False

    async def test_link_null_when_too_big(self, mock_client):
        mock_client.build_manifest.return_value = BuiltManifest(manifest=b"x", link=None)
        out = await _build(entries=[{"address": ADDR_1}])
        assert out["link"] is None
        assert out["manifest_base64"] == "eA=="

    async def test_unset_size_is_null_zero_stays_zero(self, mock_client):
        mock_client.build_manifest.return_value = BuiltManifest(
            manifest=b"x", entries=[_info(size=None), _info(size=0, exact_size=0)]
        )
        out = await _build(entries=[{"address": ADDR_1}, {"address": ADDR_2, "size": 0}])
        assert out["entries"][0]["size"] is None
        assert out["entries"][1]["size"] == 0
        assert out["entries"][1]["exact_size"] == 0
        inp = mock_client.build_manifest.call_args.args[0]
        assert inp[0].size is None and inp[1].size == 0

    @pytest.mark.parametrize(
        "entries, fragment",
        [
            ([{"address": ADDR_1}, {"path": "x"}], "entries[1]"),
            ([{"address": ADDR_1, "data_map": "ab"}], "entries[0]"),
            (["nope"], "entries[0]"),
            ([{"address": ADDR_1, "colour": "red"}], "unknown field"),
            ([{"address": 5}], "entries[0]: address must be a string"),
        ],
    )
    async def test_bad_entries_refused_before_sending(self, mock_client, entries, fragment):
        # The real SDK check runs here for both-or-neither: use a client that
        # applies it, as the SDK does before sending.
        from antd import _manifests

        async def build(inputs, **kw):
            _manifests.check_entries(inputs)
            return BuiltManifest(manifest=b"x")

        mock_client.build_manifest.side_effect = build
        out = await _build(entries=entries)
        assert out["error"] == "BAD_REQUEST"
        assert fragment in out["message"]

    async def test_entries_not_a_list(self, mock_client):
        out = await _build(entries={"address": ADDR_1})
        assert out["error"] == "BAD_REQUEST"
        mock_client.build_manifest.assert_not_called()

    async def test_daemon_400_keeps_message(self, mock_client):
        mock_client.build_manifest.side_effect = BadRequestError("entries[2]: path must be relative", 400)
        out = await _build(entries=[{"address": ADDR_1}])
        assert out["error"] == "BAD_REQUEST"
        assert out["message"] == "entries[2]: path must be relative"
        assert out["status_code"] == 400

    async def test_other_errors(self, mock_client):
        mock_client.build_manifest.side_effect = NetworkError("timeout", 504)
        assert (await _build(entries=[{"address": ADDR_1}]))["error"] == "NETWORK_ERROR"
        mock_client.build_manifest.side_effect = RuntimeError("boom")
        assert (await _build(entries=[{"address": ADDR_1}]))["error"] == "UNEXPECTED"


class TestDecode:
    async def test_bytes_round_trip(self, mock_client):
        mock_client.decode_manifest.return_value = DecodedManifest(
            source="manifest", name="demo", torrent_info_hash_v1="ab" * 20,
            entries=[_info(exact_size=7, kind="embedded", data_map="dd")],
        )
        out = await _decode(manifest_base64=B64, resolve=True)
        mock_client.decode_manifest.assert_awaited_once_with(MANIFEST_BYTES, resolve=True)
        mock_client.decode_manifest_link.assert_not_called()
        assert out["source"] == "manifest"
        assert out["name"] == "demo"
        assert out["torrent_info_hash_v1"] == "ab" * 20
        assert out["torrent_info_hash_v2"] is None
        assert out["entries"][0]["exact_size"] == 7
        assert out["entries"][0]["data_map"] == "dd"

    async def test_link_forwarded_and_resolve_defaults_false(self, mock_client):
        mock_client.decode_manifest_link.return_value = DecodedManifest(
            source="file_link", entries=[_info(path=None, effective_name=ADDR_1)]
        )
        out = await _decode(link=ADDR_1)
        mock_client.decode_manifest_link.assert_awaited_once_with(ADDR_1, resolve=False)
        assert out["source"] == "file_link"
        assert out["name"] is None
        assert out["entries"][0]["path"] is None

    async def test_per_entry_resolve_error_is_not_a_failed_call(self, mock_client):
        mock_client.decode_manifest_link.return_value = DecodedManifest(
            source="manifest", entries=[_info(error="not found")]
        )
        out = await _decode(link=LINK, resolve=True)
        assert "error" in out["entries"][0] and out["entries"][0]["error"] == "not found"
        assert out.get("error") is None

    @pytest.mark.parametrize("kwargs", [{}, {"manifest_base64": B64, "link": LINK}])
    async def test_needs_exactly_one_input(self, mock_client, kwargs):
        out = await _decode(**kwargs)
        assert out["error"] == "BAD_REQUEST"
        assert "exactly one" in out["message"]
        mock_client.decode_manifest.assert_not_called()
        mock_client.decode_manifest_link.assert_not_called()

    async def test_invalid_base64(self, mock_client):
        out = await _decode(manifest_base64="not base64!!")
        assert out["error"] == "BAD_REQUEST"
        assert "base64" in out["message"]
        mock_client.decode_manifest.assert_not_called()

    async def test_daemon_400(self, mock_client):
        mock_client.decode_manifest_link.side_effect = BadRequestError("link is not a manifest link", 400)
        out = await _decode(link="ant://nope")
        assert out["error"] == "BAD_REQUEST"
        assert out["message"] == "link is not a manifest link"


class TestThroughRealRestClient:
    """The tools over the SDK's own REST client and a mocked transport."""

    @pytest.fixture
    def rest(self, monkeypatch):
        seen = []

        def handler(request: httpx.Request) -> httpx.Response:
            body = json.loads(request.content)
            seen.append((request.url.path, body))
            if request.url.path == "/v1/manifests/build":
                if len(body["entries"]) == 2:
                    return httpx.Response(
                        400, json={"error": "entries[1]: path must be relative", "code": "BAD_REQUEST"}
                    )
                return httpx.Response(200, json={
                    "manifest": B64, "link": LINK,
                    "entries": [{"effective_name": "a", "kind": "public", "content_address": ADDR_1}],
                })
            return httpx.Response(200, json={
                "source": "manifest",
                "entries": [{"effective_name": "a", "kind": "public", "content_address": ADDR_1}],
            })

        client = AsyncRestClient(base_url="http://test")
        client._http = httpx.AsyncClient(base_url="http://test", transport=httpx.MockTransport(handler))
        monkeypatch.setattr(manifests._server(), "_get_ctx", lambda ctx: (client, "test-net"))
        return seen

    async def test_build_sends_embed_roots_and_returns_base64(self, rest):
        out = await _build(entries=[{"address": ADDR_1}])
        assert out["manifest_base64"] == B64
        path, body = rest[0]
        assert body["embed_roots"] is True
        assert body["entries"] == [{"address": ADDR_1}]

    async def test_decode_sends_base64_on_the_wire(self, rest):
        out = await _decode(manifest_base64=B64)
        assert rest[0][1]["manifest"] == B64
        assert out["entries"][0]["size"] is None
        assert out["entries"][0]["exact_size"] is None

    async def test_400_maps_to_bad_request_with_entry_message(self, rest):
        out = await _build(entries=[{"address": ADDR_1}, {"address": ADDR_2, "path": "/x"}])
        assert out["error"] == "BAD_REQUEST"
        assert "entries[1]" in out["message"]


class TestRegistration:
    def test_tools_registered_with_annotations(self):
        tools = {t.name: t for t in asyncio.run(server.mcp.list_tools())}
        assert MANIFEST_TOOLS <= set(tools)
        for name in MANIFEST_TOOLS:
            a = tools[name].annotations
            assert a.read_only_hint is True
            assert a.destructive_hint is False
            assert a.idempotent_hint is True
            assert a.open_world_hint is True
            assert tools[name].description

    def test_input_schemas(self):
        tools = {t.name: t for t in asyncio.run(server.mcp.list_tools())}
        b = tools["build_manifest"].input_schema
        assert b["required"] == ["entries"]
        assert set(b["properties"]) == {"entries", "name", "torrent_info_hashes", "embed_roots"}
        d = tools["decode_manifest"].input_schema
        assert not d.get("required")
        assert set(d["properties"]) == {"manifest_base64", "link", "resolve"}

    def test_not_registered_without_the_sdk_api(self, monkeypatch):
        """Against an SDK without build_manifest the server still imports and
        registers none of the manifest tools."""
        from mcp.server.mcpserver import MCPServer

        monkeypatch.delattr(AsyncRestClient, "build_manifest")
        try:
            importlib.reload(manifests)
            assert manifests.MANIFESTS_AVAILABLE is False
            fresh = MCPServer("t")
            manifests.register(fresh)
            assert not MANIFEST_TOOLS & {t.name for t in asyncio.run(fresh.list_tools())}
        finally:
            monkeypatch.undo()
            importlib.reload(manifests)
        assert manifests.MANIFESTS_AVAILABLE is True
        fresh = MCPServer("t")
        manifests.register(fresh)
        assert MANIFEST_TOOLS == {t.name for t in asyncio.run(fresh.list_tools())}


_LIVE_URL = os.environ.get("ANTD_TEST_URL")
_LIVE_ADDRS = os.environ.get("ANTD_TEST_MANIFEST_ADDRESSES")


@pytest.mark.skipif(not (_LIVE_URL and _LIVE_ADDRS), reason="needs ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES")
class TestLive:
    """No paid calls: builds and decodes manifests of fixtures already uploaded."""

    @pytest.fixture
    async def live(self, monkeypatch):
        client = AsyncRestClient(base_url=_LIVE_URL)
        monkeypatch.setattr(manifests._server(), "_get_ctx", lambda ctx: (client, "live"))
        yield client
        await client.close()

    async def test_build_and_decode(self, live):
        a1, a2 = _LIVE_ADDRS.split(",")
        s1, s2 = (int(x) for x in os.environ["ANTD_TEST_MANIFEST_SIZES"].split(","))
        dm = os.environ["ANTD_TEST_MANIFEST_DATA_MAP"]
        dm_size = int(os.environ["ANTD_TEST_MANIFEST_DATA_MAP_SIZE"])
        built = await _build(
            entries=[
                {"path": "notes/one.txt", "address": a1},
                {"path": "notes/two.txt", "address": a2},
                {"path": "private/secret.bin", "data_map": dm},
            ],
            name="mcp-live",
        )
        assert "error" not in built, built
        assert built["link"]
        kinds = {e["effective_name"]: e["kind"] for e in built["entries"]}
        assert kinds == {"notes/one.txt": "public", "notes/two.txt": "public", "private/secret.bin": "embedded"}

        sizes = {"notes/one.txt": s1, "notes/two.txt": s2, "private/secret.bin": dm_size}
        for decoded in (
            await _decode(manifest_base64=built["manifest_base64"], resolve=True),
            await _decode(link=built["link"], resolve=True),
        ):
            assert decoded["source"] == "manifest"
            assert decoded["name"] == "mcp-live"
            by_name = {e["effective_name"]: e for e in decoded["entries"]}
            assert {n: e["exact_size"] for n, e in by_name.items()} == sizes
            assert by_name["private/secret.bin"]["kind"] == "embedded"
            assert by_name["private/secret.bin"]["data_map"]

        fixture_link = os.environ.get("ANTD_TEST_MANIFEST_LINK")
        if fixture_link:
            out = await _decode(link=fixture_link)
            assert out["source"] == "manifest" and len(out["entries"]) == 3

    async def test_bad_entry(self, live):
        a1 = _LIVE_ADDRS.split(",")[0]
        out = await _build(entries=[{"address": a1, "data_map": "ab"}])
        assert out["error"] == "BAD_REQUEST" and "entries[0]" in out["message"]
        out = await _build(entries=[{"address": a1}, {"path": "../x", "address": a1}])
        assert out["error"] == "BAD_REQUEST" and "entries[1]" in out["message"]
