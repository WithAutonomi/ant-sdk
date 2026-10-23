"""``sha256`` on upload results and manifest entries (antd 0.17.0 or later),
over REST (mock daemon) and gRPC (in-process services), sync and async.

Covers: every upload result type reads ``sha256`` when present and None when
the key is absent (REST) or ``""`` (gRPC); a manifest build sends ``sha256``
only on an entry that sets it (REST: key omitted; gRPC: proto3 ``optional``
presence); ``ManifestEntryInfo`` reads it from build and decode responses; and
a malformed one comes back as the daemon's bad-request error with its message.
"""

from __future__ import annotations

import json
import threading
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, HTTPServer

import grpc
import grpc.aio
import pytest
import pytest_asyncio

from antd import (
    BadRequestError,
    DataPutPublicResult,
    DataPutResult,
    FilePutPublicResult,
    FilePutResult,
    FinalizeUploadResult,
    ManifestEntryInfo,
    ManifestEntryInput,
)
from antd._grpc import AsyncGrpcClient, GrpcClient
from antd._proto.antd.v1 import (
    data_pb2,
    data_pb2_grpc,
    files_pb2,
    files_pb2_grpc,
    manifests_pb2,
    manifests_pb2_grpc,
    upload_pb2,
    upload_pb2_grpc,
)
from antd._rest import AsyncRestClient, RestClient

SHA = "ab" * 32
BAD_SHA_MSG = "Bad request: 1 invalid entries: entries[0]: invalid hex sha256: Invalid character 'z' at position 0"

# (method name, arguments, result type, daemon route, REST body without sha256)
_UPLOADS = [
    ("data_put", (b"x",), DataPutResult, "/v1/data", {"data_map": "dd", "chunks_stored": 1}),
    ("data_put_public", (b"x",), DataPutPublicResult, "/v1/data/public", {"address": "aa", "chunks_stored": 1}),
    ("file_put", ("f",), FilePutResult, "/v1/files", {
        "data_map": "dd", "storage_cost_atto": "1", "gas_cost_wei": "2", "chunks_stored": 1,
        "payment_mode_used": "single"}),
    ("file_put_public", ("f",), FilePutPublicResult, "/v1/files/public", {
        "address": "aa", "storage_cost_atto": "1", "gas_cost_wei": "2", "chunks_stored": 1,
        "payment_mode_used": "single"}),
    ("finalize_upload", ("id", {}), FinalizeUploadResult, "/v1/upload/finalize", {
        "address": "aa", "chunks_stored": 1, "data_map": "dd"}),
    ("finalize_merkle_upload", ("id", "pool"), FinalizeUploadResult, "/v1/upload/finalize", {
        "address": "aa", "chunks_stored": 1, "data_map": "dd"}),
]
_IDS = [u[0] for u in _UPLOADS]


# --- REST mock daemon ----------------------------------------------------------


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        self.server.requests.append((self.path, json.loads(raw) if raw else None))
        status, payload = self.server.routes.get(
            self.path, (404, {"error": f"no route {self.path}", "code": "NOT_FOUND"}))
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


@pytest.fixture
def server():
    srv = HTTPServer(("127.0.0.1", 0), _Handler)
    srv.routes = {}
    srv.requests = []
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


class TestRestUploadResults:
    @pytest.mark.parametrize("method, args, kind, route, body", _UPLOADS, ids=_IDS)
    def test_reads_sha256_when_present(self, client, server, method, args, kind, route, body):
        server.routes[route] = (200, {**body, "sha256": SHA})
        res = getattr(client, method)(*args)
        assert isinstance(res, kind)
        assert res.sha256 == SHA

    @pytest.mark.parametrize("method, args, kind, route, body", _UPLOADS, ids=_IDS)
    def test_reads_none_when_absent_null_or_empty(self, client, server, method, args, kind, route, body):
        for extra in ({}, {"sha256": None}, {"sha256": ""}):
            server.routes[route] = (200, {**body, **extra})
            assert getattr(client, method)(*args).sha256 is None

    @pytest.mark.parametrize("method, args, kind, route, body", _UPLOADS, ids=_IDS)
    @pytest.mark.asyncio
    async def test_async_reads_sha256_and_none(self, aclient, server, method, args, kind, route, body):
        server.routes[route] = (200, {**body, "sha256": SHA})
        res = await getattr(aclient, method)(*args)
        assert isinstance(res, kind) and res.sha256 == SHA
        server.routes[route] = (200, body)
        assert (await getattr(aclient, method)(*args)).sha256 is None

    def test_existing_construction_still_works(self):
        assert DataPutResult(data_map="dd").sha256 is None
        assert DataPutPublicResult("aa", 1, "single").sha256 is None
        assert FilePutResult("dd", "1", "2", 1, "single").sha256 is None
        assert FilePutPublicResult("aa", "1", "2", 1, "single").sha256 is None
        assert FinalizeUploadResult("aa", 1, "dd", "ee").sha256 is None


_BUILD = "/v1/manifests/build"
_DECODE = "/v1/manifests/decode"
_ENTRY = {"effective_name": "a.txt", "path": "a.txt", "kind": "public", "content_address": "11"}


class TestRestManifests:
    def test_build_sends_sha256_only_when_set(self, client, server):
        server.routes[_BUILD] = (200, {"manifest": "wUFOVAE=", "entries": []})
        client.build_manifest([
            ManifestEntryInput(address="11", path="a.txt", sha256=SHA),
            ManifestEntryInput(address="22", path="b.txt"),
            ManifestEntryInput(address="33", path="c.txt", sha256=""),
            ManifestEntryInput(data_map="dd", sha256=SHA.upper()),
        ])
        assert server.requests[-1][1]["entries"] == [
            {"path": "a.txt", "sha256": SHA, "address": "11"},
            {"path": "b.txt", "address": "22"},
            {"path": "c.txt", "address": "33"},
            {"sha256": SHA.upper(), "data_map": "dd"},  # passed through as given
        ]

    @pytest.mark.asyncio
    async def test_async_build_sends_sha256_only_when_set(self, aclient, server):
        server.routes[_BUILD] = (200, {"manifest": "wUFOVAE=", "entries": []})
        await aclient.build_manifest([
            ManifestEntryInput(address="11", sha256=SHA), ManifestEntryInput(address="22")])
        assert server.requests[-1][1]["entries"] == [{"sha256": SHA, "address": "11"}, {"address": "22"}]

    def test_entry_info_reads_sha256_from_build_and_decode(self, client, server):
        entries = [
            {**_ENTRY, "sha256": SHA},
            {**_ENTRY, "effective_name": "b"},
            {**_ENTRY, "effective_name": "c", "sha256": ""},
            {**_ENTRY, "effective_name": "d", "sha256": None},
        ]
        server.routes[_BUILD] = (200, {"manifest": "wUFOVAE=", "entries": entries})
        server.routes[_DECODE] = (200, {"source": "manifest", "entries": entries})
        built = client.build_manifest([ManifestEntryInput(address="11")])
        decoded = client.decode_manifest(b"\xc1ANT\x01")
        for got in (built.entries, decoded.entries):
            assert [e.sha256 for e in got] == [SHA, None, None, None]

    @pytest.mark.asyncio
    async def test_async_entry_info_reads_sha256(self, aclient, server):
        server.routes[_DECODE] = (200, {"source": "manifest", "entries": [{**_ENTRY, "sha256": SHA}, _ENTRY]})
        decoded = await aclient.decode_manifest_link("ant://manifest/x")
        assert [e.sha256 for e in decoded.entries] == [SHA, None]

    def test_bad_sha256_is_the_bad_request_error_with_the_daemon_message(self, client, server):
        server.routes[_BUILD] = (400, {"error": BAD_SHA_MSG, "code": "BAD_REQUEST"})
        with pytest.raises(BadRequestError) as info:
            client.build_manifest([ManifestEntryInput(address="11", sha256="zz")])
        assert info.value.status_code == 400
        assert "invalid hex sha256" in str(info.value)
        # Nothing was refused client-side: the hash went out as given.
        assert server.requests[-1][1]["entries"] == [{"sha256": "zz", "address": "11"}]

    def test_entry_info_construction_unchanged(self):
        assert ManifestEntryInfo(effective_name="a").sha256 is None
        assert ManifestEntryInput(address="11").sha256 is None


# --- gRPC mock services --------------------------------------------------------


def _bad_sha(context, empty):
    context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
    context.set_details(BAD_SHA_MSG)
    return empty


class _Data(data_pb2_grpc.DataServiceServicer):
    """The hash comes from the payload: b"has" -> SHA, anything else -> unset."""

    def Put(self, request, context):
        return data_pb2.PutDataResponse(
            data_map="dd", chunks_stored=1, sha256=SHA if request.data == b"has" else "")

    def PutPublic(self, request, context):
        return data_pb2.PutPublicDataResponse(
            address="aa", chunks_stored=1, sha256=SHA if request.data == b"has" else "")


class _Files(files_pb2_grpc.FileServiceServicer):
    def Put(self, request, context):
        return files_pb2.PutFileResponse(
            data_map="dd", chunks_stored=1, sha256=SHA if request.path == "has" else "")

    def PutPublic(self, request, context):
        return files_pb2.PutFilePublicResponse(
            address="aa", chunks_stored=1, sha256=SHA if request.path == "has" else "")


class _Upload(upload_pb2_grpc.UploadServiceServicer):
    def FinalizeUpload(self, request, context):
        return upload_pb2.FinalizeUploadResponse(
            address="aa", chunks_stored=1, sha256=SHA if request.upload_id == "has" else "")


class _Manifests(manifests_pb2_grpc.ManifestServiceServicer):
    def __init__(self):
        self.requests: list = []

    def Build(self, request, context):
        self.requests.append(request)
        if any(e.HasField("sha256") and e.sha256 == "zz" for e in request.entries):
            return _bad_sha(context, manifests_pb2.BuildManifestResponse())
        return manifests_pb2.BuildManifestResponse(manifest=b"\xc1ANT\x01", entries=self._infos())

    def Decode(self, request, context):
        return manifests_pb2.DecodeManifestResponse(source="manifest", entries=self._infos())

    @staticmethod
    def _infos():
        return [
            manifests_pb2.ManifestEntryInfo(effective_name="a", kind="public", content_address="11", sha256=SHA),
            manifests_pb2.ManifestEntryInfo(effective_name="b", kind="public", content_address="22"),
            manifests_pb2.ManifestEntryInfo(effective_name="c", kind="public", content_address="33", sha256=""),
        ]


def _register(server):
    manifests = _Manifests()
    data_pb2_grpc.add_DataServiceServicer_to_server(_Data(), server)
    files_pb2_grpc.add_FileServiceServicer_to_server(_Files(), server)
    upload_pb2_grpc.add_UploadServiceServicer_to_server(_Upload(), server)
    manifests_pb2_grpc.add_ManifestServiceServicer_to_server(manifests, server)
    return manifests


@pytest.fixture
def grpc_client():
    server = grpc.server(ThreadPoolExecutor(max_workers=4))
    manifests = _register(server)
    port = server.add_insecure_port("127.0.0.1:0")
    server.start()
    c = GrpcClient(target=f"127.0.0.1:{port}")
    c.manifests = manifests
    try:
        yield c
    finally:
        c.close()
        server.stop(None)


@pytest_asyncio.fixture
async def agrpc_client():
    server = grpc.aio.server()
    manifests = _register(server)
    port = server.add_insecure_port("127.0.0.1:0")
    await server.start()
    c = AsyncGrpcClient(target=f"127.0.0.1:{port}")
    c.manifests = manifests
    try:
        yield c
    finally:
        await c.close()
        await server.stop(None)


# Arguments that make the mock answer with / without a hash.
_GRPC_CALLS = [
    ("data_put", (b"has",), (b"no",), DataPutResult),
    ("data_put_public", (b"has",), (b"no",), DataPutPublicResult),
    ("file_put", ("has",), ("no",), FilePutResult),
    ("file_put_public", ("has",), ("no",), FilePutPublicResult),
    ("finalize_upload", ("has", {}), ("no", {}), FinalizeUploadResult),
    ("finalize_merkle_upload", ("has", "pool"), ("no", "pool"), FinalizeUploadResult),
]


class TestGrpcUploadResults:
    @pytest.mark.parametrize("method, has, no, kind", _GRPC_CALLS, ids=[c[0] for c in _GRPC_CALLS])
    def test_reads_sha256_and_empty_as_none(self, grpc_client, method, has, no, kind):
        res = getattr(grpc_client, method)(*has)
        assert isinstance(res, kind) and res.sha256 == SHA
        assert getattr(grpc_client, method)(*no).sha256 is None

    @pytest.mark.parametrize("method, has, no, kind", _GRPC_CALLS, ids=[c[0] for c in _GRPC_CALLS])
    @pytest.mark.asyncio
    async def test_async_reads_sha256_and_empty_as_none(self, agrpc_client, method, has, no, kind):
        res = await getattr(agrpc_client, method)(*has)
        assert isinstance(res, kind) and res.sha256 == SHA
        assert (await getattr(agrpc_client, method)(*no)).sha256 is None


class TestGrpcManifests:
    def test_build_sets_sha256_only_when_given(self, grpc_client):
        grpc_client.build_manifest([
            ManifestEntryInput(address="11", sha256=SHA),
            ManifestEntryInput(address="22"),
            ManifestEntryInput(address="33", sha256=""),
            ManifestEntryInput(address="44", sha256=SHA.upper()),
        ])
        first, second, third, fourth = grpc_client.manifests.requests[-1].entries
        assert first.HasField("sha256") and first.sha256 == SHA
        assert not second.HasField("sha256")
        assert not third.HasField("sha256")
        assert fourth.sha256 == SHA.upper()  # passed through as given

    @pytest.mark.asyncio
    async def test_async_build_sets_sha256_only_when_given(self, agrpc_client):
        await agrpc_client.build_manifest([
            ManifestEntryInput(address="11", sha256=SHA), ManifestEntryInput(address="22")])
        first, second = agrpc_client.manifests.requests[-1].entries
        assert first.HasField("sha256") and first.sha256 == SHA
        assert not second.HasField("sha256")

    def test_entry_info_reads_sha256_from_build_and_decode(self, grpc_client):
        built = grpc_client.build_manifest([ManifestEntryInput(address="11")])
        decoded = grpc_client.decode_manifest(b"\xc1ANT\x01")
        for got in (built.entries, decoded.entries):
            assert [e.sha256 for e in got] == [SHA, None, None]

    @pytest.mark.asyncio
    async def test_async_entry_info_reads_sha256(self, agrpc_client):
        built = await agrpc_client.build_manifest([ManifestEntryInput(address="11")])
        decoded = await agrpc_client.decode_manifest_link("ant://manifest/x")
        for got in (built.entries, decoded.entries):
            assert [e.sha256 for e in got] == [SHA, None, None]

    def test_bad_sha256_is_the_bad_request_error_with_the_daemon_message(self, grpc_client):
        with pytest.raises(BadRequestError) as info:
            grpc_client.build_manifest([ManifestEntryInput(address="11", sha256="zz")])
        assert str(info.value) == BAD_SHA_MSG
        assert info.value.status_code == grpc.StatusCode.INVALID_ARGUMENT.value[0]

    @pytest.mark.asyncio
    async def test_async_bad_sha256(self, agrpc_client):
        with pytest.raises(BadRequestError, match="invalid hex sha256"):
            await agrpc_client.build_manifest([ManifestEntryInput(address="11", sha256="zz")])
