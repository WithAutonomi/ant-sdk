"""Unit tests for the antd-mcp pointer tools.

Same approach as ``test_server.py``: the tool coroutines run directly, with
``server._get_ctx`` monkeypatched to hand them a mocked client (or, where the
SDK's own parsing matters, a real ``AsyncRestClient`` over an
``httpx.MockTransport``).
"""

from __future__ import annotations

import asyncio
import functools
import json
from unittest.mock import AsyncMock

import httpx
import pytest

from antd import (
    POINTER_FINAL_COUNTER,
    PointerController,
    PointerFinality,
    PointerFinalityStatus,
    PointerFinalizeResult,
    PointerFinalState,
    PointerKind,
    PointerOp,
    PointerPrepareResult,
    PointerRecord,
    PointerTarget,
    PointerTransferResult,
    PointerWriteResult,
)
from antd._rest import AsyncRestClient
from antd.exceptions import (
    AlreadyExistsError,
    CloseGroupShortfallError,
    ConflictError,
    ForkError,
    PointerFinalError,
    PointerForkedError,
)
from antd.models import PaymentInfo
from antd_mcp import server

OWNER = "aa" * 32
RECIPIENT = "bb" * 32
TARGET_1 = "c1" * 32
TARGET_2 = "c2" * 32
STATE_ID = "d0" * 32
FINAL = str(POINTER_FINAL_COUNTER)  # "18446744073709551615"

POINTER_TOOLS = {
    "pointer_keys",
    "pointer_get",
    "pointer_resolve",
    "pointer_finality",
    "pointer_controller",
    "pointer_create",
    "pointer_update",
    "pointer_transfer",
    "pointer_prepare",
    "pointer_finalize",
}


def _tool_fn(tool):
    """See ``test_server._tool_fn``: bind the server-injected ``ctx`` to None."""
    fn = tool if callable(tool) else getattr(tool, "fn", None)
    if fn is None:
        raise AssertionError(f"Cannot extract coroutine function from MCP tool {tool!r}")
    return functools.partial(fn, ctx=None)


@pytest.fixture
def mock_client(monkeypatch):
    client = AsyncMock()
    monkeypatch.setattr(server, "_get_ctx", lambda ctx: (client, "test-net"))
    return client


async def _call(name: str, **kwargs) -> dict:
    return json.loads(await _tool_fn(getattr(server, name))(**kwargs))


def _final_state(**overrides) -> PointerFinalState:
    fields = dict(
        state_id=STATE_ID, kind="pointer", kind_tag=1, target=RECIPIENT,
        holders=7, transferred_to=RECIPIENT,
    )
    fields.update(overrides)
    return PointerFinalState(**fields)


def _final_finality() -> PointerFinality:
    return PointerFinality(
        address=OWNER, group=7, answered=7,
        status=PointerFinalityStatus.FINAL, raw_status="final",
        state=_final_state(), transferred_to=RECIPIENT,
    )


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------


def test_pointer_tools_are_registered():
    tools = asyncio.run(server.mcp.list_tools())
    names = {t.name for t in tools}
    assert server.POINTERS_AVAILABLE is True
    assert POINTER_TOOLS <= names
    assert len(tools) == 29


def test_transfer_is_annotated_destructive_and_says_irreversible():
    tools = {t.name: t for t in asyncio.run(server.mcp.list_tools())}
    transfer = tools["pointer_transfer"]
    assert transfer.annotations is not None
    assert transfer.annotations.destructive_hint is True
    assert transfer.annotations.idempotent_hint is False
    assert transfer.description.startswith("IRREVERSIBLE")
    assert "confirm_irreversible" in transfer.input_schema["properties"]
    # Optional in the schema, so a call without it reaches the refusal.
    assert "confirm_irreversible" not in transfer.input_schema.get("required", [])


def test_write_tool_descriptions_say_they_pay():
    tools = {t.name: t for t in asyncio.run(server.mcp.list_tools())}
    for name in ("pointer_create", "pointer_update", "pointer_transfer"):
        assert "Pays from the daemon wallet" in tools[name].description, name
        assert "never retr" in tools[name].description, name
    for name in ("pointer_keys", "pointer_get", "pointer_resolve", "pointer_finality",
                 "pointer_controller"):
        assert "Free." in tools[name].description, name


# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_pointer_keys(mock_client):
    mock_client.pointer_keys.return_value = [OWNER, RECIPIENT]

    payload = await _call("pointer_keys")

    mock_client.pointer_keys.assert_awaited_once_with()
    assert payload == {"keys": [OWNER, RECIPIENT], "network": "test-net"}


@pytest.mark.asyncio
async def test_pointer_get_counter_is_a_decimal_string_and_owner_key_left_out(mock_client):
    mock_client.pointer_get.return_value = PointerRecord(
        address=OWNER, owner="ab" * 1952, counter=POINTER_FINAL_COUNTER, kind="pointer",
        kind_tag=1, target=RECIPIENT, state_id=STATE_ID, is_final=True,
        transferred_to=RECIPIENT,
    )

    payload = await _call("pointer_get", address=OWNER)

    mock_client.pointer_get.assert_awaited_once_with(OWNER)
    assert payload == {
        "address": OWNER,
        "counter": FINAL,
        "target": RECIPIENT,
        "kind": "pointer",
        "kind_tag": 1,
        "state_id": STATE_ID,
        "is_final": True,
        "transferred_to": RECIPIENT,
        "network": "test-net",
    }


@pytest.mark.asyncio
async def test_pointer_get_include_owner_key(mock_client):
    mock_client.pointer_get.return_value = PointerRecord(
        address=OWNER, owner="ab" * 1952, counter=3, kind="chunk", kind_tag=0,
        target=TARGET_1, state_id=STATE_ID, is_final=False,
    )

    payload = await _call("pointer_get", address=OWNER, include_owner_key=True)

    assert payload["owner"] == "ab" * 1952
    assert payload["counter"] == "3"
    assert payload["transferred_to"] is None
    assert payload["is_final"] is False


@pytest.mark.asyncio
async def test_pointer_resolve(mock_client):
    mock_client.pointer_resolve.return_value = PointerTarget(
        kind="chunk", kind_tag=0, target=TARGET_2,
    )

    payload = await _call("pointer_resolve", address=OWNER)

    mock_client.pointer_resolve.assert_awaited_once_with(OWNER)
    assert payload == {"target": TARGET_2, "kind": "chunk", "kind_tag": 0, "network": "test-net"}


@pytest.mark.asyncio
async def test_pointer_finality_open_counter_is_a_string(mock_client):
    mock_client.pointer_finality.return_value = PointerFinality(
        address=OWNER, group=7, answered=6, status=PointerFinalityStatus.OPEN,
        raw_status="open", counter=1,
    )

    payload = await _call("pointer_finality", address=OWNER)

    mock_client.pointer_finality.assert_awaited_once_with(OWNER)
    assert payload == {
        "address": OWNER,
        "status": "open",
        "raw_status": "open",
        "is_final": False,
        "group": 7,
        "answered": 6,
        "counter": "1",
        "state": None,
        "states": [],
        "majority": None,
        "transferred_to": None,
        "network": "test-net",
    }


@pytest.mark.asyncio
async def test_pointer_finality_final(mock_client):
    mock_client.pointer_finality.return_value = _final_finality()

    payload = await _call("pointer_finality", address=OWNER)

    assert payload["status"] == "final"
    assert payload["is_final"] is True
    assert payload["counter"] is None
    assert payload["transferred_to"] == RECIPIENT
    assert payload["state"] == {
        "state_id": STATE_ID,
        "kind": "pointer",
        "kind_tag": 1,
        "target": RECIPIENT,
        "holders": 7,
        "transferred_to": RECIPIENT,
    }


@pytest.mark.asyncio
async def test_pointer_finality_forked_lists_states_and_majority(mock_client):
    a = _final_state(state_id="01" * 32, holders=4)
    b = _final_state(state_id="02" * 32, holders=3, transferred_to=None, kind="chunk",
                     kind_tag=0, target=TARGET_1)
    mock_client.pointer_finality.return_value = PointerFinality(
        address=OWNER, group=7, answered=7, status=PointerFinalityStatus.FORKED,
        raw_status="forked", states=[a, b], majority=a,
    )

    payload = await _call("pointer_finality", address=OWNER)

    assert payload["status"] == "forked"
    assert [s["state_id"] for s in payload["states"]] == ["01" * 32, "02" * 32]
    assert payload["states"][1]["transferred_to"] is None
    assert payload["majority"]["state_id"] == "01" * 32


@pytest.mark.asyncio
async def test_pointer_finality_unknown_status_keeps_raw(mock_client):
    mock_client.pointer_finality.return_value = PointerFinality(
        address=OWNER, group=7, answered=7, status=PointerFinalityStatus.UNKNOWN,
        raw_status="quantum",
    )

    payload = await _call("pointer_finality", address=OWNER)

    assert payload["status"] == "unknown"
    assert payload["raw_status"] == "quantum"
    assert payload["is_final"] is False


@pytest.mark.asyncio
async def test_pointer_controller(mock_client):
    mock_client.pointer_controller.return_value = PointerController(
        pointer=RECIPIENT, transfers=[RECIPIENT], frozen=False,
    )

    payload = await _call("pointer_controller", address=OWNER)

    mock_client.pointer_controller.assert_awaited_once_with(OWNER)
    assert payload == {
        "pointer": RECIPIENT,
        "transfers": [RECIPIENT],
        "frozen": False,
        "network": "test-net",
    }


# ---------------------------------------------------------------------------
# Daemon-wallet writes
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
@pytest.mark.parametrize("tool", ["pointer_create", "pointer_update"])
@pytest.mark.parametrize(
    "kind_arg, kind",
    [(None, PointerKind.CHUNK), ("chunk", PointerKind.CHUNK), ("pointer", PointerKind.POINTER)],
    ids=["default", "chunk", "pointer"],
)
async def test_pointer_write_forwards_typed_kind(mock_client, tool, kind_arg, kind):
    method = getattr(mock_client, tool)
    method.return_value = PointerWriteResult(address=OWNER, state_id=STATE_ID, counter=1)
    kwargs = {"owner": OWNER, "target": TARGET_1}
    if kind_arg is not None:
        kwargs["kind"] = kind_arg

    payload = await _call(tool, **kwargs)

    method.assert_awaited_once_with(OWNER, TARGET_1, kind)
    assert payload == {
        "address": OWNER,
        "state_id": STATE_ID,
        "counter": "1",
        "network": "test-net",
    }


@pytest.mark.asyncio
@pytest.mark.parametrize("tool", ["pointer_create", "pointer_update"])
async def test_pointer_write_bad_kind_sends_nothing(mock_client, tool):
    payload = await _call(tool, owner=OWNER, target=TARGET_1, kind="file")

    getattr(mock_client, tool).assert_not_awaited()
    assert payload["error"] == "UNEXPECTED"
    assert "file" in payload["message"]


@pytest.mark.asyncio
async def test_pointer_create_already_exists(mock_client):
    mock_client.pointer_create.side_effect = AlreadyExistsError("pointer exists", 409)

    payload = await _call("pointer_create", owner=OWNER, target=TARGET_1)

    assert payload["error"] == "ALREADY_EXISTS"
    assert "hint" not in payload


@pytest.mark.asyncio
@pytest.mark.parametrize("confirm", [None, False], ids=["omitted", "false"])
async def test_pointer_transfer_refuses_without_confirmation(mock_client, confirm):
    kwargs = {"owner": OWNER, "recipient": RECIPIENT}
    if confirm is not None:
        kwargs["confirm_irreversible"] = confirm

    payload = await _call("pointer_transfer", **kwargs)

    mock_client.pointer_transfer.assert_not_awaited()
    assert payload["error"] == "CONFIRMATION_REQUIRED"
    assert OWNER in payload["message"] and RECIPIENT in payload["message"]
    assert "Nothing was sent or paid" in payload["message"]
    assert payload["network"] == "test-net"


@pytest.mark.asyncio
async def test_pointer_transfer_confirmed_returns_finality(mock_client):
    mock_client.pointer_transfer.return_value = PointerTransferResult(
        address=OWNER, state_id=STATE_ID, finality=_final_finality(),
    )

    payload = await _call(
        "pointer_transfer", owner=OWNER, recipient=RECIPIENT, confirm_irreversible=True,
    )

    mock_client.pointer_transfer.assert_awaited_once_with(OWNER, RECIPIENT)
    assert payload["address"] == OWNER
    assert payload["state_id"] == STATE_ID
    assert payload["finality"]["status"] == "final"
    assert payload["finality"]["is_final"] is True
    assert payload["finality_error"] is None


@pytest.mark.asyncio
async def test_pointer_transfer_finality_check_failed(mock_client):
    mock_client.pointer_transfer.return_value = PointerTransferResult(
        address=OWNER, state_id=STATE_ID, finality=None,
        finality_error="only 4 of 7 answered",
    )

    payload = await _call(
        "pointer_transfer", owner=OWNER, recipient=RECIPIENT, confirm_irreversible=True,
    )

    assert payload["finality"] is None
    assert payload["finality_error"] == "only 4 of 7 answered"


# ---------------------------------------------------------------------------
# External signer
# ---------------------------------------------------------------------------


def _prepare_result(op: str = "create") -> PointerPrepareResult:
    return PointerPrepareResult(
        upload_id="ptr-upload-1",
        op=op,
        address=OWNER,
        state_id=STATE_ID,
        counter=0 if op == "create" else POINTER_FINAL_COUNTER,
        payment_type="wave_batch",
        payments=[PaymentInfo(quote_hash="0xq1", rewards_address="0xr1", amount="500")],
        total_amount="500",
        payment_vault_address="0xvault",
        payment_token_address="0xtoken",
        rpc_url="http://rpc.example",
    )


@pytest.mark.asyncio
async def test_pointer_prepare_create(mock_client):
    mock_client.pointer_prepare.return_value = _prepare_result("create")

    payload = await _call("pointer_prepare", owner=OWNER, op="create", target=TARGET_1)

    mock_client.pointer_prepare.assert_awaited_once_with(
        OWNER, PointerOp.CREATE, target=TARGET_1, kind=None, recipient=None,
    )
    assert payload == {
        "upload_id": "ptr-upload-1",
        "op": "create",
        "address": OWNER,
        "state_id": STATE_ID,
        "counter": "0",
        "payment_type": "wave_batch",
        "total_amount": "500",
        "payment_vault_address": "0xvault",
        "payment_token_address": "0xtoken",
        "rpc_url": "http://rpc.example",
        "payments": [{"quote_hash": "0xq1", "rewards_address": "0xr1", "amount": "500"}],
        "network": "test-net",
    }


@pytest.mark.asyncio
async def test_pointer_prepare_update_forwards_kind(mock_client):
    mock_client.pointer_prepare.return_value = _prepare_result("update")

    await _call("pointer_prepare", owner=OWNER, op="update", target=RECIPIENT, kind="pointer")

    mock_client.pointer_prepare.assert_awaited_once_with(
        OWNER, PointerOp.UPDATE, target=RECIPIENT, kind=PointerKind.POINTER, recipient=None,
    )


@pytest.mark.asyncio
async def test_pointer_prepare_transfer_counter_is_final_string(mock_client):
    mock_client.pointer_prepare.return_value = _prepare_result("transfer")

    payload = await _call("pointer_prepare", owner=OWNER, op="transfer", recipient=RECIPIENT)

    mock_client.pointer_prepare.assert_awaited_once_with(
        OWNER, PointerOp.TRANSFER, target=None, kind=None, recipient=RECIPIENT,
    )
    assert payload["counter"] == FINAL


@pytest.mark.asyncio
async def test_pointer_prepare_bad_op_sends_nothing(mock_client):
    payload = await _call("pointer_prepare", owner=OWNER, op="delete")

    mock_client.pointer_prepare.assert_not_awaited()
    assert payload["error"] == "UNEXPECTED"


@pytest.mark.asyncio
async def test_pointer_finalize_update(mock_client):
    mock_client.pointer_finalize.return_value = PointerFinalizeResult(
        address=OWNER, state_id=STATE_ID, counter=2,
    )

    payload = await _call("pointer_finalize", upload_id="ptr-upload-1", tx_hashes={"0xq1": "0xtx1"})

    mock_client.pointer_finalize.assert_awaited_once_with("ptr-upload-1", {"0xq1": "0xtx1"})
    assert payload == {
        "address": OWNER,
        "state_id": STATE_ID,
        "counter": "2",
        "finality": None,
        "network": "test-net",
    }


@pytest.mark.asyncio
async def test_pointer_finalize_transfer_carries_finality(mock_client):
    mock_client.pointer_finalize.return_value = PointerFinalizeResult(
        address=OWNER, state_id=STATE_ID, counter=POINTER_FINAL_COUNTER,
        finality=_final_finality(),
    )

    payload = await _call("pointer_finalize", upload_id="ptr-upload-1", tx_hashes={})

    assert payload["counter"] == FINAL
    assert payload["finality"]["status"] == "final"


# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_pointer_final_error(mock_client):
    mock_client.pointer_update.side_effect = PointerFinalError("Pointer is final: aa..", 409)

    payload = await _call("pointer_update", owner=OWNER, target=TARGET_2)

    assert payload["error"] == "POINTER_FINAL"
    assert payload["status_code"] == 409
    assert "Nothing was paid" in payload["hint"]
    assert "Do not retry" in payload["hint"]
    assert "retryable" not in payload


@pytest.mark.asyncio
async def test_pointer_forked_error_is_not_version_conflict(mock_client):
    mock_client.pointer_get.side_effect = PointerForkedError("Pointer is forked: aa..", 409)

    payload = await _call("pointer_get", address=OWNER)

    assert payload["error"] == "POINTER_FORKED"
    assert "hint" in payload


@pytest.mark.asyncio
async def test_plain_fork_error_keeps_version_conflict(mock_client):
    mock_client.pointer_get.side_effect = ForkError("version conflict", 409)

    payload = await _call("pointer_get", address=OWNER)

    assert payload["error"] == "VERSION_CONFLICT"
    assert "hint" not in payload


@pytest.mark.asyncio
async def test_conflict_error(mock_client):
    mock_client.pointer_create.side_effect = ConflictError("Conflict: pending prepare", 409)

    payload = await _call("pointer_create", owner=OWNER, target=TARGET_1)

    assert payload["error"] == "CONFLICT"
    assert "Nothing was paid" in payload["hint"]


@pytest.mark.asyncio
async def test_close_group_shortfall_retryable_says_retry_the_finalize(mock_client):
    mock_client.pointer_finalize.side_effect = CloseGroupShortfallError(
        "Close group shortfall: 4 of 7 stored (paid attempt retained: call finalize again "
        "with the same upload_id)",
        503,
        retryable=True,
    )

    payload = await _call("pointer_finalize", upload_id="ptr-upload-1", tx_hashes={})

    assert payload["error"] == "CLOSE_GROUP_SHORTFALL"
    assert payload["status_code"] == 503
    assert payload["retryable"] is True
    assert payload["hint"].startswith("Retry the finalize, the payment was kept")
    assert "same upload_id" in payload["hint"]


@pytest.mark.asyncio
async def test_close_group_shortfall_not_retryable(mock_client):
    mock_client.pointer_create.side_effect = CloseGroupShortfallError(
        "Close group shortfall: 3 of 7 answered", 503,
    )

    payload = await _call("pointer_create", owner=OWNER, target=TARGET_1)

    assert payload["error"] == "CLOSE_GROUP_SHORTFALL"
    assert payload["retryable"] is False
    assert "Do not repeat a paid write automatically" in payload["hint"]


# ---------------------------------------------------------------------------
# Through the real REST client: the SDK's parsing and error mapping
# ---------------------------------------------------------------------------


def _real_client(monkeypatch, status: int, body: dict) -> AsyncRestClient:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(status, json=body)

    client = AsyncRestClient(base_url="http://antd.test")
    client._http = httpx.AsyncClient(
        base_url="http://antd.test", transport=httpx.MockTransport(handler),
    )
    monkeypatch.setattr(server, "_get_ctx", lambda ctx: (client, "test-net"))
    return client


async def _call_real(monkeypatch, status, body, name, **kwargs) -> dict:
    client = _real_client(monkeypatch, status, body)
    try:
        return await _call(name, **kwargs)
    finally:
        await client.close()


@pytest.mark.asyncio
async def test_real_client_final_counter_round_trips_as_string(monkeypatch):
    body = {
        "address": OWNER, "owner": "ab" * 4, "counter": FINAL, "kind": "pointer",
        "kind_tag": 1, "target": RECIPIENT, "state_id": STATE_ID, "is_final": True,
        "transferred_to": RECIPIENT,
    }

    payload = await _call_real(monkeypatch, 200, body, "pointer_get", address=OWNER)

    assert payload["counter"] == FINAL
    assert payload["is_final"] is True


@pytest.mark.asyncio
async def test_real_client_malformed_counter_is_internal_error(monkeypatch):
    body = {"address": OWNER, "state_id": STATE_ID, "counter": 1}  # a JSON number

    payload = await _call_real(
        monkeypatch, 200, body, "pointer_create", owner=OWNER, target=TARGET_1,
    )

    assert payload["error"] == "INTERNAL_ERROR"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "status, body, code",
    [
        (409, {"error": "Pointer is final", "code": "POINTER_FINAL"}, "POINTER_FINAL"),
        (409, {"error": "Pointer is forked", "code": "POINTER_FORKED"}, "POINTER_FORKED"),
        (409, {"error": "Conflict: pending", "code": "CONFLICT"}, "CONFLICT"),
        (409, {"error": "pointer exists", "code": "ALREADY_EXISTS"}, "ALREADY_EXISTS"),
    ],
    ids=["final", "forked", "conflict", "already-exists"],
)
async def test_real_client_409s_map_by_code(monkeypatch, status, body, code):
    payload = await _call_real(
        monkeypatch, status, body, "pointer_update", owner=OWNER, target=TARGET_1,
    )

    assert payload["error"] == code
    assert payload["status_code"] == 409


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "retryable_json, retryable",
    [(True, True), (False, False), (None, False), ("true", False)],
    ids=["true", "false", "missing", "quoted"],
)
async def test_real_client_shortfall_retryable(monkeypatch, retryable_json, retryable):
    body = {"error": "Close group shortfall: 4 of 7 stored", "code": "CLOSE_GROUP_SHORTFALL"}
    if retryable_json is not None:
        body["retryable"] = retryable_json

    payload = await _call_real(
        monkeypatch, 503, body, "pointer_finalize", upload_id="ptr-upload-1", tx_hashes={},
    )

    assert payload["error"] == "CLOSE_GROUP_SHORTFALL"
    assert payload["retryable"] is retryable
