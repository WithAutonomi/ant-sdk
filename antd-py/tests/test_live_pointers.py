"""Live pointer round trip against a running antd with a devnet behind it.

Skipped unless all three are set:

- ``ANTD_TEST_URL``: the daemon's REST base URL, e.g. ``http://127.0.0.1:8082``
- ``ANTD_TEST_GRPC``: its gRPC target, e.g. ``127.0.0.1:50051``
- ``ANTD_TEST_POINTER_OWNERS``: two comma-separated pointer addresses the
  daemon holds keys for (``antd --pointer-keys``) and that have **never been
  written**. The test creates both, transfers the first to the second, and
  leaves the second with a prepared write awaiting payment, so each pair can
  be used once.

Every write is paid by the daemon's wallet, so run it against a devnet, and
run this file on its own: ``tests/test_integration.py`` also reads
``ANTD_TEST_URL`` and expects a daemon without a wallet.

    ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051 \\
    ANTD_TEST_POINTER_OWNERS=<hex>,<hex> python -m pytest -v tests/test_live_pointers.py
"""

from __future__ import annotations

import os

import pytest

from antd import (
    POINTER_FINAL_COUNTER,
    AlreadyExistsError,
    BadRequestError,
    ConflictError,
    NotFoundError,
    PointerFinalError,
    PointerFinalityStatus,
    PointerKind,
    PointerOp,
)
from antd._grpc import AsyncGrpcClient, GrpcClient
from antd._rest import AsyncRestClient, RestClient

URL = os.environ.get("ANTD_TEST_URL")
GRPC = os.environ.get("ANTD_TEST_GRPC")
OWNERS = os.environ.get("ANTD_TEST_POINTER_OWNERS", "")

pytestmark = pytest.mark.skipif(
    not (URL and GRPC and OWNERS.count(",") == 1),
    reason="set ANTD_TEST_URL, ANTD_TEST_GRPC and ANTD_TEST_POINTER_OWNERS to run",
)


def _bare(address: str) -> str:
    """The daemon accepts a 0x prefix but always answers in bare lowercase hex."""
    address = address.strip().lower()
    return address[2:] if address.startswith("0x") else address


@pytest.mark.asyncio
async def test_live_pointer_round_trip():
    a, b = (_bare(x) for x in OWNERS.split(","))
    assert URL is not None and GRPC is not None
    rest = RestClient(base_url=URL, timeout=600.0)
    grpc_client = GrpcClient(target=GRPC)
    arest = AsyncRestClient(base_url=URL, timeout=600.0)
    agrpc = AsyncGrpcClient(target=GRPC)
    try:
        # Both owners must be writable through this daemon.
        keys = rest.pointer_keys()
        assert a in keys and b in keys, f"daemon holds no key for one of the owners: {keys}"
        assert sorted(grpc_client.pointer_keys()) == sorted(keys)

        # Real targets, so the chain can be followed back to bytes.
        one = rest.data_put_public(b"antd-py pointer target one").address
        two = rest.data_put_public(b"antd-py pointer target two").address

        # -- REST: create, read, update --
        with pytest.raises(NotFoundError):
            rest.pointer_get(a)  # if this fails, the owner was written before: use a fresh pair
        w = rest.pointer_create(a, one)
        assert (w.address, w.counter) == (a, 0)
        with pytest.raises(AlreadyExistsError):
            rest.pointer_create(a, two)  # refused before paying
        r = rest.pointer_get(a)
        assert (r.counter, r.target, r.is_final, r.transferred_to) == (0, one, False, None)
        assert r.target_kind is PointerKind.CHUNK
        assert len(r.owner) == 2 * 1952
        res = rest.pointer_resolve(a)
        assert res.target == one
        assert rest.data_get_public(res.target) == b"antd-py pointer target one"

        w = rest.pointer_update(a, two)
        assert w.counter == 1
        assert rest.pointer_resolve(a).target == two
        f = rest.pointer_finality(a)
        assert f.status is PointerFinalityStatus.OPEN
        assert f.counter == 1
        assert f.answered == f.group

        # -- gRPC: a write, then reads (sync and async) --
        w = grpc_client.pointer_create(b, one)
        assert w.counter == 0
        r = grpc_client.pointer_get(b)
        assert (r.counter, r.target) == (0, one)
        assert (await agrpc.pointer_get(b)).target == one
        assert (await arest.pointer_get(a)).counter == 1

        # -- transfer a -> b --
        t = rest.pointer_transfer(a, b)
        assert t.finality is not None, f"the close group should answer after the transfer: {t.finality_error}"
        assert t.finality.status is PointerFinalityStatus.FINAL
        assert t.finality.transferred_to == b
        r = rest.pointer_get(a)
        assert r.is_final
        assert r.counter == POINTER_FINAL_COUNTER
        assert r.transferred_to == b
        c = rest.pointer_controller(a)
        assert (c.pointer, c.transfers) == (b, [b])
        # a now resolves through b.
        assert grpc_client.pointer_resolve(a).target == one
        assert grpc_client.pointer_finality(a).is_final
        assert (await agrpc.pointer_finality(a)).transferred_to == b

        # A final pointer refuses every write, before anything is paid.
        with pytest.raises(PointerFinalError):
            rest.pointer_update(a, one)
        with pytest.raises(PointerFinalError):
            grpc_client.pointer_update(a, one)
        with pytest.raises(PointerFinalError):
            await agrpc.pointer_update(a, one)
        with pytest.raises(PointerFinalError):
            rest.pointer_transfer(a, b)

        # -- external signer, up to the quote --
        # Last: the prepared write blocks b's other writes until it expires.
        p = rest.pointer_prepare(b, PointerOp.UPDATE, target=two)
        assert (p.op, p.counter, p.address) == ("update", 1, b)
        assert p.payment_type == "wave_batch"
        assert p.payments and p.upload_id
        with pytest.raises(ConflictError):
            rest.pointer_update(b, two)
        with pytest.raises(ConflictError):
            grpc_client.pointer_prepare(b, PointerOp.UPDATE, target=two)
        with pytest.raises(ConflictError):
            await arest.pointer_update(b, two)
        # A finalize without the payment is refused and keeps the session.
        with pytest.raises(BadRequestError):
            rest.pointer_finalize(p.upload_id, {})
        with pytest.raises(ConflictError):
            rest.pointer_update(b, two)
    finally:
        rest.close()
        grpc_client.close()
        await arest.close()
        await agrpc.close()
