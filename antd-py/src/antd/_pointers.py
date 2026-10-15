"""Pointer request/response mapping shared by the REST and gRPC clients.

The REST parsers read the daemon's JSON; the ``*_from_pb`` converters read
the PointerService messages by attribute, so this module never imports grpc
or the generated stubs and the REST-only install keeps working.

The two transports differ in how they leave a value unset: REST sends
``null`` (or omits the field), gRPC sends ``""`` or an absent message. Both
read as ``None`` here, so the models come out the same either way.
"""

from __future__ import annotations

import base64
import re
from enum import Enum

from .exceptions import InternalError
from .models import (
    POINTER_FINAL_COUNTER,
    PaymentInfo,
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
    SignedQuoteEntry,
)

# ASCII digits only. ``int()`` alone would also take "+1", " 1", "1_000" and
# non-ASCII decimal digits, none of which the daemon writes.
_DECIMAL = re.compile(r"[0-9]+", re.ASCII)
# u64::MAX has 20 digits; leading zeros aside, anything longer cannot fit, and
# checking first keeps int() away from its 4300-digit limit.
_U64_DIGITS = 20
# A target-kind tag is a u8. One that is missing or out of range reads as
# 255, which names no kind (PointerKind.from_tag returns None).
_UNKNOWN_KIND_TAG = 255


def wire(value: Enum | str) -> str:
    """The wire string for an enum member or a plain string."""
    return value.value if isinstance(value, Enum) else value


def parse_counter(field: str, value: object) -> int:
    """Parse a pointer counter: a decimal string of ASCII digits in
    ``0..=POINTER_FINAL_COUNTER``. Anything else (a JSON number, an empty or
    signed string, whitespace, underscores, a value past u64) raises
    :class:`InternalError`; a counter never silently reads as 0."""
    if isinstance(value, str) and _DECIMAL.fullmatch(value):
        digits = value.lstrip("0") or "0"
        if len(digits) <= _U64_DIGITS:
            n = int(digits)
            if n <= POINTER_FINAL_COUNTER:
                return n
    raise InternalError(f"invalid pointer {field} {value!r}: expected a decimal u64")


def _opt_counter(field: str, value: object) -> int | None:
    """An optional counter: ``None`` / ``""`` are unset, anything else must
    parse."""
    if value is None or value == "":
        return None
    return parse_counter(field, value)


def _str(j: dict, key: str) -> str:
    value = j.get(key)
    return value if isinstance(value, str) else ""


def _opt_str(value: object) -> str | None:
    """REST ``null`` / absent and gRPC ``""`` both read as ``None``."""
    return value if isinstance(value, str) and value else None


def _uint(value: object, limit: int) -> int:
    """A JSON unsigned integer up to ``limit``; anything else reads as 0."""
    if isinstance(value, bool) or not isinstance(value, int):
        return 0
    return value if 0 <= value <= limit else 0


def _kind_tag(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= 255:
        return _UNKNOWN_KIND_TAG
    return value


def _dicts(value: object) -> list[dict]:
    return [v for v in value if isinstance(v, dict)] if isinstance(value, list) else []


# --- Request bodies (REST) -----------------------------------------------


def write_body(owner: str, target: str, kind: PointerKind | str) -> dict:
    return {"owner": owner, "target": target, "kind": wire(kind)}


def prepare_body(
    owner: str,
    op: PointerOp | str,
    target: str | None,
    kind: PointerKind | str | None,
    recipient: str | None,
    include_signed_quotes: bool,
) -> dict:
    body: dict = {"owner": owner, "op": wire(op)}
    if target is not None:
        body["target"] = target
    if kind is not None:
        body["kind"] = wire(kind)
    if recipient is not None:
        body["recipient"] = recipient
    if include_signed_quotes:
        body["include_signed_quotes"] = True
    return body


# --- REST responses --------------------------------------------------------


def keys_from_json(j: dict) -> list[str]:
    return [_str(k, "address") for k in _dicts(j.get("keys"))]


def write_from_json(j: dict) -> PointerWriteResult:
    return PointerWriteResult(
        address=_str(j, "address"),
        state_id=_str(j, "state_id"),
        counter=parse_counter("counter", j.get("counter")),
    )


def record_from_json(j: dict) -> PointerRecord:
    return PointerRecord(
        address=_str(j, "address"),
        owner=_str(j, "owner"),
        counter=parse_counter("counter", j.get("counter")),
        kind=_str(j, "kind"),
        kind_tag=_kind_tag(j.get("kind_tag")),
        target=_str(j, "target"),
        state_id=_str(j, "state_id"),
        is_final=j.get("is_final") is True,
        transferred_to=_opt_str(j.get("transferred_to")),
    )


def target_from_json(j: dict) -> PointerTarget:
    return PointerTarget(
        kind=_str(j, "kind"),
        kind_tag=_kind_tag(j.get("kind_tag")),
        target=_str(j, "target"),
    )


def _final_state_from_json(j: dict) -> PointerFinalState:
    return PointerFinalState(
        state_id=_str(j, "state_id"),
        kind=_str(j, "kind"),
        kind_tag=_kind_tag(j.get("kind_tag")),
        target=_str(j, "target"),
        holders=_uint(j.get("holders"), 2**32 - 1),
        transferred_to=_opt_str(j.get("transferred_to")),
    )


def _opt_final_state_from_json(value: object) -> PointerFinalState | None:
    return _final_state_from_json(value) if isinstance(value, dict) else None


def finality_from_json(j: dict) -> PointerFinality:
    raw_status = _str(j, "status")
    return PointerFinality(
        address=_str(j, "address"),
        group=_uint(j.get("group"), 2**32 - 1),
        answered=_uint(j.get("answered"), 2**32 - 1),
        status=PointerFinalityStatus.from_wire(raw_status),
        raw_status=raw_status,
        counter=_opt_counter("counter", j.get("counter")),
        state=_opt_final_state_from_json(j.get("state")),
        states=[_final_state_from_json(s) for s in _dicts(j.get("states"))],
        majority=_opt_final_state_from_json(j.get("majority")),
        transferred_to=_opt_str(j.get("transferred_to")),
    )


def _opt_finality_from_json(value: object) -> PointerFinality | None:
    return finality_from_json(value) if isinstance(value, dict) else None


def controller_from_json(j: dict) -> PointerController:
    transfers = j.get("transfers")
    return PointerController(
        pointer=_str(j, "pointer"),
        transfers=[t for t in transfers if isinstance(t, str)] if isinstance(transfers, list) else [],
        frozen=j.get("frozen") is True,
    )


def transfer_from_json(j: dict) -> PointerTransferResult:
    return PointerTransferResult(
        address=_str(j, "address"),
        state_id=_str(j, "state_id"),
        finality=_opt_finality_from_json(j.get("finality")),
        finality_error=_opt_str(j.get("finality_error")),
    )


def prepare_from_json(j: dict) -> PointerPrepareResult:
    return PointerPrepareResult(
        upload_id=_str(j, "upload_id"),
        op=_str(j, "op"),
        address=_str(j, "address"),
        state_id=_str(j, "state_id"),
        counter=parse_counter("counter", j.get("counter")),
        payment_type=_str(j, "payment_type"),
        payments=[
            PaymentInfo(
                quote_hash=_str(p, "quote_hash"),
                rewards_address=_str(p, "rewards_address"),
                amount=_str(p, "amount"),
            )
            for p in _dicts(j.get("payments"))
        ],
        total_amount=_str(j, "total_amount"),
        payment_vault_address=_str(j, "payment_vault_address"),
        payment_token_address=_str(j, "payment_token_address"),
        rpc_url=_str(j, "rpc_url"),
        signed_quotes=[
            SignedQuoteEntry(
                quote_hash=_str(q, "quote_hash"),
                quote=_str(q, "quote"),
                commitment_sidecar=_opt_str(q.get("commitment_sidecar")),
            )
            for q in _dicts(j.get("signed_quotes"))
        ],
    )


def finalize_from_json(j: dict) -> PointerFinalizeResult:
    return PointerFinalizeResult(
        address=_str(j, "address"),
        state_id=_str(j, "state_id"),
        counter=parse_counter("counter", j.get("counter")),
        finality=_opt_finality_from_json(j.get("finality")),
    )


# --- gRPC responses (PointerService messages, read by attribute) -----------


def write_from_pb(resp) -> PointerWriteResult:
    return PointerWriteResult(
        address=resp.address,
        state_id=resp.state_id,
        counter=parse_counter("counter", resp.counter),
    )


def record_from_pb(resp) -> PointerRecord:
    return PointerRecord(
        address=resp.address,
        owner=resp.owner,
        counter=parse_counter("counter", resp.counter),
        kind=resp.kind,
        kind_tag=_kind_tag(resp.kind_tag),
        target=resp.target,
        state_id=resp.state_id,
        is_final=bool(resp.is_final),
        transferred_to=_opt_str(resp.transferred_to),
    )


def target_from_pb(resp) -> PointerTarget:
    return PointerTarget(kind=resp.kind, kind_tag=_kind_tag(resp.kind_tag), target=resp.target)


def _final_state_from_pb(s) -> PointerFinalState:
    return PointerFinalState(
        state_id=s.state_id,
        kind=s.kind,
        kind_tag=_kind_tag(s.kind_tag),
        target=s.target,
        holders=int(s.holders),
        transferred_to=_opt_str(s.transferred_to),
    )


def finality_from_pb(f) -> PointerFinality:
    return PointerFinality(
        address=f.address,
        group=int(f.group),
        answered=int(f.answered),
        status=PointerFinalityStatus.from_wire(f.status),
        raw_status=f.status,
        counter=_opt_counter("counter", f.counter),
        state=_final_state_from_pb(f.state) if f.HasField("state") else None,
        states=[_final_state_from_pb(s) for s in f.states],
        majority=_final_state_from_pb(f.majority) if f.HasField("majority") else None,
        transferred_to=_opt_str(f.transferred_to),
    )


def controller_from_pb(resp) -> PointerController:
    return PointerController(pointer=resp.pointer, transfers=list(resp.transfers), frozen=bool(resp.frozen))


def transfer_from_pb(resp) -> PointerTransferResult:
    return PointerTransferResult(
        address=resp.address,
        state_id=resp.state_id,
        finality=finality_from_pb(resp.finality) if resp.HasField("finality") else None,
        finality_error=_opt_str(resp.finality_error),
    )


def prepare_from_pb(resp) -> PointerPrepareResult:
    return PointerPrepareResult(
        upload_id=resp.upload_id,
        op=resp.op,
        address=resp.address,
        state_id=resp.state_id,
        counter=parse_counter("counter", resp.counter),
        payment_type=resp.payment_type,
        payments=[
            PaymentInfo(quote_hash=p.quote_hash, rewards_address=p.rewards_address, amount=p.amount)
            for p in resp.payments
        ],
        total_amount=resp.total_amount,
        payment_vault_address=resp.payment_vault_address,
        payment_token_address=resp.payment_token_address,
        rpc_url=resp.rpc_url,
        # REST sends these as base64 strings; encode the raw bytes to match.
        signed_quotes=[
            SignedQuoteEntry(
                quote_hash=q.quote_hash,
                quote=base64.b64encode(q.quote).decode(),
                commitment_sidecar=(
                    base64.b64encode(q.commitment_sidecar).decode() if q.commitment_sidecar else None
                ),
            )
            for q in resp.signed_quotes
        ],
    )


def finalize_from_pb(resp) -> PointerFinalizeResult:
    return PointerFinalizeResult(
        address=resp.address,
        state_id=resp.state_id,
        counter=parse_counter("counter", resp.counter),
        finality=finality_from_pb(resp.finality) if resp.HasField("finality") else None,
    )
