"""V2-286 WalletService wire-mapping tests for GrpcClient + AsyncGrpcClient.

Spins up an in-process gRPC server with a MockWalletServicer, then dials
with a real client. Mirrors the antd-rust / antd-go suites for V2-286.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

import grpc
import grpc.aio
import pytest
import pytest_asyncio

from antd._grpc import AsyncGrpcClient, GrpcClient
from antd._proto.antd.v1 import wallet_pb2, wallet_pb2_grpc
from antd.exceptions import PaymentError


# --- Mock servicers ---------------------------------------------------------


class MockWalletServicer(wallet_pb2_grpc.WalletServiceServicer):
    def GetAddress(self, request, context):
        return wallet_pb2.GetWalletAddressResponse(
            address="0xabc1234567890abcdef1234567890abcdef123456"
        )

    def GetBalance(self, request, context):
        return wallet_pb2.GetWalletBalanceResponse(
            balance="1000000000000000000",
            gas_balance="500000000000000000",
        )

    def Approve(self, request, context):
        return wallet_pb2.WalletApproveResponse(approved=True)


class UnconfiguredWalletServicer(wallet_pb2_grpc.WalletServiceServicer):
    """Daemon without AUTONOMI_WALLET_KEY → FailedPrecondition on every RPC."""

    def _fail(self, context):
        context.set_code(grpc.StatusCode.FAILED_PRECONDITION)
        context.set_details("wallet not configured — set AUTONOMI_WALLET_KEY")
        return None

    def GetAddress(self, request, context):
        self._fail(context)
        return wallet_pb2.GetWalletAddressResponse()

    def GetBalance(self, request, context):
        self._fail(context)
        return wallet_pb2.GetWalletBalanceResponse()

    def Approve(self, request, context):
        self._fail(context)
        return wallet_pb2.WalletApproveResponse()


# --- Sync fixtures ----------------------------------------------------------


def _start_sync(servicer):
    server = grpc.server(ThreadPoolExecutor(max_workers=4))
    wallet_pb2_grpc.add_WalletServiceServicer_to_server(servicer, server)
    port = server.add_insecure_port("127.0.0.1:0")
    server.start()
    client = GrpcClient(target=f"127.0.0.1:{port}")
    return server, client


@pytest.fixture
def sync_client():
    server, client = _start_sync(MockWalletServicer())
    try:
        yield client
    finally:
        client.close()
        server.stop(None)


@pytest.fixture
def sync_client_unconfigured():
    server, client = _start_sync(UnconfiguredWalletServicer())
    try:
        yield client
    finally:
        client.close()
        server.stop(None)


# --- Async fixtures ---------------------------------------------------------


async def _start_async(servicer):
    server = grpc.aio.server()
    wallet_pb2_grpc.add_WalletServiceServicer_to_server(servicer, server)
    port = server.add_insecure_port("127.0.0.1:0")
    await server.start()
    client = AsyncGrpcClient(target=f"127.0.0.1:{port}")
    return server, client


@pytest_asyncio.fixture
async def async_client():
    server, client = await _start_async(MockWalletServicer())
    try:
        yield client
    finally:
        await client.close()
        await server.stop(None)


@pytest_asyncio.fixture
async def async_client_unconfigured():
    server, client = await _start_async(UnconfiguredWalletServicer())
    try:
        yield client
    finally:
        await client.close()
        await server.stop(None)


# --- Sync tests -------------------------------------------------------------


class TestSyncWallet:
    def test_wallet_address(self, sync_client: GrpcClient):
        r = sync_client.wallet_address()
        assert r.address == "0xabc1234567890abcdef1234567890abcdef123456"

    def test_wallet_balance(self, sync_client: GrpcClient):
        r = sync_client.wallet_balance()
        assert r.balance == "1000000000000000000"
        assert r.gas_balance == "500000000000000000"

    def test_wallet_approve(self, sync_client: GrpcClient):
        assert sync_client.wallet_approve() is True

    def test_wallet_address_unconfigured(self, sync_client_unconfigured: GrpcClient):
        # FailedPrecondition → PaymentError per the established gRPC→SDK mapping
        # (the semantic is a bit off vs REST's 503 but matches every SDK).
        with pytest.raises(PaymentError) as exc:
            sync_client_unconfigured.wallet_address()
        assert "wallet not configured" in str(exc.value)


# --- Async tests ------------------------------------------------------------


class TestAsyncWallet:
    @pytest.mark.asyncio
    async def test_wallet_address(self, async_client: AsyncGrpcClient):
        r = await async_client.wallet_address()
        assert r.address == "0xabc1234567890abcdef1234567890abcdef123456"

    @pytest.mark.asyncio
    async def test_wallet_balance(self, async_client: AsyncGrpcClient):
        r = await async_client.wallet_balance()
        assert r.balance == "1000000000000000000"
        assert r.gas_balance == "500000000000000000"

    @pytest.mark.asyncio
    async def test_wallet_approve(self, async_client: AsyncGrpcClient):
        assert await async_client.wallet_approve() is True

    @pytest.mark.asyncio
    async def test_wallet_address_unconfigured(
        self, async_client_unconfigured: AsyncGrpcClient
    ):
        with pytest.raises(PaymentError) as exc:
            await async_client_unconfigured.wallet_address()
        assert "wallet not configured" in str(exc.value)
