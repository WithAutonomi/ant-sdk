"""Manifest API over gRPC: GrpcClient and AsyncGrpcClient against an
in-process ManifestService. Covers raw bytes on the wire, proto3 ``optional``
presence (an unset size reads as None, a 0 stays 0), the both-or-neither
entry check, the ``embed_roots`` default, INVALID_ARGUMENT mapping, and the
raised message limits on the manifest channel. Mirrors antd-go's manifest
suite."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

import grpc
import grpc.aio
import pytest
import pytest_asyncio

from antd import BadRequestError, ManifestEntryInfo, ManifestEntryInput
from antd._grpc import (
    _MANIFEST_CHANNEL_OPTIONS,
    _MAX_MANIFEST_GRPC_MESSAGE_BYTES,
    AsyncGrpcClient,
    GrpcClient,
)
from antd._proto.antd.v1 import manifests_pb2, manifests_pb2_grpc

HEADER = bytes([0xC1, ord("A"), ord("N"), ord("T"), 0x01])
ADDR = "42" * 32
U64_MAX = 2**64 - 1

# Past gRPC's default 4 MiB receive limit, well inside the raised one.
LARGE = 5 * 1024 * 1024
_SERVER_OPTIONS = [
    ("grpc.max_receive_message_length", 64 * 1024 * 1024),
    ("grpc.max_send_message_length", 64 * 1024 * 1024),
]

_BAD_PATH = 'Bad request: 1 invalid entries: entries[0]: invalid path "../x": path component ".." is not allowed'


def _invalid(context, details: str, empty):
    # set_code / set_details rather than abort(): the same servicer runs under
    # the sync and the aio server, and the aio abort() is a coroutine.
    context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
    context.set_details(details)
    return empty


class MockManifestServicer(manifests_pb2_grpc.ManifestServiceServicer):
    """Answers by request name / link; records every request."""

    def __init__(self):
        self.requests: list = []

    def Build(self, request, context):
        self.requests.append(("Build", request))
        if request.name == "invalid":
            return _invalid(context, _BAD_PATH, manifests_pb2.BuildManifestResponse())
        if request.name == "large":
            return manifests_pb2.BuildManifestResponse(manifest=b"\xab" * LARGE)
        return manifests_pb2.BuildManifestResponse(
            manifest=HEADER,
            link="ant://manifest/wUFOVAE",
            entries=[
                manifests_pb2.ManifestEntryInfo(
                    effective_name="a.txt", path="a.txt", size=10, kind="embedded",
                    content_address="cc", exact_size=10),
                manifests_pb2.ManifestEntryInfo(effective_name="11", kind="public", content_address="11"),
                manifests_pb2.ManifestEntryInfo(
                    effective_name="empty", path="empty", size=0, kind="public",
                    content_address="ee", exact_size=0),
            ],
        )

    def Decode(self, request, context):
        self.requests.append(("Decode", request))
        which = request.WhichOneof("input")
        if which == "link" and request.link == "invalid":
            return _invalid(context, "Bad request: not a manifest link", manifests_pb2.DecodeManifestResponse())
        if which == "link":
            return manifests_pb2.DecodeManifestResponse(
                source="file_link",
                entries=[manifests_pb2.ManifestEntryInfo(
                    effective_name=request.link, kind="public", content_address=request.link,
                    exact_size=46 if request.resolve else None)],
            )
        return manifests_pb2.DecodeManifestResponse(
            source="manifest",
            name=f"{len(request.manifest)} bytes",
            torrent_info_hash_v2="bb" * 32,
            entries=[
                manifests_pb2.ManifestEntryInfo(
                    effective_name="a.txt", path="a.txt", kind="embedded", content_address="cc",
                    data_map="abcd", exact_size=3),
                manifests_pb2.ManifestEntryInfo(
                    effective_name="b", path="b", kind="public", content_address="dd",
                    error="Record not found: gone"),
            ],
        )


@pytest.fixture
def servicer():
    return MockManifestServicer()


@pytest.fixture
def client(servicer):
    server = grpc.server(ThreadPoolExecutor(max_workers=4), options=_SERVER_OPTIONS)
    manifests_pb2_grpc.add_ManifestServiceServicer_to_server(servicer, server)
    port = server.add_insecure_port("127.0.0.1:0")
    server.start()
    c = GrpcClient(target=f"127.0.0.1:{port}")
    c.port = port
    try:
        yield c
    finally:
        c.close()
        server.stop(None)


@pytest_asyncio.fixture
async def aclient(servicer):
    server = grpc.aio.server(options=_SERVER_OPTIONS)
    manifests_pb2_grpc.add_ManifestServiceServicer_to_server(servicer, server)
    port = server.add_insecure_port("127.0.0.1:0")
    await server.start()
    c = AsyncGrpcClient(target=f"127.0.0.1:{port}")
    try:
        yield c
    finally:
        await c.close()
        await server.stop(None)


def _last(servicer):
    return servicer.requests[-1]


_ENTRIES = [ManifestEntryInput(path="a.txt", size=10, data_map="abcd"), ManifestEntryInput(address="11")]


class TestBuild:
    def test_request_shape(self, client, servicer):
        client.build_manifest(_ENTRIES, name="album", torrent_info_hashes=["aa" * 20])
        name, req = _last(servicer)
        assert name == "Build"
        assert req.HasField("name") and req.name == "album"
        assert req.HasField("embed_roots") and req.embed_roots is True
        assert list(req.torrent_info_hashes) == ["aa" * 20]
        first, second = req.entries
        assert first.HasField("path") and first.path == "a.txt"
        assert first.HasField("size") and first.size == 10
        assert first.WhichOneof("source") == "data_map" and first.data_map == "abcd"
        assert not second.HasField("path") and not second.HasField("size")
        assert second.WhichOneof("source") == "address" and second.address == "11"

    def test_embed_roots_is_sent_explicitly(self, client, servicer):
        client.build_manifest([ManifestEntryInput(address="11")])
        _, req = _last(servicer)
        assert req.HasField("embed_roots") and req.embed_roots is True
        assert not req.HasField("name") and list(req.torrent_info_hashes) == []
        client.build_manifest([ManifestEntryInput(address="11")], embed_roots=False)
        _, req = _last(servicer)
        assert req.HasField("embed_roots") and req.embed_roots is False

    def test_size_zero_is_present(self, client, servicer):
        client.build_manifest([ManifestEntryInput(address="11", size=0)])
        entry = _last(servicer)[1].entries[0]
        assert entry.HasField("size") and entry.size == 0

    def test_size_u64_max_is_sent(self, client, servicer):
        client.build_manifest([ManifestEntryInput(address="11", size=U64_MAX)])
        assert _last(servicer)[1].entries[0].size == U64_MAX

    def test_response_reads_raw_bytes_and_presence(self, client):
        res = client.build_manifest(_ENTRIES)
        assert (res.manifest, res.link) == (HEADER, "ant://manifest/wUFOVAE")
        assert res.entries == [
            ManifestEntryInfo(effective_name="a.txt", path="a.txt", size=10, kind="embedded",
                              content_address="cc", exact_size=10),
            ManifestEntryInfo(effective_name="11", kind="public", content_address="11"),
            ManifestEntryInfo(effective_name="empty", path="empty", size=0, kind="public",
                              content_address="ee", exact_size=0),
        ]
        public, empty = res.entries[1], res.entries[2]
        assert (public.size, public.exact_size, public.path, public.data_map, public.error) == (
            None, None, None, None, None)
        assert (empty.size, empty.exact_size) == (0, 0)

    @pytest.mark.parametrize("entry", [
        ManifestEntryInput(),
        ManifestEntryInput(path="a.txt"),
        ManifestEntryInput(data_map="aa", address="bb"),
        ManifestEntryInput(address="11", size=-1),
    ])
    def test_entry_check_before_sending(self, client, servicer, entry):
        with pytest.raises(BadRequestError, match=r"^1 invalid entries: entries\[0\]: "):
            client.build_manifest([entry])
        assert servicer.requests == []

    def test_invalid_argument_is_bad_request_with_the_daemon_message(self, client):
        with pytest.raises(BadRequestError) as info:
            client.build_manifest([ManifestEntryInput(address=ADDR, path="../x")], name="invalid")
        assert str(info.value) == _BAD_PATH
        assert info.value.status_code == grpc.StatusCode.INVALID_ARGUMENT.value[0]


class TestDecode:
    def test_bytes_are_sent_raw(self, client, servicer):
        res = client.decode_manifest(HEADER, resolve=True)
        _, req = _last(servicer)
        assert req.WhichOneof("input") == "manifest" and req.manifest == HEADER
        assert req.resolve is True
        assert (res.source, res.name) == ("manifest", "5 bytes")
        assert (res.torrent_info_hash_v1, res.torrent_info_hash_v2) == (None, "bb" * 32)
        embedded, failed = res.entries
        assert (embedded.data_map, embedded.exact_size, embedded.size) == ("abcd", 3, None)
        assert (failed.error, failed.exact_size, failed.data_map) == ("Record not found: gone", None, None)

    def test_link(self, client, servicer):
        res = client.decode_manifest_link(ADDR)
        _, req = _last(servicer)
        assert req.WhichOneof("input") == "link" and req.link == ADDR and req.resolve is False
        assert (res.source, res.name) == ("file_link", None)
        assert res.entries[0].exact_size is None
        res = client.decode_manifest_link(ADDR, resolve=True)
        assert res.entries[0].exact_size == 46

    def test_empty_input_is_refused_before_sending(self, client, servicer):
        for call, arg in ((client.decode_manifest, b""), (client.decode_manifest_link, "")):
            with pytest.raises(BadRequestError) as info:
                call(arg)
            assert str(info.value) == "needs a manifest (base64 .ant bytes) or a link"
            assert info.value.status_code == 400
        assert servicer.requests == []

    def test_invalid_argument_is_bad_request(self, client):
        with pytest.raises(BadRequestError, match="not a manifest link"):
            client.decode_manifest_link("invalid")


class TestMessageLimits:
    def test_manifest_channel_options(self):
        options = dict(_MANIFEST_CHANNEL_OPTIONS)
        assert options == {
            "grpc.max_receive_message_length": _MAX_MANIFEST_GRPC_MESSAGE_BYTES,
            "grpc.max_send_message_length": _MAX_MANIFEST_GRPC_MESSAGE_BYTES,
        }
        # antd-go's maxManifestGrpcMessage; above the 64 MiB manifest cap and
        # the daemon's 100 MiB request limit.
        assert _MAX_MANIFEST_GRPC_MESSAGE_BYTES == 256 * 1024 * 1024

    def test_manifests_use_their_own_channel(self, client):
        assert client._manifest_channel is not client._channel

    def test_receives_a_manifest_past_the_default_limit(self, client):
        res = client.build_manifest([ManifestEntryInput(address="11")], name="large")
        assert len(res.manifest) == LARGE

    def test_sends_a_manifest_past_the_default_limit(self, client):
        res = client.decode_manifest(b"\xcd" * LARGE)
        assert res.name == f"{LARGE} bytes"

    def test_a_default_channel_would_refuse_it(self, client):
        # The control: the same response through a channel with gRPC's
        # defaults fails, so the tests above exercise the raised limit.
        with grpc.insecure_channel(f"127.0.0.1:{client.port}") as channel:
            stub = manifests_pb2_grpc.ManifestServiceStub(channel)
            with pytest.raises(grpc.RpcError) as info:
                stub.Build(manifests_pb2.BuildManifestRequest(name="large"))
        assert info.value.code() == grpc.StatusCode.RESOURCE_EXHAUSTED


class TestAsync:
    @pytest.mark.asyncio
    async def test_build(self, aclient, servicer):
        res = await aclient.build_manifest(_ENTRIES, name="album")
        _, req = _last(servicer)
        assert req.name == "album" and req.HasField("embed_roots") and req.embed_roots is True
        assert not req.entries[1].HasField("size")
        assert res.manifest == HEADER
        assert (res.entries[1].size, res.entries[2].size) == (None, 0)

    def test_every_bad_entry_is_reported_together(self, client, servicer):
        with pytest.raises(BadRequestError) as info:
            client.build_manifest([
                ManifestEntryInput(data_map="aa", address="bb"),
                ManifestEntryInput(address="11"),
                ManifestEntryInput(path="x"),
            ])
        assert str(info.value) == (
            "2 invalid entries: entries[0]: give data_map or address, not both; "
            "entries[2]: needs a data_map or an address"
        )
        assert info.value.status_code == 400
        assert servicer.requests == []

    @pytest.mark.asyncio
    async def test_entry_check_before_sending(self, aclient, servicer):
        with pytest.raises(BadRequestError, match="^1 invalid entries: entries.0.: give data_map or address, not both$"):
            await aclient.build_manifest([ManifestEntryInput(data_map="aa", address="bb")])
        assert servicer.requests == []

    @pytest.mark.asyncio
    async def test_decode_bytes_and_link(self, aclient, servicer):
        res = await aclient.decode_manifest(HEADER, resolve=True)
        assert _last(servicer)[1].manifest == HEADER
        assert res.entries[0].data_map == "abcd"
        res = await aclient.decode_manifest_link(ADDR, resolve=True)
        assert (res.source, res.entries[0].exact_size) == ("file_link", 46)

    @pytest.mark.asyncio
    async def test_invalid_argument_is_bad_request(self, aclient):
        with pytest.raises(BadRequestError, match=r"entries\[0\]"):
            await aclient.build_manifest([ManifestEntryInput(address=ADDR, path="../x")], name="invalid")

    @pytest.mark.asyncio
    async def test_large_manifest_both_ways(self, aclient):
        res = await aclient.build_manifest([ManifestEntryInput(address="11")], name="large")
        assert len(res.manifest) == LARGE
        res = await aclient.decode_manifest(b"\xcd" * LARGE)
        assert res.name == f"{LARGE} bytes"
