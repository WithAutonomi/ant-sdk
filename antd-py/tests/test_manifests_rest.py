"""Manifest API over REST: RestClient and AsyncRestClient against a local mock
daemon. Covers the base64 wire form of the ``.ant`` bytes, unset sizes reading
as None (never 0), the both-or-neither entry check, the ``embed_roots``
default and the 400 mapping. Mirrors antd-go's manifest suite."""

from __future__ import annotations

import base64
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest
import pytest_asyncio

from antd import (
    BadRequestError,
    BuiltManifest,
    DecodedManifest,
    InternalError,
    ManifestEntryInfo,
    ManifestEntryInput,
)
from antd._rest import AsyncRestClient, RestClient

# The five-byte `.ant` header; "wUFOVAE=" is its base64.
HEADER = bytes([0xC1, ord("A"), ord("N"), ord("T"), 0x01])
HEADER_B64 = "wUFOVAE="
# Bytes whose base64 uses "+" and "/" (the standard alphabet, not URL-safe).
BINARY = bytes(range(256))
ADDR = "42" * 32
U64_MAX = 2**64 - 1

BUILD = ("POST", "/v1/manifests/build")
DECODE = ("POST", "/v1/manifests/decode")

_BUILT = {
    "manifest": HEADER_B64,
    "link": "ant://manifest/wUFOVAE",
    "entries": [
        {"effective_name": "a.txt", "path": "a.txt", "size": 10, "kind": "embedded",
         "content_address": "cc", "exact_size": 10},
        {"effective_name": "11", "kind": "public", "content_address": "11"},
    ],
}

_DECODED = {
    "source": "manifest",
    "name": "album",
    "torrent_info_hash_v2": "bb" * 32,
    "entries": [
        {"effective_name": "a.txt", "path": "a.txt", "kind": "embedded",
         "content_address": "cc", "data_map": "abcd", "exact_size": 3},
        {"effective_name": "b", "path": "b", "kind": "public", "content_address": "dd",
         "error": "Record not found: gone"},
        {"effective_name": "empty", "path": "empty", "size": 0, "kind": "public",
         "content_address": "ee", "exact_size": 0},
    ],
}

_BAD_PATH = {
    "error": 'Bad request: 1 invalid entries: entries[0]: invalid path "../x": path component ".." is not allowed',
    "code": "BAD_REQUEST",
}


class _Handler(BaseHTTPRequestHandler):
    """Answers each (method, path) from the server's route table and records
    every request, so tests can assert on exactly what was sent."""

    def log_message(self, format, *args):
        pass

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        body = json.loads(raw) if raw else None
        self.server.requests.append(("POST", self.path, body))
        status, payload = self.server.routes.get(
            ("POST", self.path), (404, {"error": f"no route {self.path}", "code": "NOT_FOUND"}),
        )
        data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


@pytest.fixture
def server():
    srv = HTTPServer(("127.0.0.1", 0), _Handler)
    srv.routes = {BUILD: (200, _BUILT), DECODE: (200, _DECODED)}
    srv.requests = []
    # A short poll keeps shutdown(), once per test, from waiting 0.5 s.
    t = threading.Thread(target=srv.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
    t.start()
    try:
        yield srv
    finally:
        srv.shutdown()
        srv.server_close()


@pytest.fixture
def client(server):
    c = RestClient(base_url=f"http://127.0.0.1:{server.server_address[1]}", timeout=5.0)
    try:
        yield c
    finally:
        c.close()


@pytest_asyncio.fixture
async def aclient(server):
    c = AsyncRestClient(base_url=f"http://127.0.0.1:{server.server_address[1]}", timeout=5.0)
    try:
        yield c
    finally:
        await c.close()


def _sent(server) -> dict:
    return server.requests[-1][2]


# --- Build -------------------------------------------------------------------


class TestBuild:
    def test_sends_entries_and_options(self, client, server):
        res = client.build_manifest(
            [
                ManifestEntryInput(path="a.txt", size=10, data_map="abcd"),
                ManifestEntryInput(address="11"),
            ],
            name="album",
            torrent_info_hashes=["aa" * 20, "bb" * 32],
            embed_roots=False,
        )
        assert isinstance(res, BuiltManifest)
        method, path, body = server.requests[-1]
        assert (method, path) == BUILD
        assert body == {
            "entries": [{"path": "a.txt", "size": 10, "data_map": "abcd"}, {"address": "11"}],
            "embed_roots": False,
            "name": "album",
            "torrent_info_hashes": ["aa" * 20, "bb" * 32],
        }

    def test_embed_roots_defaults_to_true_and_unset_options_are_omitted(self, client, server):
        client.build_manifest([ManifestEntryInput(address="11")])
        assert _sent(server) == {"entries": [{"address": "11"}], "embed_roots": True}

    def test_empty_name_path_and_hashes_are_omitted(self, client, server):
        client.build_manifest([ManifestEntryInput(address="11", path="")], name="", torrent_info_hashes=[])
        assert _sent(server) == {"entries": [{"address": "11"}], "embed_roots": True}

    def test_size_zero_is_sent(self, client, server):
        client.build_manifest([ManifestEntryInput(address="11", size=0)])
        assert _sent(server)["entries"] == [{"size": 0, "address": "11"}]

    def test_size_up_to_u64_max_is_sent(self, client, server):
        client.build_manifest([ManifestEntryInput(address="11", size=U64_MAX)])
        assert _sent(server)["entries"][0]["size"] == U64_MAX

    def test_reads_raw_bytes_link_and_entries(self, client):
        res = client.build_manifest([ManifestEntryInput(address="11")])
        assert res.manifest == HEADER
        assert res.link == "ant://manifest/wUFOVAE"
        assert res.entries == [
            ManifestEntryInfo(effective_name="a.txt", path="a.txt", size=10, kind="embedded",
                              content_address="cc", exact_size=10),
            ManifestEntryInfo(effective_name="11", kind="public", content_address="11"),
        ]

    def test_unset_fields_read_as_none_not_zero(self, client):
        public = client.build_manifest([ManifestEntryInput(address="11")]).entries[1]
        assert public.size is None
        assert public.exact_size is None
        assert (public.path, public.data_map, public.error) == (None, None, None)

    def test_link_absent_reads_as_none(self, client, server):
        server.routes[BUILD] = (200, {"manifest": HEADER_B64, "entries": []})
        res = client.build_manifest([ManifestEntryInput(address="11")])
        assert (res.manifest, res.link, res.entries) == (HEADER, None, [])

    def test_standard_base64_alphabet_decodes(self, client, server):
        server.routes[BUILD] = (200, {"manifest": base64.b64encode(BINARY).decode(), "entries": []})
        assert client.build_manifest([ManifestEntryInput(address="11")]).manifest == BINARY

    @pytest.mark.parametrize("bad", ["not base64!", "wUFOVAE", 123, ["wUFOVAE="]])
    def test_malformed_base64_is_an_error(self, client, server, bad):
        server.routes[BUILD] = (200, {"manifest": bad, "entries": []})
        with pytest.raises(InternalError):
            client.build_manifest([ManifestEntryInput(address="11")])

    def test_daemon_bad_request_keeps_its_message(self, client, server):
        server.routes[BUILD] = (400, _BAD_PATH)
        with pytest.raises(BadRequestError) as info:
            client.build_manifest([ManifestEntryInput(address=ADDR, path="../x")])
        assert info.value.status_code == 400
        assert "entries[0]" in str(info.value) and '"../x"' in str(info.value)


class TestEntryCheck:
    @pytest.mark.parametrize("entry, message", [
        (ManifestEntryInput(), "1 invalid entries: entries[0]: needs a data_map or an address"),
        (ManifestEntryInput(data_map="", address=""), "1 invalid entries: entries[0]: needs a data_map or an address"),
        (ManifestEntryInput(path="a.txt", size=1), "1 invalid entries: entries[0]: needs a data_map or an address"),
        (ManifestEntryInput(data_map="aa", address="bb"), "1 invalid entries: entries[0]: give data_map or address, not both"),
    ])
    def test_both_or_neither_is_refused_before_sending(self, client, server, entry, message):
        with pytest.raises(BadRequestError) as info:
            client.build_manifest([entry])
        assert str(info.value) == message
        assert info.value.status_code == 400
        assert server.requests == []

    def test_every_bad_entry_is_reported_together(self, client, server):
        entries = [
            ManifestEntryInput(data_map="aa", address="bb"),
            ManifestEntryInput(address="11"),
            ManifestEntryInput(path="x"),
        ]
        with pytest.raises(BadRequestError) as info:
            client.build_manifest(entries)
        assert str(info.value) == (
            "2 invalid entries: entries[0]: give data_map or address, not both; "
            "entries[2]: needs a data_map or an address"
        )
        assert info.value.status_code == 400
        assert server.requests == []

    def test_more_than_twenty_bad_entries_are_cut_short(self, client):
        with pytest.raises(BadRequestError) as info:
            client.build_manifest([ManifestEntryInput()] * 23)
        msg = str(info.value)
        assert msg.startswith("23 invalid entries: entries[0]: needs a data_map or an address; ")
        assert "entries[19]:" in msg and "entries[20]:" not in msg
        assert msg.endswith("; and 3 more")

    def test_names_the_offending_index(self, client, server):
        entries = [ManifestEntryInput(address="11"), ManifestEntryInput(data_map="aa", address="bb")]
        with pytest.raises(BadRequestError, match=r"^1 invalid entries: entries\[1\]: "):
            client.build_manifest(entries)
        assert server.requests == []

    @pytest.mark.parametrize("size", [-1, U64_MAX + 1, True, 1.5, "10"])
    def test_size_that_is_not_a_u64_is_refused_before_sending(self, client, server, size):
        with pytest.raises(BadRequestError, match=r"^1 invalid entries: entries\[0\]: size must be"):
            client.build_manifest([ManifestEntryInput(address="11", size=size)])
        assert server.requests == []

    def test_torrent_info_hashes_must_not_be_a_bare_string(self, client, server):
        with pytest.raises(TypeError):
            client.build_manifest([ManifestEntryInput(address="11")], torrent_info_hashes="aa" * 20)
        assert server.requests == []

    def test_entry_input_is_keyword_only(self):
        with pytest.raises(TypeError):
            ManifestEntryInput("abcd")  # type: ignore[misc]


# --- Decode ------------------------------------------------------------------


class TestDecode:
    def test_sends_base64_and_resolve(self, client, server):
        res = client.decode_manifest(HEADER, resolve=True)
        method, path, body = server.requests[-1]
        assert (method, path) == DECODE
        assert body == {"manifest": HEADER_B64, "resolve": True}
        assert isinstance(res, DecodedManifest)

    def test_resolve_defaults_to_false(self, client, server):
        client.decode_manifest(HEADER)
        assert _sent(server)["resolve"] is False

    def test_base64_round_trip(self, client, server):
        server.routes[BUILD] = (200, {"manifest": base64.b64encode(BINARY).decode(), "entries": []})
        built = client.build_manifest([ManifestEntryInput(address="11")])
        client.decode_manifest(built.manifest)
        assert base64.b64decode(_sent(server)["manifest"], validate=True) == BINARY

    def test_accepts_bytearray_and_memoryview(self, client, server):
        client.decode_manifest(bytearray(HEADER))
        client.decode_manifest(memoryview(HEADER))
        assert [r[2]["manifest"] for r in server.requests] == [HEADER_B64, HEADER_B64]

    def test_reads_header_fields_and_entries(self, client):
        res = client.decode_manifest(HEADER, resolve=True)
        assert (res.source, res.name) == ("manifest", "album")
        assert (res.torrent_info_hash_v1, res.torrent_info_hash_v2) == (None, "bb" * 32)
        embedded, failed, empty = res.entries
        assert (embedded.data_map, embedded.exact_size, embedded.size) == ("abcd", 3, None)
        assert (failed.error, failed.exact_size, failed.data_map) == ("Record not found: gone", None, None)
        # A recorded and resolved 0 stays 0.
        assert (empty.size, empty.exact_size) == (0, 0)

    def test_link_sends_the_link_and_no_bytes(self, client, server):
        server.routes[DECODE] = (200, {
            "source": "file_link",
            "entries": [{"effective_name": ADDR, "kind": "public", "content_address": ADDR, "exact_size": 46}],
        })
        res = client.decode_manifest_link(ADDR, resolve=True)
        assert _sent(server) == {"link": ADDR, "resolve": True}
        assert (res.source, res.name, res.torrent_info_hash_v1, res.torrent_info_hash_v2) == (
            "file_link", None, None, None)
        assert res.entries == [ManifestEntryInfo(
            effective_name=ADDR, kind="public", content_address=ADDR, exact_size=46)]

    def test_link_resolve_defaults_to_false(self, client, server):
        client.decode_manifest_link("ant://manifest/wUFOVAE")
        assert _sent(server) == {"link": "ant://manifest/wUFOVAE", "resolve": False}

    def test_empty_input_is_refused_before_sending(self, client, server):
        for call, arg in ((client.decode_manifest, b""), (client.decode_manifest_link, "")):
            with pytest.raises(BadRequestError) as info:
                call(arg)
            assert str(info.value) == "needs a manifest (base64 .ant bytes) or a link"
            assert info.value.status_code == 400
        assert server.requests == []

    def test_wrong_input_types_are_refused(self, client, server):
        with pytest.raises(TypeError):
            client.decode_manifest("ant://manifest/wUFOVAE")  # type: ignore[arg-type]
        with pytest.raises(TypeError):
            client.decode_manifest_link(HEADER)  # type: ignore[arg-type]
        assert server.requests == []

    def test_bad_request_is_typed(self, client, server):
        server.routes[DECODE] = (400, {
            "error": "Bad request: not a manifest: missing or invalid header", "code": "BAD_REQUEST"})
        with pytest.raises(BadRequestError, match="not a manifest"):
            client.decode_manifest(b"nope")

    @pytest.mark.parametrize("value", [-1, U64_MAX + 1, "3", 3.0, True, None])
    def test_malformed_sizes_read_as_none(self, client, server, value):
        server.routes[DECODE] = (200, {"source": "manifest", "entries": [
            {"effective_name": "a", "kind": "public", "content_address": "aa",
             "size": value, "exact_size": value}]})
        entry = client.decode_manifest(HEADER).entries[0]
        assert (entry.size, entry.exact_size) == (None, None)

    def test_u64_max_size_reads_back(self, client, server):
        server.routes[DECODE] = (200, {"source": "manifest", "entries": [
            {"effective_name": "a", "kind": "public", "content_address": "aa", "size": U64_MAX}]})
        assert client.decode_manifest(HEADER).entries[0].size == U64_MAX


# --- Async -------------------------------------------------------------------


class TestAsync:
    @pytest.mark.asyncio
    async def test_build(self, aclient, server):
        res = await aclient.build_manifest(
            [ManifestEntryInput(path="a.txt", size=10, data_map="abcd"), ManifestEntryInput(address="11")],
            name="album",
        )
        assert _sent(server) == {
            "entries": [{"path": "a.txt", "size": 10, "data_map": "abcd"}, {"address": "11"}],
            "embed_roots": True,
            "name": "album",
        }
        assert (res.manifest, res.link) == (HEADER, "ant://manifest/wUFOVAE")
        assert (res.entries[1].size, res.entries[1].exact_size) == (None, None)

    @pytest.mark.asyncio
    async def test_build_embed_roots_false(self, aclient, server):
        await aclient.build_manifest([ManifestEntryInput(address="11")], embed_roots=False)
        assert _sent(server)["embed_roots"] is False

    @pytest.mark.asyncio
    async def test_entry_check_before_sending(self, aclient, server):
        with pytest.raises(BadRequestError, match="^1 invalid entries: entries.0.: give data_map or address, not both$"):
            await aclient.build_manifest([ManifestEntryInput(data_map="aa", address="bb")])
        with pytest.raises(BadRequestError, match="^1 invalid entries: entries.0.: needs a data_map or an address$"):
            await aclient.build_manifest([ManifestEntryInput(path="x")])
        assert server.requests == []

    @pytest.mark.asyncio
    async def test_decode_bytes_and_link(self, aclient, server):
        res = await aclient.decode_manifest(HEADER, resolve=True)
        assert _sent(server) == {"manifest": HEADER_B64, "resolve": True}
        assert res.entries[2].size == 0 and res.entries[1].exact_size is None
        await aclient.decode_manifest_link("ant://manifest/wUFOVAE")
        assert _sent(server) == {"link": "ant://manifest/wUFOVAE", "resolve": False}

    @pytest.mark.asyncio
    async def test_bad_request(self, aclient, server):
        server.routes[BUILD] = (400, _BAD_PATH)
        with pytest.raises(BadRequestError, match=r"entries\[0\]"):
            await aclient.build_manifest([ManifestEntryInput(address=ADDR, path="../x")])
