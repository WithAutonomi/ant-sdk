"""Pointer API over gRPC: GrpcClient and AsyncGrpcClient against an
in-process PointerService, including the x-antd-error-code trailer mapping.
Mirrors the antd-go / antd-rust pointer suites."""

from __future__ import annotations

import base64
from concurrent.futures import ThreadPoolExecutor

import grpc
import grpc.aio
import pytest
import pytest_asyncio

from antd import (
    POINTER_FINAL_COUNTER,
    AlreadyExistsError,
    CloseGroupShortfallError,
    ConflictError,
    ForkError,
    InternalError,
    NetworkError,
    NotFoundError,
    PaymentError,
    PointerFinalError,
    PointerFinalityStatus,
    PointerForkedError,
    PointerKind,
    PointerOp,
)
from antd._grpc import AsyncGrpcClient, GrpcClient, _typed_status_error
from antd._proto.antd.v1 import (
    chunks_pb2,
    chunks_pb2_grpc,
    common_pb2,
    pointers_pb2,
    pointers_pb2_grpc,
)

A = "aa" * 32
B = "bb" * 32
T1 = "11" * 32
T2 = "22" * 32
STATE = "cc" * 32
U64_MAX = str(2**64 - 1)

_RETAINED = (
    "Close group shortfall: stored on 4 of 7 (paid attempt retained: call finalize "
    "again with the same upload_id to store it against the same payment)"
)

# owner / address -> (status, x-antd-error-code or None, details) for the
# error cases. Each mirrors how the daemon reports it; the mismatched ones put
# a tag on the wrong code, which the client must not trust.
_FAILURES = {
    "final": (grpc.StatusCode.FAILED_PRECONDITION, "POINTER_FINAL", "Pointer is final: transferred"),
    "forked": (grpc.StatusCode.FAILED_PRECONDITION, "POINTER_FORKED", "Pointer is forked: 2 final states"),
    "conflict": (grpc.StatusCode.ABORTED, "CONFLICT", "Conflict: a prepared write awaits payment"),
    "shortfall": (grpc.StatusCode.UNAVAILABLE, "CLOSE_GROUP_SHORTFALL", "Close group shortfall: only 3 answered"),
    "retained": (grpc.StatusCode.UNAVAILABLE, "CLOSE_GROUP_SHORTFALL", _RETAINED),
    "payment": (grpc.StatusCode.FAILED_PRECONDITION, None, "wallet not configured"),
    "aborted": (grpc.StatusCode.ABORTED, None, "version conflict"),
    "unavailable": (grpc.StatusCode.UNAVAILABLE, None, "network unreachable"),
    "exists": (grpc.StatusCode.ALREADY_EXISTS, None, "Already exists: pointer"),
    "missing": (grpc.StatusCode.NOT_FOUND, None, "no pointer"),
    "final-on-unavailable": (grpc.StatusCode.UNAVAILABLE, "POINTER_FINAL", "x"),
    "conflict-on-precondition": (grpc.StatusCode.FAILED_PRECONDITION, "CONFLICT", "x"),
    "shortfall-on-aborted": (grpc.StatusCode.ABORTED, "CLOSE_GROUP_SHORTFALL", "x"),
    "unknown-tag": (grpc.StatusCode.FAILED_PRECONDITION, "SOMETHING_NEW", "x"),
}


def _fail(context, key: str) -> None:
    status, tag, details = _FAILURES[key]
    if tag is not None:
        context.set_trailing_metadata((("x-antd-error-code", tag),))
    context.set_code(status)
    context.set_details(details)


def _final_state(target: str, holders: int, transferred_to: str = "") -> pointers_pb2.PointerFinalState:
    return pointers_pb2.PointerFinalState(
        state_id=STATE, kind="pointer", kind_tag=1, target=target, holders=holders,
        transferred_to=transferred_to,
    )


def _final_finality() -> pointers_pb2.PointerFinality:
    return pointers_pb2.PointerFinality(
        address=A, group=7, answered=7, status="final",
        state=_final_state(B, 7, B), transferred_to=B,
    )


class MockPointerServicer(pointers_pb2_grpc.PointerServiceServicer):
    """Answers by owner / address; records every request."""

    def __init__(self):
        self.requests: list = []

    def ListKeys(self, request, context):
        self.requests.append(("ListKeys", request))
        return pointers_pb2.ListPointerKeysResponse(
            keys=[pointers_pb2.PointerKey(address=A), pointers_pb2.PointerKey(address=B)])

    def _write(self, name, request, context, counter):
        self.requests.append((name, request))
        if request.owner in _FAILURES:
            _fail(context, request.owner)
            return pointers_pb2.PointerWriteResponse()
        if request.owner == "bad-counter":
            return pointers_pb2.PointerWriteResponse(address=A, state_id=STATE, counter="+1")
        return pointers_pb2.PointerWriteResponse(address=request.owner, state_id=STATE, counter=counter)

    def Create(self, request, context):
        return self._write("Create", request, context, "0")

    def Update(self, request, context):
        return self._write("Update", request, context, "1")

    def Transfer(self, request, context):
        self.requests.append(("Transfer", request))
        if request.owner in _FAILURES:
            _fail(context, request.owner)
            return pointers_pb2.PointerTransferResponse()
        if request.recipient == "unchecked":
            return pointers_pb2.PointerTransferResponse(
                address=request.owner, state_id=STATE, finality_error="only 5 of 7 answered")
        return pointers_pb2.PointerTransferResponse(
            address=request.owner, state_id=STATE, finality=_final_finality())

    def Get(self, request, context):
        self.requests.append(("Get", request))
        if request.address in _FAILURES:
            _fail(context, request.address)
            return pointers_pb2.PointerRecord()
        if request.address == A:
            return pointers_pb2.PointerRecord(
                address=A, owner="ab" * 1952, counter=U64_MAX, kind="pointer", kind_tag=1,
                target=B, state_id=STATE, is_final=True, transferred_to=B)
        counter = {"bad-counter": "1_000", "empty-counter": "", "overflow": str(2**64)}.get(request.address, "3")
        return pointers_pb2.PointerRecord(
            address=request.address, owner="ab" * 1952, counter=counter, kind="chunk", kind_tag=0,
            target=T1, state_id=STATE)

    def Resolve(self, request, context):
        self.requests.append(("Resolve", request))
        if request.address in _FAILURES:
            _fail(context, request.address)
            return pointers_pb2.PointerResolved()
        return pointers_pb2.PointerResolved(kind="chunk", kind_tag=0, target=T2)

    def Finality(self, request, context):
        self.requests.append(("Finality", request))
        if request.address in _FAILURES:
            _fail(context, request.address)
            return pointers_pb2.PointerFinality()
        if request.address == "open":
            return pointers_pb2.PointerFinality(address=A, group=7, answered=7, status="open", counter="1")
        if request.address == "open-uncorroborated":
            return pointers_pb2.PointerFinality(address=A, group=7, answered=5, status="open")
        if request.address == "forked-states":
            rivals = [_final_state(T1, 4), _final_state(T2, 2)]
            return pointers_pb2.PointerFinality(
                address=A, group=7, answered=7, status="forked", states=rivals, majority=rivals[0])
        if request.address == "contested":
            return pointers_pb2.PointerFinality(address=A, group=7, answered=7, status="contested")
        return _final_finality()

    def Controller(self, request, context):
        self.requests.append(("Controller", request))
        return pointers_pb2.PointerController(pointer=B, transfers=[B], frozen=False)

    def Prepare(self, request, context):
        self.requests.append(("Prepare", request))
        if request.owner in _FAILURES:
            _fail(context, request.owner)
            return pointers_pb2.PreparePointerResponse()
        signed = []
        if request.include_signed_quotes:
            signed = [
                common_pb2.SignedQuoteEntry(quote_hash="0xq1", quote=b"quote", commitment_sidecar=b"side"),
                common_pb2.SignedQuoteEntry(quote_hash="0xq2", quote=b"q2"),
            ]
        return pointers_pb2.PreparePointerResponse(
            upload_id="up-1", op=request.op, address=request.owner, state_id=STATE, counter="4",
            payment_type="wave_batch",
            payments=[common_pb2.PaymentEntry(quote_hash="0xq1", rewards_address="0xr1", amount="123")],
            total_amount="123", payment_vault_address="0xvault", payment_token_address="0xtoken",
            rpc_url="http://127.0.0.1:8545", signed_quotes=signed)

    def Finalize(self, request, context):
        self.requests.append(("Finalize", request))
        if request.upload_id in _FAILURES:
            _fail(context, request.upload_id)
            return pointers_pb2.FinalizePointerResponse()
        if request.upload_id == "transfer":
            return pointers_pb2.FinalizePointerResponse(
                address=A, state_id=STATE, counter=U64_MAX, finality=_final_finality())
        return pointers_pb2.FinalizePointerResponse(address=A, state_id=STATE, counter="0")


class MockChunkServicer(chunks_pb2_grpc.ChunkServiceServicer):
    """A non-pointer RPC the daemon can tag too: a chunk store whose close
    group fell short."""

    def Put(self, request, context):
        _fail(context, "shortfall")
        return chunks_pb2.PutChunkResponse()


def _add_servicers(server, servicer):
    pointers_pb2_grpc.add_PointerServiceServicer_to_server(servicer, server)
    chunks_pb2_grpc.add_ChunkServiceServicer_to_server(MockChunkServicer(), server)


@pytest.fixture
def servicer():
    return MockPointerServicer()


@pytest.fixture
def client(servicer):
    server = grpc.server(ThreadPoolExecutor(max_workers=4))
    _add_servicers(server, servicer)
    port = server.add_insecure_port("127.0.0.1:0")
    server.start()
    c = GrpcClient(target=f"127.0.0.1:{port}")
    try:
        yield c
    finally:
        c.close()
        server.stop(None)


@pytest_asyncio.fixture
async def aclient(servicer):
    server = grpc.aio.server()
    _add_servicers(server, servicer)
    port = server.add_insecure_port("127.0.0.1:0")
    await server.start()
    c = AsyncGrpcClient(target=f"127.0.0.1:{port}")
    try:
        yield c
    finally:
        await c.close()
        await server.stop(None)


# --- Methods -----------------------------------------------------------------


class TestSyncMethods:
    def test_keys(self, client):
        assert client.pointer_keys() == [A, B]

    def test_create_and_update_forward_owner_target_kind(self, client, servicer):
        w = client.pointer_create(A, T1)
        assert (w.address, w.state_id, w.counter) == (A, STATE, 0)
        name, req = servicer.requests[-1]
        assert (name, req.owner, req.target, req.kind) == ("Create", A, T1, "chunk")
        w = client.pointer_update(A, B, PointerKind.POINTER)
        assert w.counter == 1
        name, req = servicer.requests[-1]
        assert (name, req.kind) == ("Update", "pointer")

    def test_get_final_record_reads_u64_max_and_the_transfer(self, client):
        r = client.pointer_get(A)
        assert r.counter == POINTER_FINAL_COUNTER
        assert (r.is_final, r.transferred_to, r.target_kind) == (True, B, PointerKind.POINTER)

    def test_get_open_record_reads_empty_transfer_as_none(self, client):
        r = client.pointer_get(B)
        assert (r.counter, r.is_final, r.transferred_to, r.kind_tag) == (3, False, None, 0)

    @pytest.mark.parametrize("address", ["bad-counter", "empty-counter", "overflow"])
    def test_malformed_counter_is_an_error_not_a_zero(self, client, address):
        with pytest.raises(InternalError):
            client.pointer_get(address)

    def test_malformed_write_counter_is_an_error(self, client):
        with pytest.raises(InternalError):
            client.pointer_create("bad-counter", T1)

    def test_resolve_and_controller(self, client):
        t = client.pointer_resolve(A)
        assert (t.kind, t.kind_tag, t.target) == ("chunk", 0, T2)
        c = client.pointer_controller(A)
        assert (c.pointer, c.transfers, c.frozen) == (B, [B], False)

    def test_finality_final(self, client):
        f = client.pointer_finality(A)
        assert f.is_final and f.status is PointerFinalityStatus.FINAL
        assert (f.counter, f.transferred_to, f.majority, f.states) == (None, B, None, [])
        assert f.state is not None and (f.state.target, f.state.holders) == (B, 7)

    def test_finality_open_reads_the_counter_and_empty_as_none(self, client):
        f = client.pointer_finality("open")
        assert (f.status, f.counter, f.state, f.transferred_to) == (PointerFinalityStatus.OPEN, 1, None, None)
        f = client.pointer_finality("open-uncorroborated")
        assert (f.counter, f.answered, f.group) == (None, 5, 7)

    def test_finality_forked(self, client):
        f = client.pointer_finality("forked-states")
        assert f.status is PointerFinalityStatus.FORKED
        assert [(s.target, s.holders, s.transferred_to) for s in f.states] == [(T1, 4, None), (T2, 2, None)]
        assert f.majority is not None and f.majority.target == T1
        assert f.state is None

    def test_finality_unknown_status_is_kept(self, client):
        f = client.pointer_finality("contested")
        assert (f.status, f.raw_status) == (PointerFinalityStatus.UNKNOWN, "contested")

    def test_transfer_with_and_without_a_finality_check(self, client):
        t = client.pointer_transfer(A, B)
        assert t.finality is not None and t.finality.is_final and t.finality_error is None
        t = client.pointer_transfer(A, "unchecked")
        assert (t.finality, t.finality_error) == (None, "only 5 of 7 answered")

    @pytest.mark.parametrize("kwargs, expected", [
        ({"op": PointerOp.CREATE, "target": T1}, ("create", T1, "", "", False)),
        ({"op": "update", "target": B, "kind": PointerKind.POINTER}, ("update", B, "pointer", "", False)),
        ({"op": PointerOp.TRANSFER, "recipient": B}, ("transfer", "", "", B, False)),
        ({"op": PointerOp.UPDATE, "target": T2, "include_signed_quotes": True}, ("update", T2, "", "", True)),
    ])
    def test_prepare_sends_each_op_shape(self, client, servicer, kwargs, expected):
        kwargs = dict(kwargs)
        op = kwargs.pop("op")
        p = client.pointer_prepare(A, op, **kwargs)
        name, req = servicer.requests[-1]
        assert name == "Prepare" and req.owner == A
        assert (req.op, req.target, req.kind, req.recipient, req.include_signed_quotes) == expected
        assert (p.upload_id, p.op, p.counter, p.payment_type) == ("up-1", expected[0], 4, "wave_batch")
        assert [(x.quote_hash, x.amount) for x in p.payments] == [("0xq1", "123")]
        assert (p.payment_vault_address, p.payment_token_address, p.rpc_url) == (
            "0xvault", "0xtoken", "http://127.0.0.1:8545")

    def test_prepare_signed_quotes_are_base64_like_rest(self, client):
        p = client.pointer_prepare(A, PointerOp.UPDATE, target=T2, include_signed_quotes=True)
        assert [(q.quote_hash, q.quote, q.commitment_sidecar) for q in p.signed_quotes] == [
            ("0xq1", base64.b64encode(b"quote").decode(), base64.b64encode(b"side").decode()),
            ("0xq2", base64.b64encode(b"q2").decode(), None),
        ]

    def test_finalize_forwards_hashes_and_reads_a_transfer_finality(self, client, servicer):
        r = client.pointer_finalize("transfer", {"0xq1": "0xtx1"})
        name, req = servicer.requests[-1]
        assert (name, req.upload_id, dict(req.tx_hashes)) == ("Finalize", "transfer", {"0xq1": "0xtx1"})
        assert r.counter == POINTER_FINAL_COUNTER and r.finality is not None and r.finality.is_final
        r = client.pointer_finalize("create", {"0xq1": "0xtx1"})
        assert (r.counter, r.finality) == (0, None)


# --- Errors ------------------------------------------------------------------


class TestSyncErrors:
    @pytest.mark.parametrize("owner, exc", [
        ("final", PointerFinalError),
        ("forked", PointerForkedError),
        ("conflict", ConflictError),
        ("shortfall", CloseGroupShortfallError),
        # Untagged statuses keep the code mapping.
        ("payment", PaymentError),
        ("aborted", ForkError),
        ("unavailable", NetworkError),
        ("exists", AlreadyExistsError),
        # A tag that disagrees with the status, or one this SDK does not know,
        # is not trusted.
        ("final-on-unavailable", NetworkError),
        ("conflict-on-precondition", PaymentError),
        ("shortfall-on-aborted", ForkError),
        ("unknown-tag", PaymentError),
    ])
    def test_errors_map_by_the_daemon_tag_over_the_wire(self, client, owner, exc):
        with pytest.raises(exc) as exc_info:
            client.pointer_update(owner, T1)
        assert type(exc_info.value) is exc
        assert exc_info.value.status_code == _FAILURES[owner][0].value[0]
        assert str(exc_info.value) == _FAILURES[owner][2]

    def test_shortfall_on_a_read_is_not_retryable(self, client):
        with pytest.raises(CloseGroupShortfallError) as exc_info:
            client.pointer_get("shortfall")
        assert exc_info.value.retryable is False

    def test_retained_finalize_shortfall_is_retryable(self, client, servicer):
        with pytest.raises(CloseGroupShortfallError) as exc_info:
            client.pointer_finalize("retained", {"0xq1": "0xtx1"})
        assert exc_info.value.retryable is True
        # One attempt: the SDK leaves the repeat to the caller.
        assert [name for name, _ in servicer.requests] == ["Finalize"]

    def test_tagged_errors_map_on_every_service(self, client):
        with pytest.raises(CloseGroupShortfallError):
            client.chunk_put(b"x")

    def test_not_found_and_conflict_on_prepare(self, client):
        with pytest.raises(NotFoundError):
            client.pointer_resolve("missing")
        with pytest.raises(ConflictError):
            client.pointer_prepare("conflict", PointerOp.UPDATE, target=T1)
        with pytest.raises(PointerFinalError):
            client.pointer_transfer("final", B)


class TestTypedStatusError:
    @pytest.mark.parametrize("code, tag, exc", [
        (grpc.StatusCode.FAILED_PRECONDITION, "POINTER_FINAL", PointerFinalError),
        (grpc.StatusCode.FAILED_PRECONDITION, "POINTER_FORKED", PointerForkedError),
        (grpc.StatusCode.ABORTED, "CONFLICT", ConflictError),
        (grpc.StatusCode.UNAVAILABLE, "CLOSE_GROUP_SHORTFALL", CloseGroupShortfallError),
    ])
    def test_agreeing_tags_map(self, code, tag, exc):
        assert type(_typed_status_error(code, "x", tag)) is exc

    @pytest.mark.parametrize("code, tag", [
        (grpc.StatusCode.FAILED_PRECONDITION, None),
        (grpc.StatusCode.ABORTED, "POINTER_FINAL"),
        (grpc.StatusCode.UNAVAILABLE, "CONFLICT"),
        (grpc.StatusCode.FAILED_PRECONDITION, "CLOSE_GROUP_SHORTFALL"),
        (grpc.StatusCode.INTERNAL, "POINTER_FORKED"),
        (grpc.StatusCode.ABORTED, "PARTIAL_UPLOAD"),
        (grpc.StatusCode.ALREADY_EXISTS, "ALREADY_EXISTS"),
    ])
    def test_untagged_or_disagreeing_tags_do_not(self, code, tag):
        assert _typed_status_error(code, "x", tag) is None

    def test_retryable_comes_from_the_closing_hint(self):
        e = _typed_status_error(grpc.StatusCode.UNAVAILABLE, _RETAINED, "CLOSE_GROUP_SHORTFALL")
        assert isinstance(e, CloseGroupShortfallError) and e.retryable is True
        e = _typed_status_error(
            grpc.StatusCode.UNAVAILABLE, "reason (paid attempt retained) then more", "CLOSE_GROUP_SHORTFALL")
        assert isinstance(e, CloseGroupShortfallError) and e.retryable is False


# --- Async client ----------------------------------------------------------------


@pytest.mark.asyncio
class TestAsync:
    async def test_every_method(self, aclient, servicer):
        assert await aclient.pointer_keys() == [A, B]
        assert (await aclient.pointer_create(A, T1)).counter == 0
        assert (await aclient.pointer_update(A, B, "pointer")).counter == 1
        assert servicer.requests[-1][1].kind == "pointer"
        assert (await aclient.pointer_transfer(A, B)).finality.is_final
        r = await aclient.pointer_get(A)
        assert (r.counter, r.transferred_to) == (POINTER_FINAL_COUNTER, B)
        assert (await aclient.pointer_resolve(A)).target == T2
        assert (await aclient.pointer_finality("open")).counter == 1
        assert (await aclient.pointer_controller(A)).pointer == B
        p = await aclient.pointer_prepare(A, PointerOp.TRANSFER, recipient=B)
        assert (servicer.requests[-1][1].op, servicer.requests[-1][1].recipient) == ("transfer", B)
        assert p.counter == 4
        assert (await aclient.pointer_finalize("transfer", {"0xq1": "0xtx1"})).finality.is_final

    @pytest.mark.parametrize("owner, exc", [
        ("final", PointerFinalError),
        ("forked", PointerForkedError),
        ("conflict", ConflictError),
        ("shortfall", CloseGroupShortfallError),
        ("payment", PaymentError),
        ("aborted", ForkError),
        ("final-on-unavailable", NetworkError),
    ])
    async def test_errors_map_by_the_daemon_tag(self, aclient, owner, exc):
        with pytest.raises(exc) as exc_info:
            await aclient.pointer_update(owner, T1)
        assert type(exc_info.value) is exc

    async def test_retained_finalize_shortfall_is_retryable(self, aclient):
        with pytest.raises(CloseGroupShortfallError) as exc_info:
            await aclient.pointer_finalize("retained", {})
        assert exc_info.value.retryable is True

    async def test_malformed_counter_is_an_error(self, aclient):
        with pytest.raises(InternalError):
            await aclient.pointer_get("bad-counter")
