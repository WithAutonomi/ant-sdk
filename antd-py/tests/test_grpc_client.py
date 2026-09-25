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
from antd.exceptions import ForkError, NetworkError, PartialUploadError
from antd._proto.antd.v1 import (
    chunks_pb2,
    chunks_pb2_grpc,
    common_pb2,
    data_pb2,
    data_pb2_grpc,
    upload_pb2,
    upload_pb2_grpc,
)


_RETAINED_HINT = (
    "(paid attempt retained: call finalize again with the same upload_id to "
    "store the remainder against the same payment)"
)
_U64_OVERFLOW = "18446744073709551616"  # u64::MAX + 1
_OVER_INT_LIMIT = "9" * 5000  # past int()'s 4300-digit limit (Python >= 3.11)

# upload_id -> ABORTED details for the malformed-message cases.
_MALFORMED_ABORTED = {
    "overflow-stored": f"Partial upload: {_U64_OVERFLOW}/3 chunks stored, 2 failed after retries: quorum {_RETAINED_HINT}",
    "overflow-total": f"Partial upload: 1/{_U64_OVERFLOW} chunks stored, 2 failed after retries: quorum {_RETAINED_HINT}",
    "overflow-failed": f"Partial upload: 1/3 chunks stored, {_U64_OVERFLOW} failed after retries: quorum {_RETAINED_HINT}",
    "huge-stored": f"Partial upload: {_OVER_INT_LIMIT}/3 chunks stored, 2 failed after retries: quorum {_RETAINED_HINT}",
    "huge-total": f"Partial upload: 1/{_OVER_INT_LIMIT} chunks stored, 2 failed after retries: quorum {_RETAINED_HINT}",
    "huge-failed": f"Partial upload: 1/3 chunks stored, {_OVER_INT_LIMIT} failed after retries: quorum {_RETAINED_HINT}",
    "miss-with-hint": f"Partial upload: counts unavailable {_RETAINED_HINT}",
    "well-formed-hint": f"Partial upload: 1/3 chunks stored, 2 failed after retries: quorum {_RETAINED_HINT}",
    "well-formed-no-hint": "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum",
    "truncated-hint": "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum (paid attempt retai",
    "embedded-marker": "upstream error: Partial upload: 1/3 chunks stored, 2 failed",
    "embedded-marker-hint": f"upstream error: Partial upload: 1/3 chunks stored, 2 failed {_RETAINED_HINT}",
}

_UNREADABLE_COUNTS = [
    "overflow-stored", "overflow-total", "overflow-failed",
    "huge-stored", "huge-total", "huge-failed", "miss-with-hint",
]

# Readable counts but no readable retention hint (missing, or the review's
# truncated reproducer): retention unknown, never "nothing retained".
_COUNTS_WITHOUT_HINT = ["well-formed-no-hint", "truncated-hint"]


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
            total_chunks=3,
            already_stored_count=1,
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
        if request.upload_id in _MALFORMED_ABORTED:
            context.set_code(grpc.StatusCode.ABORTED)
            context.set_details(_MALFORMED_ABORTED[request.upload_id])
            return upload_pb2.FinalizeUploadResponse()
        # PARTIAL_UPLOAD rides gRPC ABORTED with the counts in the message.
        # "partial" carries the daemon's "paid attempt retained" hint
        # (antd >= 0.14.0); "partial-final" carries the re-prepare hint.
        if request.upload_id in ("partial", "partial-final"):
            hint = (
                "paid attempt retained: call finalize again with the same "
                "upload_id to store the remainder against the same payment"
                if request.upload_id == "partial" else
                "stored chunks persist; re-prepare the same content to retry "
                "only the remainder"
            )
            context.set_code(grpc.StatusCode.ABORTED)
            context.set_details(
                f"Partial upload: 300/312 chunks stored, 12 failed after retries: quorum ({hint})"
            )
            return upload_pb2.FinalizeUploadResponse()
        # The daemon's prefix but counts the SDK cannot parse: still a
        # partial upload, with the counts left at zero.
        if request.upload_id == "partial-garbled":
            context.set_code(grpc.StatusCode.ABORTED)
            context.set_details("Partial upload: counts unavailable")
            return upload_pb2.FinalizeUploadResponse()
        # Any other ABORTED is not a partial upload and keeps the pre-existing
        # ForkError mapping.
        if request.upload_id == "fork":
            context.set_code(grpc.StatusCode.ABORTED)
            context.set_details("version conflict: upload was superseded")
            return upload_pb2.FinalizeUploadResponse()
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


class MockDataServicer(data_pb2_grpc.DataServiceServicer):
    """Server-streams the payload in two chunks so the client's
    chunk-by-chunk consumption is exercised, not just a single message."""

    def Stream(self, request, context):
        if request.include_progress:
            # Mirror the daemon: attach the byte total as initial metadata.
            context.send_initial_metadata([("x-content-length", "6")])
            yield data_pb2.DataChunk(progress=data_pb2.DownloadProgress(
                phase="fetching", fetched=1, total=2))
        for part in (b"sec", b"ret"):
            yield data_pb2.DataChunk(data=part)

    def StreamPublic(self, request, context):
        if request.include_progress:
            context.send_initial_metadata([("x-content-length", "5")])
            yield data_pb2.DataChunk(progress=data_pb2.DownloadProgress(
                phase="fetching", fetched=1, total=2))
        for part in (b"hel", b"lo"):
            yield data_pb2.DataChunk(data=part)


# --- Fixtures: sync + async mock servers -----------------------------------


@pytest.fixture
def sync_client():
    server = grpc.server(ThreadPoolExecutor(max_workers=4))
    chunks_pb2_grpc.add_ChunkServiceServicer_to_server(MockChunkServicer(), server)
    upload_pb2_grpc.add_UploadServiceServicer_to_server(MockUploadServicer(), server)
    data_pb2_grpc.add_DataServiceServicer_to_server(MockDataServicer(), server)
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
    data_pb2_grpc.add_DataServiceServicer_to_server(MockDataServicer(), server)
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
        assert r.total_chunks == 3
        assert r.already_stored_count == 1
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


class TestSyncFinalizePartialUpload:
    """ABORTED whose message carries the daemon's "Partial upload:" prefix
    maps to PartialUploadError with counts parsed from the message; any other
    ABORTED stays a ForkError."""

    def test_retained_hint_reads_retryable(self, sync_client):
        with pytest.raises(PartialUploadError) as exc_info:
            sync_client.finalize_merkle_upload("partial", "0xwinpool")
        err = exc_info.value
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (300, 12, 312)
        assert err.retryable is True
        assert err.retention_known is True
        assert err.status_code == grpc.StatusCode.ABORTED.value[0]

    def test_no_retained_hint_reads_not_retryable(self, sync_client):
        with pytest.raises(PartialUploadError) as exc_info:
            sync_client.finalize_upload("partial-final", {"0xq1": "0xtx1"})
        err = exc_info.value
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (300, 12, 312)
        assert err.retryable is False
        assert err.retention_known is True  # the not-retained hint: nothing kept

    def test_is_a_network_error(self, sync_client):
        with pytest.raises(NetworkError):
            sync_client.finalize_upload("partial", {"0xq1": "0xtx1"})

    def test_prefix_with_garbled_counts_reads_zeros(self, sync_client):
        with pytest.raises(PartialUploadError) as exc_info:
            sync_client.finalize_upload("partial-garbled", {"0xq1": "0xtx1"})
        err = exc_info.value
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (0, 0, 0)
        assert err.retryable is False
        assert err.retention_known is False

    def test_aborted_without_prefix_is_fork_error(self, sync_client):
        with pytest.raises(ForkError) as exc_info:
            sync_client.finalize_upload("fork", {"0xq1": "0xtx1"})
        assert not isinstance(exc_info.value, PartialUploadError)
        assert exc_info.value.status_code == grpc.StatusCode.ABORTED.value[0]
        assert "version conflict" in str(exc_info.value)


class TestSyncFinalizePartialUploadMalformed:
    """Retention is known only when the message matched, every count
    converted, and one of the daemon's two hints closes it; retryable only
    for the retained hint. The gate is anchored (only details that START
    WITH "Partial upload:" are a partial upload)."""

    @pytest.mark.parametrize("upload_id", _UNREADABLE_COUNTS)
    def test_unreadable_counts_read_zero_and_not_retryable(self, sync_client, upload_id):
        with pytest.raises(PartialUploadError) as exc_info:
            sync_client.finalize_upload(upload_id, {"0xq1": "0xtx1"})
        err = exc_info.value
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (0, 0, 0)
        assert err.retryable is False
        assert err.retention_known is False
        assert str(err) == _MALFORMED_ABORTED[upload_id]

    def test_well_formed_with_hint_is_retryable(self, sync_client):
        with pytest.raises(PartialUploadError) as exc_info:
            sync_client.finalize_upload("well-formed-hint", {"0xq1": "0xtx1"})
        err = exc_info.value
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (1, 2, 3)
        assert err.retryable is True
        assert err.retention_known is True

    @pytest.mark.parametrize("upload_id", _COUNTS_WITHOUT_HINT)
    def test_counts_without_a_readable_hint_are_unknown(self, sync_client, upload_id):
        with pytest.raises(PartialUploadError) as exc_info:
            sync_client.finalize_merkle_upload(upload_id, "0xwinpool")
        err = exc_info.value
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (1, 2, 3)
        assert err.retryable is False
        assert err.retention_known is False

    @pytest.mark.parametrize("upload_id", ["embedded-marker", "embedded-marker-hint"])
    def test_embedded_marker_is_not_a_partial_upload(self, sync_client, upload_id):
        with pytest.raises(ForkError) as exc_info:
            sync_client.finalize_upload(upload_id, {"0xq1": "0xtx1"})
        assert not isinstance(exc_info.value, PartialUploadError)
        assert str(exc_info.value) == _MALFORMED_ABORTED[upload_id]


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


class TestAsyncFinalizePartialUpload:
    @pytest.mark.asyncio
    async def test_retained_hint_reads_retryable(self, async_client):
        with pytest.raises(PartialUploadError) as exc_info:
            await async_client.finalize_upload("partial", {"0xq1": "0xtx1"})
        err = exc_info.value
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (300, 12, 312)
        assert err.retryable is True
        assert err.retention_known is True

    @pytest.mark.asyncio
    async def test_no_retained_hint_reads_not_retryable(self, async_client):
        with pytest.raises(PartialUploadError) as exc_info:
            await async_client.finalize_merkle_upload("partial-final", "0xwinpool")
        assert exc_info.value.retryable is False
        assert exc_info.value.retention_known is True
        assert exc_info.value.chunks_failed == 12

    @pytest.mark.asyncio
    async def test_prefix_with_garbled_counts_reads_zeros(self, async_client):
        with pytest.raises(PartialUploadError) as exc_info:
            await async_client.finalize_merkle_upload("partial-garbled", "0xwinpool")
        err = exc_info.value
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (0, 0, 0)
        assert err.retryable is False
        assert err.retention_known is False

    @pytest.mark.asyncio
    async def test_aborted_without_prefix_is_fork_error(self, async_client):
        with pytest.raises(ForkError) as exc_info:
            await async_client.finalize_merkle_upload("fork", "0xwinpool")
        assert not isinstance(exc_info.value, PartialUploadError)


class TestAsyncFinalizePartialUploadMalformed:
    @pytest.mark.asyncio
    @pytest.mark.parametrize("upload_id", _UNREADABLE_COUNTS)
    async def test_unreadable_counts_read_zero_and_not_retryable(self, async_client, upload_id):
        with pytest.raises(PartialUploadError) as exc_info:
            await async_client.finalize_merkle_upload(upload_id, "0xwinpool")
        err = exc_info.value
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (0, 0, 0)
        assert err.retryable is False
        assert err.retention_known is False

    @pytest.mark.asyncio
    async def test_well_formed_with_hint_is_retryable(self, async_client):
        with pytest.raises(PartialUploadError) as exc_info:
            await async_client.finalize_upload("well-formed-hint", {"0xq1": "0xtx1"})
        err = exc_info.value
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks, err.retryable) == (1, 2, 3, True)
        assert err.retention_known is True

    @pytest.mark.asyncio
    @pytest.mark.parametrize("upload_id", _COUNTS_WITHOUT_HINT)
    async def test_counts_without_a_readable_hint_are_unknown(self, async_client, upload_id):
        with pytest.raises(PartialUploadError) as exc_info:
            await async_client.finalize_upload(upload_id, {"0xq1": "0xtx1"})
        err = exc_info.value
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (1, 2, 3)
        assert (err.retryable, err.retention_known) == (False, False)

    @pytest.mark.asyncio
    async def test_embedded_marker_is_not_a_partial_upload(self, async_client):
        with pytest.raises(ForkError) as exc_info:
            await async_client.finalize_upload("embedded-marker-hint", {"0xq1": "0xtx1"})
        assert not isinstance(exc_info.value, PartialUploadError)


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


class TestSyncDataStream:
    def test_stream_private(self, sync_client):
        chunks = list(sync_client.data_stream("dm123"))
        assert chunks == [b"sec", b"ret"]
        assert b"".join(chunks) == b"secret"

    def test_stream_public(self, sync_client):
        assert b"".join(sync_client.data_stream_public("abc123")) == b"hello"

    def test_stream_with_progress(self, sync_client):
        frames = list(sync_client.data_stream_with_progress("dm123"))
        data = b"".join(f.data for f in frames if f.data is not None)
        progress = [f.progress for f in frames if f.is_progress]
        meta = [f.meta for f in frames if f.is_meta]
        assert data == b"secret"
        assert meta == [6]
        assert len(progress) == 1
        assert progress[0].phase == "fetching"
        assert progress[0].fetched == 1 and progress[0].total == 2

    def test_stream_public_with_progress(self, sync_client):
        frames = list(sync_client.data_stream_public_with_progress("abc123"))
        assert b"".join(f.data for f in frames if f.data is not None) == b"hello"
        assert [f.meta for f in frames if f.is_meta] == [5]
        assert any(f.is_progress for f in frames)


class TestAsyncDataStream:
    @pytest.mark.asyncio
    async def test_stream_private(self, async_client):
        chunks = [c async for c in async_client.data_stream("dm123")]
        assert chunks == [b"sec", b"ret"]
        assert b"".join(chunks) == b"secret"

    @pytest.mark.asyncio
    async def test_stream_public(self, async_client):
        chunks = [c async for c in async_client.data_stream_public("abc123")]
        assert b"".join(chunks) == b"hello"

    @pytest.mark.asyncio
    async def test_stream_with_progress(self, async_client):
        frames = [f async for f in async_client.data_stream_with_progress("dm123")]
        data = b"".join(f.data for f in frames if f.data is not None)
        progress = [f.progress for f in frames if f.is_progress]
        assert data == b"secret"
        assert [f.meta for f in frames if f.is_meta] == [6]
        assert len(progress) == 1 and progress[0].total == 2
