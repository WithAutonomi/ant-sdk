"""Mock-server tests for the external-signer prepare/finalize surface on
GrpcClient and AsyncGrpcClient. Mirrors the antd-rust / antd-go suite.

Uses an in-process gRPC server (one per test, random port) so the tests run
without a live antd daemon.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

import grpc
import grpc.aio
import pytest
import pytest_asyncio

from antd._grpc import AsyncGrpcClient, GrpcClient
from antd._proto.antd.v1 import (
    chunks_pb2,
    chunks_pb2_grpc,
    common_pb2,
    upload_pb2,
    upload_pb2_grpc,
)


# --- Mock servicers ---------------------------------------------------------


class MockChunkServicer(chunks_pb2_grpc.ChunkServiceServicer):
    """Mock implementation of the V2-284 chunk prepare/finalize RPCs."""

    def PrepareChunk(self, request, context):
        # Inputs starting with b"EXISTS" → already-stored short-circuit.
        if request.data.startswith(b"EXISTS"):
            return chunks_pb2.PrepareChunkResponse(
                address="0xabc",
                already_stored=True,
            )
        return chunks_pb2.PrepareChunkResponse(
            address="0xnewchunk",
            already_stored=False,
            upload_id="upid_chunk_42",
            payment_type="wave_batch",
            payments=[
                common_pb2.PaymentEntry(
                    quote_hash="0xq1",
                    rewards_address="0xr1",
                    amount="100",
                ),
            ],
            total_amount="100",
            payment_vault_address="0xvault",
            payment_token_address="0xtoken",
            rpc_url="http://localhost:8545",
        )

    def FinalizeChunk(self, request, context):
        # Echo the upload_id into the address so the test can verify forwarding.
        return chunks_pb2.FinalizeChunkResponse(
            address=f"addr_for_{request.upload_id}",
        )


class MockUploadServicer(upload_pb2_grpc.UploadServiceServicer):
    """Mock implementation of UploadService."""

    def PrepareFileUpload(self, request, context):
        # Encode visibility into upload_id so the test can verify forwarding.
        return upload_pb2.PrepareUploadResponse(
            upload_id=f"upid_file_{request.visibility}",
            payment_type="wave_batch",
            payments=[
                common_pb2.PaymentEntry(
                    quote_hash="0xqa",
                    rewards_address="0xra",
                    amount="1",
                ),
            ],
            total_amount="1",
            payment_vault_address="0xvault",
            payment_token_address="0xtoken",
            rpc_url="http://localhost:8545",
        )

    def PrepareDataUpload(self, request, context):
        # MERKLE payload → merkle response; otherwise wave-batch.
        upload_id = f"upid_data_{request.visibility}"
        if request.data.startswith(b"MERKLE"):
            return upload_pb2.PrepareUploadResponse(
                upload_id=upload_id,
                payment_type="merkle",
                depth=7,
                pool_commitments=[
                    upload_pb2.PoolCommitmentEntry(
                        pool_hash="0xpool",
                        candidates=[
                            upload_pb2.CandidateNodeEntry(
                                rewards_address="0xc1",
                                amount="5",
                            ),
                        ],
                    ),
                ],
                merkle_payment_timestamp=1_700_000_000,
                total_amount="0",
                payment_vault_address="0xvault",
                payment_token_address="0xtoken",
                rpc_url="http://localhost:8545",
            )
        return upload_pb2.PrepareUploadResponse(
            upload_id=upload_id,
            payment_type="wave_batch",
            payments=[
                common_pb2.PaymentEntry(
                    quote_hash="0xqb",
                    rewards_address="0xrb",
                    amount="2",
                ),
            ],
            total_amount="2",
            payment_vault_address="0xvault",
            payment_token_address="0xtoken",
            rpc_url="http://localhost:8545",
        )

    def FinalizeUpload(self, request, context):
        # Merkle: winner_pool_hash populated, tx_hashes empty.
        if request.winner_pool_hash:
            return upload_pb2.FinalizeUploadResponse(
                data_map="dm_merkle",
                address="stored_on_network" if request.store_data_map else "",
                chunks_stored=64,
            )
        # Wave-batch: include data_map_address when visibility was public
        # (encoded into upload_id by the prepare mock).
        data_map_address = ""
        if request.upload_id.endswith("public"):
            data_map_address = "addr_public_dm"
        return upload_pb2.FinalizeUploadResponse(
            data_map="dm_wave",
            data_map_address=data_map_address,
            chunks_stored=3,
        )


# --- Fixtures: sync + async mock servers -----------------------------------


@pytest.fixture
def sync_client():
    server = grpc.server(ThreadPoolExecutor(max_workers=4))
    chunks_pb2_grpc.add_ChunkServiceServicer_to_server(MockChunkServicer(), server)
    upload_pb2_grpc.add_UploadServiceServicer_to_server(MockUploadServicer(), server)
    port = server.add_insecure_port("127.0.0.1:0")
    server.start()
    client = GrpcClient(target=f"127.0.0.1:{port}")
    try:
        yield client
    finally:
        client.close()
        server.stop(None)


@pytest_asyncio.fixture
async def async_client():
    server = grpc.aio.server()
    chunks_pb2_grpc.add_ChunkServiceServicer_to_server(MockChunkServicer(), server)
    upload_pb2_grpc.add_UploadServiceServicer_to_server(MockUploadServicer(), server)
    port = server.add_insecure_port("127.0.0.1:0")
    await server.start()
    client = AsyncGrpcClient(target=f"127.0.0.1:{port}")
    try:
        yield client
    finally:
        await client.close()
        await server.stop(None)


# --- Sync tests ------------------------------------------------------------


class TestSyncPrepareUpload:
    def test_omits_visibility_when_none(self, sync_client):
        r = sync_client.prepare_upload("/tmp/x.bin")
        assert r.upload_id == "upid_file_"
        assert r.payment_type == "wave_batch"
        assert len(r.payments) == 1
        assert r.payments[0].quote_hash == "0xqa"
        assert r.depth == 0
        assert r.pool_commitments == []

    def test_forwards_visibility_public(self, sync_client):
        r = sync_client.prepare_upload("/tmp/x.bin", visibility="public")
        assert r.upload_id == "upid_file_public"

    def test_public_convenience_wrapper(self, sync_client):
        r = sync_client.prepare_upload_public("/tmp/x.bin")
        assert r.upload_id == "upid_file_public"


class TestSyncPrepareDataUpload:
    def test_wave_batch(self, sync_client):
        r = sync_client.prepare_data_upload(b"small")
        assert r.upload_id == "upid_data_"
        assert r.payment_type == "wave_batch"
        assert r.depth == 0
        assert r.pool_commitments == []

    def test_merkle(self, sync_client):
        r = sync_client.prepare_data_upload(b"MERKLE-large-payload")
        assert r.payment_type == "merkle"
        assert r.depth == 7
        assert r.merkle_payment_timestamp == 1_700_000_000
        assert len(r.pool_commitments) == 1
        assert r.pool_commitments[0].pool_hash == "0xpool"
        assert r.pool_commitments[0].candidates[0].rewards_address == "0xc1"


class TestSyncFinalizeUpload:
    def test_wave_batch_private_omits_data_map_address(self, sync_client):
        r = sync_client.finalize_upload("upid_file_", {"0xq1": "0xtx1"})
        assert r.data_map == "dm_wave"
        assert r.data_map_address == ""
        assert r.chunks_stored == 3

    def test_wave_batch_public_returns_data_map_address(self, sync_client):
        r = sync_client.finalize_upload("upid_file_public", {"0xq1": "0xtx1"})
        assert r.data_map_address == "addr_public_dm"


class TestSyncFinalizeMerkleUpload:
    def test_store_data_map_true(self, sync_client):
        r = sync_client.finalize_merkle_upload(
            "upid_data_", "0xwinpool", store_data_map=True,
        )
        assert r.data_map == "dm_merkle"
        assert r.address == "stored_on_network"
        assert r.chunks_stored == 64

    def test_store_data_map_false(self, sync_client):
        r = sync_client.finalize_merkle_upload("upid_data_", "0xwinpool")
        assert r.data_map == "dm_merkle"
        assert r.address == ""


class TestSyncChunkPrepareFinalize:
    def test_prepare_new_chunk(self, sync_client):
        r = sync_client.prepare_chunk_upload(b"newchunk")
        assert r.already_stored is False
        assert r.address == "0xnewchunk"
        assert r.upload_id == "upid_chunk_42"
        assert r.payment_type == "wave_batch"
        assert len(r.payments) == 1
        assert r.payments[0].quote_hash == "0xq1"
        assert r.total_amount == "100"
        assert r.rpc_url == "http://localhost:8545"

    def test_prepare_already_stored_short_circuit(self, sync_client):
        r = sync_client.prepare_chunk_upload(b"EXISTS-data")
        assert r.already_stored is True
        assert r.address == "0xabc"
        assert r.upload_id == ""
        assert r.payments == []

    def test_finalize_returns_address_and_forwards_body(self, sync_client):
        addr = sync_client.finalize_chunk_upload("upid_chunk_42", {"0xq1": "0xtxabc"})
        assert addr == "addr_for_upid_chunk_42"


# --- Async tests -----------------------------------------------------------


class TestAsyncPrepareUpload:
    @pytest.mark.asyncio
    async def test_omits_visibility_when_none(self, async_client):
        r = await async_client.prepare_upload("/tmp/x.bin")
        assert r.upload_id == "upid_file_"
        assert r.payment_type == "wave_batch"

    @pytest.mark.asyncio
    async def test_forwards_visibility_public(self, async_client):
        r = await async_client.prepare_upload("/tmp/x.bin", visibility="public")
        assert r.upload_id == "upid_file_public"

    @pytest.mark.asyncio
    async def test_public_convenience_wrapper(self, async_client):
        r = await async_client.prepare_upload_public("/tmp/x.bin")
        assert r.upload_id == "upid_file_public"


class TestAsyncPrepareDataUpload:
    @pytest.mark.asyncio
    async def test_merkle(self, async_client):
        r = await async_client.prepare_data_upload(b"MERKLE-payload")
        assert r.payment_type == "merkle"
        assert r.depth == 7
        assert len(r.pool_commitments) == 1


class TestAsyncFinalizeUpload:
    @pytest.mark.asyncio
    async def test_wave_batch_public(self, async_client):
        r = await async_client.finalize_upload(
            "upid_file_public", {"0xq1": "0xtx1"},
        )
        assert r.data_map_address == "addr_public_dm"

    @pytest.mark.asyncio
    async def test_merkle(self, async_client):
        r = await async_client.finalize_merkle_upload(
            "upid_data_", "0xwinpool", store_data_map=True,
        )
        assert r.address == "stored_on_network"
        assert r.chunks_stored == 64


class TestAsyncChunkPrepareFinalize:
    @pytest.mark.asyncio
    async def test_prepare_already_stored(self, async_client):
        r = await async_client.prepare_chunk_upload(b"EXISTS-x")
        assert r.already_stored is True
        assert r.address == "0xabc"

    @pytest.mark.asyncio
    async def test_finalize_returns_address(self, async_client):
        addr = await async_client.finalize_chunk_upload(
            "upid_chunk_42", {"0xq1": "0xtx1"},
        )
        assert addr == "addr_for_upid_chunk_42"
