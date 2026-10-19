"""Pointer API over REST: RestClient and AsyncRestClient against a local mock
daemon, plus the body-code error mapping. Mirrors the antd-go / antd-rust
pointer suites."""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest
import pytest_asyncio

from antd import (
    POINTER_FINAL_COUNTER,
    AlreadyExistsError,
    CloseGroupShortfallError,
    ConflictError,
    ForkError,
    InternalError,
    NotFoundError,
    PointerFinalError,
    PointerFinalityStatus,
    PointerForkedError,
    PointerKind,
    PointerOp,
)
from antd._rest import AsyncRestClient, RestClient
from antd.exceptions import (
    BadRequestError,
    ServiceUnavailableError,
    error_for_code,
    has_retained_attempt_hint,
    raise_for_http_error,
)

A = "aa" * 32
B = "bb" * 32
T1 = "11" * 32
T2 = "22" * 32
STATE = "cc" * 32
OWNER_KEY = "ab" * 1952
U64_MAX = str(2**64 - 1)

_RETAINED = (
    "Close group shortfall: stored on 4 of 7 (paid attempt retained: call finalize "
    "again with the same upload_id to store it against the same payment)"
)


def _record(counter: str = "3", **overrides) -> dict:
    record = {
        "address": A,
        "owner": OWNER_KEY,
        "counter": counter,
        "kind": "chunk",
        "kind_tag": 0,
        "target": T1,
        "state_id": STATE,
        "is_final": False,
        "transferred_to": None,
    }
    record.update(overrides)
    return record


def _final_state(target: str, holders: int, transferred_to: str | None = None) -> dict:
    return {
        "state_id": STATE,
        "kind": "pointer",
        "kind_tag": 1,
        "target": target,
        "holders": holders,
        "transferred_to": transferred_to,
    }


def _finality(status: str = "final", **overrides) -> dict:
    body = {
        "address": A,
        "group": 7,
        "answered": 7,
        "status": status,
        "counter": None,
        "state": _final_state(B, 7, B),
        "states": [],
        "majority": None,
        "transferred_to": B,
    }
    body.update(overrides)
    return body


class _Handler(BaseHTTPRequestHandler):
    """Answers each (method, path) from the server's route table and records
    every request, so tests can assert on exactly what was sent."""

    def log_message(self, format, *args):
        pass

    def _respond(self, method: str) -> None:
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        body = json.loads(raw) if raw else None
        self.server.requests.append((method, self.path, body))
        status, payload = self.server.routes.get(
            (method, self.path), (404, {"error": f"no route {method} {self.path}", "code": "NOT_FOUND"}),
        )
        data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802
        self._respond("GET")

    def do_POST(self):  # noqa: N802
        self._respond("POST")


class _Daemon:
    def __init__(self, server: HTTPServer):
        self.server = server
        host, port = server.server_address
        self.url = f"http://{host}:{port}"

    def route(self, method: str, path: str, status: int, body) -> None:
        self.server.routes[(method, path)] = (status, body)

    @property
    def requests(self) -> list:
        return self.server.requests

    @property
    def last_body(self):
        return self.server.requests[-1][2]


@pytest.fixture
def daemon():
    server = HTTPServer(("127.0.0.1", 0), _Handler)
    server.routes = {}
    server.requests = []
    # A short poll keeps shutdown(), once per test, from waiting 0.5 s.
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
    thread.start()
    yield _Daemon(server)
    server.shutdown()
    server.server_close()


@pytest.fixture
def client(daemon):
    c = RestClient(base_url=daemon.url, timeout=5.0)
    yield c
    c.close()


@pytest_asyncio.fixture
async def aclient(daemon):
    c = AsyncRestClient(base_url=daemon.url, timeout=5.0)
    yield c
    await c.close()


# --- Methods -----------------------------------------------------------------


class TestKeys:
    def test_lists_addresses(self, daemon, client):
        daemon.route("GET", "/v1/pointers/keys", 200, {"keys": [{"address": A}, {"address": B}]})
        assert client.pointer_keys() == [A, B]

    def test_none_loaded(self, daemon, client):
        daemon.route("GET", "/v1/pointers/keys", 200, {"keys": []})
        assert client.pointer_keys() == []


class TestWrites:
    def test_create_sends_owner_target_kind_and_parses_the_counter(self, daemon, client):
        daemon.route("POST", "/v1/pointers", 200, {"address": A, "state_id": STATE, "counter": "0"})
        w = client.pointer_create(A, T1)
        assert daemon.last_body == {"owner": A, "target": T1, "kind": "chunk"}
        assert (w.address, w.state_id, w.counter) == (A, STATE, 0)

    @pytest.mark.parametrize("kind", [PointerKind.POINTER, "pointer"])
    def test_update_forwarding_sends_kind_pointer(self, daemon, client, kind):
        daemon.route("POST", "/v1/pointers/update", 200, {"address": A, "state_id": STATE, "counter": "1"})
        w = client.pointer_update(A, B, kind)
        assert daemon.last_body == {"owner": A, "target": B, "kind": "pointer"}
        assert w.counter == 1

    def test_update_counter_up_to_u64_max(self, daemon, client):
        daemon.route("POST", "/v1/pointers/update", 200, {"address": A, "state_id": STATE, "counter": U64_MAX})
        assert client.pointer_update(A, T2).counter == POINTER_FINAL_COUNTER == 2**64 - 1

    def test_create_of_an_existing_pointer_is_already_exists(self, daemon, client):
        daemon.route("POST", "/v1/pointers", 409, {"error": "Already exists: pointer", "code": "ALREADY_EXISTS"})
        with pytest.raises(AlreadyExistsError):
            client.pointer_create(A, T1)

    def test_a_paid_write_is_never_retried(self, daemon, client):
        # A shortfall on a daemon-wallet write is raised as is: one request,
        # no second payment.
        daemon.route("POST", "/v1/pointers/update", 503, {
            "error": "Close group shortfall: stored on 3 of 7", "code": "CLOSE_GROUP_SHORTFALL",
        })
        with pytest.raises(CloseGroupShortfallError) as exc_info:
            client.pointer_update(A, T2)
        assert exc_info.value.retryable is False
        assert len(daemon.requests) == 1

    def test_transfer_with_a_finality_check(self, daemon, client):
        daemon.route("POST", "/v1/pointers/transfer", 200, {
            "address": A, "state_id": STATE, "finality": _finality(),
        })
        t = client.pointer_transfer(A, B)
        assert daemon.last_body == {"owner": A, "recipient": B}
        assert (t.address, t.state_id, t.finality_error) == (A, STATE, None)
        assert t.finality is not None and t.finality.is_final
        assert t.finality.transferred_to == B

    def test_transfer_whose_finality_check_failed(self, daemon, client):
        daemon.route("POST", "/v1/pointers/transfer", 200, {
            "address": A, "state_id": STATE, "finality": None, "finality_error": "only 5 of 7 answered",
        })
        t = client.pointer_transfer(A, B)
        assert t.finality is None
        assert t.finality_error == "only 5 of 7 answered"


class TestReads:
    def test_get_final_record_reads_u64_max_and_the_transfer(self, daemon, client):
        daemon.route("GET", f"/v1/pointers/{A}", 200, _record(
            counter=U64_MAX, is_final=True, transferred_to=B, kind="pointer", kind_tag=1, target=B,
        ))
        r = client.pointer_get(A)
        assert r.counter == POINTER_FINAL_COUNTER
        assert r.is_final is True
        assert r.transferred_to == B
        assert (r.kind, r.kind_tag, r.target_kind) == ("pointer", 1, PointerKind.POINTER)
        assert r.owner == OWNER_KEY

    @pytest.mark.parametrize("transferred_to", [None, ""])
    def test_get_open_record_has_no_transfer(self, daemon, client, transferred_to):
        daemon.route("GET", f"/v1/pointers/{A}", 200, _record(transferred_to=transferred_to))
        r = client.pointer_get(A)
        assert (r.counter, r.is_final, r.transferred_to) == (3, False, None)
        assert r.target_kind is PointerKind.CHUNK

    def test_unknown_kind_keeps_its_tag(self, daemon, client):
        daemon.route("GET", f"/v1/pointers/{A}", 200, _record(kind="unknown", kind_tag=42))
        r = client.pointer_get(A)
        assert (r.kind, r.kind_tag, r.target_kind) == ("unknown", 42, None)

    def test_get_missing_is_not_found(self, daemon, client):
        daemon.route("GET", f"/v1/pointers/{A}", 404, {"error": "no pointer", "code": "NOT_FOUND"})
        with pytest.raises(NotFoundError):
            client.pointer_get(A)

    def test_resolve(self, daemon, client):
        daemon.route("GET", f"/v1/pointers/{A}/resolve", 200, {"kind": "chunk", "kind_tag": 0, "target": T2})
        t = client.pointer_resolve(A)
        assert (t.kind, t.kind_tag, t.target, t.target_kind) == ("chunk", 0, T2, PointerKind.CHUNK)

    def test_controller(self, daemon, client):
        daemon.route("GET", f"/v1/pointers/{A}/controller", 200, {"pointer": B, "transfers": [B], "frozen": False})
        c = client.pointer_controller(A)
        assert (c.pointer, c.transfers, c.frozen) == (B, [B], False)

    def test_finality_open(self, daemon, client):
        daemon.route("GET", f"/v1/pointers/{A}/finality", 200, _finality(
            "open", counter="1", state=None, transferred_to=None,
        ))
        f = client.pointer_finality(A)
        assert f.status is PointerFinalityStatus.OPEN and f.raw_status == "open"
        assert f.counter == 1
        assert (f.state, f.states, f.majority, f.transferred_to) == (None, [], None, None)
        assert not f.is_final

    @pytest.mark.parametrize("counter", [None, ""])
    def test_finality_open_without_a_corroborated_counter(self, daemon, client, counter):
        daemon.route("GET", f"/v1/pointers/{A}/finality", 200, _finality(
            "open", counter=counter, state=None, transferred_to=None,
        ))
        assert client.pointer_finality(A).counter is None

    def test_finality_final(self, daemon, client):
        daemon.route("GET", f"/v1/pointers/{A}/finality", 200, _finality())
        f = client.pointer_finality(A)
        assert f.is_final and f.status is PointerFinalityStatus.FINAL
        assert (f.group, f.answered, f.counter) == (7, 7, None)
        assert f.state is not None
        assert (f.state.target, f.state.holders, f.state.transferred_to) == (B, 7, B)
        assert f.transferred_to == B

    def test_finality_forked(self, daemon, client):
        rivals = [_final_state(T1, 4), _final_state(T2, 2)]
        daemon.route("GET", f"/v1/pointers/{A}/finality", 200, _finality(
            "forked", state=None, states=rivals, majority=rivals[0], transferred_to=None,
        ))
        f = client.pointer_finality(A)
        assert f.status is PointerFinalityStatus.FORKED
        assert [(s.target, s.holders) for s in f.states] == [(T1, 4), (T2, 2)]
        assert f.majority is not None and f.majority.target == T1
        assert f.state is None and f.transferred_to is None

    def test_finality_unknown_status_is_kept(self, daemon, client):
        daemon.route("GET", f"/v1/pointers/{A}/finality", 200, _finality(
            "contested", state=None, transferred_to=None,
        ))
        f = client.pointer_finality(A)
        assert f.status is PointerFinalityStatus.UNKNOWN
        assert f.raw_status == "contested"
        assert not f.is_final

    @pytest.mark.parametrize("status", ["settling", "unconfirmed"])
    def test_finality_one_final_state_not_yet_final(self, daemon, client, status):
        daemon.route("GET", f"/v1/pointers/{A}/finality", 200, _finality(status, transferred_to=None))
        f = client.pointer_finality(A)
        assert f.status.value == status and f.raw_status == status
        assert f.state is not None and not f.is_final


class TestCounters:
    @pytest.mark.parametrize("counter, expected", [
        ("0", 0),
        ("7", 7),
        ("007", 7),
        (U64_MAX, 2**64 - 1),
        ("0" * 30 + "5", 5),
    ])
    def test_decimal_strings(self, daemon, client, counter, expected):
        daemon.route("GET", f"/v1/pointers/{A}", 200, _record(counter=counter))
        assert client.pointer_get(A).counter == expected

    @pytest.mark.parametrize("counter", [
        "", "+1", "-1", " 1", "1 ", "1\n", "1_000", "0x10", "1.0", "1e3", "abc",
        "١",  # ARABIC-INDIC DIGIT ONE: int() would take it
        "18446744073709551616",  # u64::MAX + 1
        "9" * 5000,  # past int()'s digit limit
        5, 1.0, True, None, [], {},
    ])
    def test_anything_else_is_an_error_not_a_zero(self, daemon, client, counter):
        daemon.route("GET", f"/v1/pointers/{A}", 200, _record(counter=counter))
        with pytest.raises(InternalError, match="counter"):
            client.pointer_get(A)

    def test_missing_counter_is_an_error(self, daemon, client):
        record = _record()
        del record["counter"]
        daemon.route("GET", f"/v1/pointers/{A}", 200, record)
        with pytest.raises(InternalError):
            client.pointer_get(A)

    def test_malformed_finality_counter_is_an_error(self, daemon, client):
        daemon.route("GET", f"/v1/pointers/{A}/finality", 200, _finality("open", counter="-1"))
        with pytest.raises(InternalError):
            client.pointer_finality(A)

    def test_non_object_body_is_an_error(self, daemon, client):
        daemon.route("POST", "/v1/pointers", 200, b"[1, 2]")
        with pytest.raises(InternalError):
            client.pointer_create(A, T1)


_PREPARED = {
    "upload_id": "up-1",
    "op": "update",
    "address": A,
    "state_id": STATE,
    "counter": "4",
    "payment_type": "wave_batch",
    "payments": [{"quote_hash": "0xq1", "rewards_address": "0xr1", "amount": "123"}],
    "total_amount": "123",
    "payment_vault_address": "0xvault",
    "payment_token_address": "0xtoken",
    "rpc_url": "http://127.0.0.1:8545",
}


class TestExternalSigner:
    @pytest.mark.parametrize("call, body", [
        (lambda c: c.pointer_prepare(A, PointerOp.CREATE, target=T1),
         {"owner": A, "op": "create", "target": T1}),
        (lambda c: c.pointer_prepare(A, "update", target=B, kind=PointerKind.POINTER),
         {"owner": A, "op": "update", "target": B, "kind": "pointer"}),
        (lambda c: c.pointer_prepare(A, PointerOp.TRANSFER, recipient=B),
         {"owner": A, "op": "transfer", "recipient": B}),
        (lambda c: c.pointer_prepare(A, PointerOp.UPDATE, target=T2, include_signed_quotes=True),
         {"owner": A, "op": "update", "target": T2, "include_signed_quotes": True}),
    ])
    def test_prepare_sends_each_op_shape(self, daemon, client, call, body):
        daemon.route("POST", "/v1/pointers/prepare", 200, _PREPARED)
        call(client)
        assert daemon.last_body == body

    def test_prepare_result(self, daemon, client):
        daemon.route("POST", "/v1/pointers/prepare", 200, _PREPARED)
        p = client.pointer_prepare(A, PointerOp.UPDATE, target=T2)
        assert (p.upload_id, p.op, p.address, p.state_id, p.counter) == ("up-1", "update", A, STATE, 4)
        assert p.payment_type == "wave_batch"
        assert [(x.quote_hash, x.rewards_address, x.amount) for x in p.payments] == [("0xq1", "0xr1", "123")]
        assert (p.total_amount, p.payment_vault_address, p.payment_token_address, p.rpc_url) == (
            "123", "0xvault", "0xtoken", "http://127.0.0.1:8545")
        assert p.signed_quotes == []

    def test_prepare_with_signed_quotes(self, daemon, client):
        daemon.route("POST", "/v1/pointers/prepare", 200, {**_PREPARED, "signed_quotes": [
            {"quote_hash": "0xq1", "quote": "cXVvdGU=", "commitment_sidecar": "c2lkZQ=="},
            {"quote_hash": "0xq2", "quote": "cTI="},
        ]})
        p = client.pointer_prepare(A, PointerOp.UPDATE, target=T2, include_signed_quotes=True)
        assert [(q.quote_hash, q.quote, q.commitment_sidecar) for q in p.signed_quotes] == [
            ("0xq1", "cXVvdGU=", "c2lkZQ=="), ("0xq2", "cTI=", None)]

    def test_prepare_while_one_is_pending_is_a_conflict(self, daemon, client):
        daemon.route("POST", "/v1/pointers/prepare", 409, {"error": "Conflict: pending", "code": "CONFLICT"})
        with pytest.raises(ConflictError):
            client.pointer_prepare(A, PointerOp.UPDATE, target=T2)

    def test_finalize_sends_hashes_and_reads_a_transfer_finality(self, daemon, client):
        daemon.route("POST", "/v1/pointers/finalize", 200, {
            "address": A, "state_id": STATE, "counter": U64_MAX, "finality": _finality(),
        })
        r = client.pointer_finalize("up-1", {"0xq1": "0xtx1"})
        assert daemon.last_body == {"upload_id": "up-1", "tx_hashes": {"0xq1": "0xtx1"}}
        assert (r.address, r.state_id, r.counter) == (A, STATE, POINTER_FINAL_COUNTER)
        assert r.finality is not None and r.finality.is_final

    def test_finalize_of_a_create_has_no_finality(self, daemon, client):
        daemon.route("POST", "/v1/pointers/finalize", 200, {"address": A, "state_id": STATE, "counter": "0"})
        r = client.pointer_finalize("up-1", {"0xq1": "0xtx1"})
        assert (r.counter, r.finality) == (0, None)

    def test_finalize_retained_shortfall_is_retryable(self, daemon, client):
        daemon.route("POST", "/v1/pointers/finalize", 503, {
            "error": _RETAINED, "code": "CLOSE_GROUP_SHORTFALL", "retryable": True,
        })
        with pytest.raises(CloseGroupShortfallError) as exc_info:
            client.pointer_finalize("up-1", {"0xq1": "0xtx1"})
        err = exc_info.value
        assert err.retryable is True
        assert err.status_code == 503
        assert len(daemon.requests) == 1  # the SDK never repeats it by itself

    def test_finalize_without_hashes_is_a_bad_request(self, daemon, client):
        daemon.route("POST", "/v1/pointers/finalize", 400, {"error": "cannot build payment proof", "code": "BAD_REQUEST"})
        with pytest.raises(BadRequestError):
            client.pointer_finalize("up-1", {})


# --- Error mapping -------------------------------------------------------------


class TestErrorCodes:
    @pytest.mark.parametrize("code, exc", [
        ("POINTER_FINAL", PointerFinalError),
        ("POINTER_FORKED", PointerForkedError),
        ("CONFLICT", ConflictError),
        ("ALREADY_EXISTS", AlreadyExistsError),
        (None, AlreadyExistsError),
    ])
    def test_409s_map_by_code_not_status(self, code, exc):
        body = {"error": "x"} if code is None else {"error": "x", "code": code}
        with pytest.raises(exc) as exc_info:
            raise_for_http_error(409, "x", body)
        assert exc_info.value.status_code == 409
        assert type(exc_info.value) is exc

    def test_pointer_refusals_are_not_already_exists(self):
        for exc in (PointerFinalError, PointerForkedError, ConflictError):
            assert not issubclass(exc, AlreadyExistsError)

    def test_pointer_forked_is_a_fork_error(self):
        assert issubclass(PointerForkedError, ForkError)
        assert not issubclass(ConflictError, ForkError)

    @pytest.mark.parametrize("retryable, expected", [
        (True, True), (False, False), ("true", False), (1, False), (None, False), ("absent", False),
    ])
    def test_shortfall_retryable_only_for_json_true(self, retryable, expected):
        body = {"error": "x", "code": "CLOSE_GROUP_SHORTFALL"}
        if retryable != "absent":
            body["retryable"] = retryable
        with pytest.raises(CloseGroupShortfallError) as exc_info:
            raise_for_http_error(503, "x", body)
        assert exc_info.value.retryable is expected
        assert exc_info.value.status_code == 503

    def test_shortfall_is_not_service_unavailable(self):
        with pytest.raises(CloseGroupShortfallError) as exc_info:
            raise_for_http_error(503, "x", {"error": "x", "code": "CLOSE_GROUP_SHORTFALL"})
        assert not isinstance(exc_info.value, ServiceUnavailableError)
        # Any other 503 keeps the status mapping.
        with pytest.raises(ServiceUnavailableError):
            raise_for_http_error(503, "no wallet", {"error": "no wallet", "code": "SERVICE_UNAVAILABLE"})

    def test_non_string_code_keeps_the_status_mapping(self):
        with pytest.raises(AlreadyExistsError):
            raise_for_http_error(409, "x", {"error": "x", "code": ["POINTER_FINAL"]})

    def test_error_for_code_unknown_is_none(self):
        assert error_for_code("NOT_A_CODE", "x") is None
        assert error_for_code("PARTIAL_UPLOAD", "x") is None

    @pytest.mark.parametrize("message, expected", [
        (_RETAINED, True),
        ("Close group shortfall: only 3 answered", False),
        ("Close group shortfall: x (paid attempt retai", False),
        ("x (paid attempt retained: y) and more", False),
        (None, False),
    ])
    def test_retained_hint_must_close_the_message(self, message, expected):
        assert has_retained_attempt_hint(message) is expected


# --- Async client ----------------------------------------------------------------


@pytest.mark.asyncio
class TestAsync:
    async def test_every_method(self, daemon, aclient):
        daemon.route("GET", "/v1/pointers/keys", 200, {"keys": [{"address": A}]})
        daemon.route("POST", "/v1/pointers", 200, {"address": A, "state_id": STATE, "counter": "0"})
        daemon.route("POST", "/v1/pointers/update", 200, {"address": A, "state_id": STATE, "counter": "1"})
        daemon.route("POST", "/v1/pointers/transfer", 200, {"address": A, "state_id": STATE, "finality": _finality()})
        daemon.route("GET", f"/v1/pointers/{A}", 200, _record(counter=U64_MAX, is_final=True, transferred_to=B))
        daemon.route("GET", f"/v1/pointers/{A}/resolve", 200, {"kind": "chunk", "kind_tag": 0, "target": T1})
        daemon.route("GET", f"/v1/pointers/{A}/finality", 200, _finality())
        daemon.route("GET", f"/v1/pointers/{A}/controller", 200, {"pointer": B, "transfers": [B], "frozen": False})
        daemon.route("POST", "/v1/pointers/prepare", 200, _PREPARED)
        daemon.route("POST", "/v1/pointers/finalize", 200, {"address": A, "state_id": STATE, "counter": "4"})

        assert await aclient.pointer_keys() == [A]
        assert (await aclient.pointer_create(A, T1)).counter == 0
        assert (await aclient.pointer_update(A, B, PointerKind.POINTER)).counter == 1
        assert daemon.last_body == {"owner": A, "target": B, "kind": "pointer"}
        assert (await aclient.pointer_transfer(A, B)).finality.is_final
        r = await aclient.pointer_get(A)
        assert (r.counter, r.transferred_to) == (POINTER_FINAL_COUNTER, B)
        assert (await aclient.pointer_resolve(A)).target == T1
        assert (await aclient.pointer_finality(A)).status is PointerFinalityStatus.FINAL
        assert (await aclient.pointer_controller(A)).transfers == [B]
        p = await aclient.pointer_prepare(A, PointerOp.TRANSFER, recipient=B)
        assert daemon.last_body == {"owner": A, "op": "transfer", "recipient": B}
        assert p.counter == 4
        assert (await aclient.pointer_finalize("up-1", {"0xq1": "0xtx1"})).counter == 4

    async def test_errors_map_by_code(self, daemon, aclient):
        daemon.route("POST", "/v1/pointers/update", 409, {"error": "Pointer is final: x", "code": "POINTER_FINAL"})
        with pytest.raises(PointerFinalError):
            await aclient.pointer_update(A, T1)
        daemon.route("POST", "/v1/pointers/finalize", 503, {
            "error": _RETAINED, "code": "CLOSE_GROUP_SHORTFALL", "retryable": True,
        })
        with pytest.raises(CloseGroupShortfallError) as exc_info:
            await aclient.pointer_finalize("up-1", {})
        assert exc_info.value.retryable is True

    async def test_malformed_counter_is_an_error(self, daemon, aclient):
        daemon.route("GET", f"/v1/pointers/{A}", 200, _record(counter="1_000"))
        with pytest.raises(InternalError):
            await aclient.pointer_get(A)
