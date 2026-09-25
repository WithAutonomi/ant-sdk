"""Tests for antd._rest.RestClient using a local mock HTTP server."""

from __future__ import annotations

import base64
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import httpx
import pytest

from antd._rest import RestClient, _acheck_streamed, _check
from antd.exceptions import BadRequestError, NetworkError, NotFoundError, PartialUploadError
from antd.models import (
    CandidateNodeEntry,
    DataPutPublicResult,
    DataPutResult,
    FilePutPublicResult,
    FilePutResult,
    FinalizeUploadResult,
    HealthStatus,
    PaymentMode,
    PoolCommitmentEntry,
    PrepareChunkResult,
    PrepareUploadResult,
    PutResult,
    WalletAddress,
    WalletBalance,
)


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


class _MockHandler(BaseHTTPRequestHandler):
    """Routes requests to canned JSON responses for testing."""

    def log_message(self, format, *args):
        # Suppress server log output during tests.
        pass

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length else b""

    def _json_response(self, status: int, body: dict) -> None:
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _raw_response(self, status: int, payload: bytes) -> None:
        """Send ``payload`` verbatim, for bodies ``json.dumps`` cannot produce
        (bare ``Infinity``, over-long integers) or that are not JSON objects."""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _ndjson_response(self, lines: list[dict]) -> None:
        payload = b"".join((json.dumps(o) + "\n").encode() for o in lines)
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    # --- GET routes ---

    def do_GET(self):  # noqa: N802
        path = self.path.split("?")[0]
        query = self.path.split("?")[1] if "?" in self.path else ""

        if path == "/health":
            self._json_response(200, {
                "status": "ok",
                "network": "local",
                "version": "0.4.0",
                "evm_network": "local",
                "uptime_seconds": 42,
                "build_commit": "abcdef123456",
                "payment_token_address": "0xtoken",
                "payment_vault_address": "0xvault",
            })

        elif path.startswith("/v1/data/public/"):
            addr = path.split("/v1/data/public/")[1]
            self._json_response(200, {"data": _b64(f"public-{addr}".encode())})

        elif path.startswith("/v1/chunks/"):
            addr = path.split("/v1/chunks/")[1]
            self._json_response(200, {"data": _b64(f"chunk-{addr}".encode())})

        elif path == "/v1/wallet/address":
            self._json_response(200, {"address": "0xABCDEF1234567890"})

        elif path == "/v1/wallet/balance":
            self._json_response(200, {"balance": "1000000", "gas_balance": "500000"})

        elif path == "/error/404":
            self._json_response(404, {"error": "not found"})

        elif path == "/error/400":
            self._json_response(400, {"error": "bad request"})

        elif path == "/error/502":
            self._json_response(502, {"error": "bad gateway"})

        elif path == "/error/502-network":
            # A 502 with a non-partial code keeps the plain NetworkError mapping.
            self._json_response(502, {"error": "upstream unreachable", "code": "NETWORK_ERROR"})

        else:
            self._json_response(404, {"error": f"unknown route: {path}"})

    # --- POST routes ---

    def do_POST(self):  # noqa: N802
        body = self._read_body()
        req_json: dict = json.loads(body) if body else {}
        path = self.path

        # Capture payment_mode for assertion in TestPaymentModeWiring.
        if "payment_mode" in req_json:
            self.server._last_payment_modes[path] = req_json["payment_mode"]

        if path == "/v1/data/public":
            self._json_response(200, {
                "address": "abc123",
                "chunks_stored": 3,
                "payment_mode_used": "auto",
            })

        elif path == "/v1/data":
            self._json_response(200, {
                "data_map": "dm_xyz",
                "chunks_stored": 2,
                "payment_mode_used": "merkle",
            })

        elif path == "/v1/data/stream":
            # NDJSON progress framing when the caller opts in via Accept; the
            # default raw path isn't exercised here (httpx streams it verbatim).
            if "application/x-ndjson" in self.headers.get("Accept", ""):
                self._ndjson_response([
                    {"type": "meta", "total_size": 6},
                    {"type": "progress", "phase": "fetching", "fetched": 1, "total": 2},
                    {"type": "data", "chunk": _b64(b"sec")},
                    {"type": "progress", "phase": "fetching", "fetched": 2, "total": 2},
                    {"type": "data", "chunk": _b64(b"ret")},
                ])
            else:
                self._json_response(400, {"error": "expected ndjson"})

        elif path == "/v1/data/get":
            self._json_response(200, {"data": _b64(b"private-payload")})

        elif path == "/v1/data/cost":
            self._json_response(200, {
                "cost": "99",
                "file_size": 4,
                "chunk_count": 3,
                "estimated_gas_cost_wei": "150000000000000",
                "payment_mode": "single",
            })

        elif path == "/v1/files":
            self._json_response(200, {
                "data_map": "file_dm_1",
                "storage_cost_atto": "500",
                "gas_cost_wei": "21",
                "chunks_stored": 2,
                "payment_mode_used": "single",
            })

        elif path == "/v1/files/get":
            self._json_response(200, {})

        elif path == "/v1/files/public":
            self._json_response(200, {
                "address": "file_addr_1",
                "storage_cost_atto": "1000",
                "gas_cost_wei": "42",
                "chunks_stored": 3,
                "payment_mode_used": "auto",
            })

        elif path == "/v1/files/public/get":
            self._json_response(200, {})

        elif path == "/v1/files/cost":
            self._json_response(200, {
                "cost": "1000",
                "file_size": 4096,
                "chunk_count": 3,
                "estimated_gas_cost_wei": "150000000000000",
                "payment_mode": "auto",
            })

        elif path == "/v1/chunks":
            self._json_response(200, {"cost": "10", "address": "chunk_addr_1"})

        elif path == "/v1/wallet/approve":
            self._json_response(200, {"approved": True})

        elif path == "/v1/upload/prepare":
            req = json.loads(body) if body else {}
            # Stash the body so tests can assert visibility was forwarded.
            self.server._last_prepare_request = req
            # Return merkle response when path contains "merkle", else wave_batch
            if "merkle" in req.get("path", ""):
                self._json_response(200, {
                    "upload_id": "up_merkle_1",
                    "payment_type": "merkle_batch",
                    "payments": [],
                    "total_amount": "5000",
                    "payment_vault_address": "0xMERKLE",
                    "payment_token_address": "0xTK",
                    "rpc_url": "http://rpc.local",
                    "depth": 3,
                    "pool_commitments": [
                        {
                            "pool_hash": "pool_abc",
                            "candidates": [
                                {"rewards_address": "0xR1", "amount": "2000"},
                                {"rewards_address": "0xR2", "amount": "3000"},
                            ],
                        },
                    ],
                    "merkle_payment_timestamp": 1700000000,
                    "total_chunks": 128,
                    "already_stored_count": 0,
                })
            elif "compat" in req.get("path", ""):
                # Backward compat: no payment_type field
                self._json_response(200, {
                    "upload_id": "up_compat_1",
                    "payments": [
                        {"quote_hash": "qh1", "rewards_address": "0xR1", "amount": "100"},
                    ],
                    "total_amount": "100",
                    "payment_vault_address": "0xDP",
                    "payment_token_address": "0xTK",
                    "rpc_url": "http://rpc.local",
                })
            else:
                self._json_response(200, {
                    "upload_id": "up_wave_1",
                    "payment_type": "wave_batch",
                    "payments": [
                        {"quote_hash": "qh1", "rewards_address": "0xR1", "amount": "100"},
                    ],
                    "total_amount": "100",
                    "payment_vault_address": "0xDP",
                    "payment_token_address": "0xTK",
                    "rpc_url": "http://rpc.local",
                    "total_chunks": 3,
                    "already_stored_count": 1,
                })

        elif path == "/v1/upload/finalize":
            req = json.loads(body) if body else {}
            # Store the request so tests can inspect it
            self.server._last_finalize_request = req
            # Malformed 502 bodies registered by a test, sent verbatim.
            raw = self.server._raw_finalize_bodies.get(req.get("upload_id"))
            if raw is not None:
                self._raw_response(502, raw)
                return
            # PARTIAL_UPLOAD: 502 whose body carries the machine-readable code
            # and counts. "partial" mimics antd >= 0.14.0 (paid attempt
            # retained, `retryable: true`); "partial-legacy" mimics an older
            # daemon that never sends `retryable`.
            if req.get("upload_id") in ("partial", "partial-legacy"):
                retained = req["upload_id"] == "partial"
                hint = (
                    "paid attempt retained: call finalize again with the same "
                    "upload_id to store the remainder against the same payment"
                    if retained else
                    "stored chunks persist; re-prepare the same content to retry "
                    "only the remainder"
                )
                err = {
                    "error": f"Partial upload: 300/312 chunks stored, 12 failed after retries: quorum ({hint})",
                    "code": "PARTIAL_UPLOAD",
                    "chunks_stored": 300,
                    "chunks_failed": 12,
                    "total_chunks": 312,
                }
                if retained:
                    err["retryable"] = True
                self._json_response(502, err)
                return
            # Echo a data_map_address when the prior prepare was public.
            last_prepare = getattr(self.server, "_last_prepare_request", {}) or {}
            resp_body: dict = {
                "address": "0xFINAL",
                "chunks_stored": 42,
                "data_map": "deadbeef",
            }
            if last_prepare.get("visibility") == "public":
                resp_body["data_map_address"] = "0xDMAP"
            self._json_response(200, resp_body)

        elif path == "/v1/chunks/prepare":
            req = json.loads(body) if body else {}
            data_b64 = req.get("data", "")
            # Decide already_stored vs needs-payment by the decoded prefix —
            # lets the same handler cover both branches.
            decoded = base64.b64decode(data_b64) if data_b64 else b""
            if decoded.startswith(b"already_"):
                self._json_response(200, {
                    "address": "addr_already_stored",
                    "already_stored": True,
                })
            else:
                self._json_response(200, {
                    "address": "addr_chunk_new",
                    "already_stored": False,
                    "upload_id": "chunk_up_1",
                    "payment_type": "wave_batch",
                    "payments": [
                        {"quote_hash": "qhC", "rewards_address": "0xRC", "amount": "7"},
                    ],
                    "total_amount": "7",
                    "payment_vault_address": "0xVC",
                    "payment_token_address": "0xTC",
                    "rpc_url": "http://rpc.local",
                })

        elif path == "/v1/chunks/finalize":
            req = json.loads(body) if body else {}
            self.server._last_chunk_finalize_request = req
            self._json_response(200, {"address": "addr_chunk_new"})

        else:
            self._json_response(404, {"error": f"unknown route: {path}"})


@pytest.fixture(scope="module")
def mock_server():
    """Start a local HTTP server on an ephemeral port for the test module."""
    server = HTTPServer(("127.0.0.1", 0), _MockHandler)
    server._last_payment_modes = {}
    server._raw_finalize_bodies = {}
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield server
    server.shutdown()


@pytest.fixture(scope="module")
def client(mock_server):
    """Create a RestClient pointed at the mock server."""
    host, port = mock_server.server_address
    url = f"http://{host}:{port}"
    c = RestClient(base_url=url, timeout=5.0)
    yield c
    c.close()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestHealth:
    def test_returns_health_status(self, client: RestClient):
        status = client.health()
        assert isinstance(status, HealthStatus)
        assert status.ok is True
        assert status.network == "local"
        assert status.version == "0.4.0"
        assert status.evm_network == "local"
        assert status.uptime_seconds == 42
        assert status.build_commit == "abcdef123456"
        assert status.payment_token_address == "0xtoken"
        assert status.payment_vault_address == "0xvault"

    def test_pre_0_4_0_daemon_leaves_diagnostics_empty(self, client: RestClient):
        # Older daemons reply with just status + network. The dataclass
        # defaults make this case still parse cleanly.
        from antd._rest import _health_status_from_json
        s = _health_status_from_json({"status": "ok", "network": "default"})
        assert s.ok is True and s.network == "default"
        assert s.version == ""
        assert s.uptime_seconds == 0


class TestDataPutPublic:
    def test_returns_put_result(self, client: RestClient):
        result = client.data_put_public(b"hello world", PaymentMode.AUTO)
        assert isinstance(result, DataPutPublicResult)
        assert result.address == "abc123"
        assert result.chunks_stored == 3
        assert result.payment_mode_used == "auto"


class TestDataGetPublic:
    def test_returns_decoded_bytes(self, client: RestClient):
        data = client.data_get_public("myaddr")
        assert data == b"public-myaddr"


class TestDataPut:
    def test_returns_data_put_result(self, client: RestClient):
        result = client.data_put(b"secret data", PaymentMode.MERKLE)
        assert isinstance(result, DataPutResult)
        assert result.data_map == "dm_xyz"
        assert result.chunks_stored == 2
        assert result.payment_mode_used == "merkle"


class TestDataGet:
    def test_returns_decoded_bytes(self, client: RestClient):
        data = client.data_get("some_data_map")
        assert data == b"private-payload"


class TestDataCost:
    def test_returns_full_breakdown(self, client: RestClient):
        est = client.data_cost(b"estimate me", PaymentMode.SINGLE)
        assert est.cost == "99"
        assert est.file_size == 4
        assert est.chunk_count == 3
        assert est.estimated_gas_cost_wei == "150000000000000"
        assert est.payment_mode == "single"


class TestFiles:
    def test_file_put_returns_data_map(self, client: RestClient):
        result = client.file_put("/tmp/test.txt", PaymentMode.SINGLE)
        assert isinstance(result, FilePutResult)
        assert result.data_map == "file_dm_1"
        assert result.storage_cost_atto == "500"
        assert result.chunks_stored == 2
        assert result.payment_mode_used == "single"

    def test_file_get_succeeds(self, client: RestClient):
        # Returns None on success; raises on failure.
        client.file_get("file_dm_1", "/tmp/out.txt")

    def test_file_put_public_returns_address(self, client: RestClient):
        result = client.file_put_public("/tmp/test.txt", PaymentMode.AUTO)
        assert isinstance(result, FilePutPublicResult)
        assert result.address == "file_addr_1"
        assert result.storage_cost_atto == "1000"
        assert result.chunks_stored == 3
        assert result.payment_mode_used == "auto"

    def test_file_get_public_succeeds(self, client: RestClient):
        client.file_get_public("file_addr_1", "/tmp/out.txt")

    def test_file_cost(self, client: RestClient):
        est = client.file_cost("/tmp/test.txt", is_public=True, payment_mode=PaymentMode.AUTO)
        assert est.cost == "1000"
        assert est.chunk_count == 3


class TestPaymentModeWiring:
    """Assert the PaymentMode enum reaches the REST `payment_mode` body field
    on every put/cost endpoint."""

    def test_payment_mode_wires_into_request_body(self, client: RestClient, mock_server):
        mock_server._last_payment_modes.clear()
        client.data_put(b"x", PaymentMode.MERKLE)
        client.data_put_public(b"x", PaymentMode.SINGLE)
        client.data_cost(b"x", PaymentMode.AUTO)
        client.file_put("/tmp/x", PaymentMode.MERKLE)
        client.file_put_public("/tmp/x", PaymentMode.SINGLE)
        client.file_cost("/tmp/x", is_public=False, payment_mode=PaymentMode.AUTO)

        seen = mock_server._last_payment_modes
        assert seen["/v1/data"] == "merkle"
        assert seen["/v1/data/public"] == "single"
        assert seen["/v1/data/cost"] == "auto"
        assert seen["/v1/files"] == "merkle"
        assert seen["/v1/files/public"] == "single"
        assert seen["/v1/files/cost"] == "auto"


class TestChunkRoundTrip:
    def test_chunk_put(self, client: RestClient):
        result = client.chunk_put(b"chunk data")
        assert isinstance(result, PutResult)
        assert result.cost == "10"
        assert result.address == "chunk_addr_1"

    def test_chunk_get(self, client: RestClient):
        data = client.chunk_get("chunk_addr_1")
        assert data == b"chunk-chunk_addr_1"


class TestWalletAddress:
    def test_returns_wallet_address(self, client: RestClient):
        wa = client.wallet_address()
        assert isinstance(wa, WalletAddress)
        assert wa.address == "0xABCDEF1234567890"


class TestWalletBalance:
    def test_returns_wallet_balance(self, client: RestClient):
        wb = client.wallet_balance()
        assert isinstance(wb, WalletBalance)
        assert wb.balance == "1000000"
        assert wb.gas_balance == "500000"


class TestWalletApprove:
    def test_returns_true(self, client: RestClient):
        assert client.wallet_approve() is True


class TestPrepareUploadMerkle:
    """Verify merkle_batch prepare_upload response is parsed correctly."""

    def test_prepare_upload_merkle(self, client: RestClient):
        result = client.prepare_upload("/tmp/merkle/file.dat")
        assert isinstance(result, PrepareUploadResult)
        assert result.upload_id == "up_merkle_1"
        assert result.payment_type == "merkle_batch"
        assert result.depth == 3
        assert result.total_amount == "5000"
        assert result.merkle_payment_timestamp == 1700000000
        assert result.payment_vault_address == "0xMERKLE"
        # pool_commitments
        assert len(result.pool_commitments) == 1
        pc = result.pool_commitments[0]
        assert isinstance(pc, PoolCommitmentEntry)
        assert pc.pool_hash == "pool_abc"
        assert len(pc.candidates) == 2
        assert isinstance(pc.candidates[0], CandidateNodeEntry)
        assert pc.candidates[0].rewards_address == "0xR1"
        assert pc.candidates[0].amount == "2000"
        assert pc.candidates[1].rewards_address == "0xR2"
        assert pc.candidates[1].amount == "3000"
        # payments list should be empty for merkle
        assert result.payments == []
        # already-stored preflight (added in antd 0.10.0)
        assert result.total_chunks == 128
        assert result.already_stored_count == 0


class TestFinalizeMerkleUpload:
    """Verify finalize_merkle_upload sends winner_pool_hash."""

    def test_finalize_merkle_upload(self, client: RestClient, mock_server):
        result = client.finalize_merkle_upload(
            upload_id="up_merkle_1",
            winner_pool_hash="pool_abc",
            store_data_map=True,
        )
        assert isinstance(result, FinalizeUploadResult)
        assert result.address == "0xFINAL"
        assert result.chunks_stored == 42
        # Verify the request body sent to the server
        req = mock_server._last_finalize_request
        assert req["upload_id"] == "up_merkle_1"
        assert req["winner_pool_hash"] == "pool_abc"
        assert req["store_data_map"] is True


class TestPrepareUploadBackwardCompat:
    """Verify missing payment_type defaults to wave_batch."""

    def test_prepare_upload_backward_compat(self, client: RestClient):
        result = client.prepare_upload("/tmp/compat/file.dat")
        assert isinstance(result, PrepareUploadResult)
        assert result.upload_id == "up_compat_1"
        assert result.payment_type == "wave_batch"
        assert result.depth == 0
        assert result.pool_commitments == []
        assert result.merkle_payment_timestamp == 0
        assert result.payment_vault_address == "0xDP"
        # wave_batch payments should still be parsed
        assert len(result.payments) == 1
        assert result.payments[0].quote_hash == "qh1"
        # preflight fields absent in older-daemon responses default to 0
        assert result.total_chunks == 0
        assert result.already_stored_count == 0


class TestPrepareUploadPublic:
    """Verify visibility="public" is forwarded and data_map_address surfaces on finalize."""

    def test_prepare_upload_public_forwards_visibility(self, client: RestClient, mock_server):
        result = client.prepare_upload_public("/tmp/wave/file.dat")
        assert isinstance(result, PrepareUploadResult)
        assert result.upload_id == "up_wave_1"
        # Mock daemon should have seen visibility="public" in the request body.
        assert mock_server._last_prepare_request["visibility"] == "public"

    def test_prepare_upload_with_visibility_arg(self, client: RestClient, mock_server):
        client.prepare_upload("/tmp/wave/file.dat", visibility="private")
        assert mock_server._last_prepare_request["visibility"] == "private"

    def test_prepare_upload_without_visibility_omits_field(self, client: RestClient, mock_server):
        client.prepare_upload("/tmp/wave/file.dat")
        # No visibility key — preserves the pre-public daemon wire shape.
        assert "visibility" not in mock_server._last_prepare_request

    def test_finalize_surfaces_data_map_address_for_public_upload(
        self, client: RestClient, mock_server,
    ):
        client.prepare_upload_public("/tmp/wave/file.dat")
        result = client.finalize_upload(
            upload_id="up_wave_1",
            tx_hashes={"qh1": "tx1"},
        )
        assert result.address == "0xFINAL"
        assert result.data_map == "deadbeef"
        assert result.data_map_address == "0xDMAP"

    def test_finalize_omits_data_map_address_for_private_upload(
        self, client: RestClient, mock_server,
    ):
        client.prepare_upload("/tmp/wave/file.dat")  # no visibility → private
        result = client.finalize_upload(
            upload_id="up_wave_1",
            tx_hashes={"qh1": "tx1"},
        )
        assert result.data_map_address == ""


class TestPrepareChunkUpload:
    def test_already_stored_omits_payment_fields(self, client: RestClient):
        result = client.prepare_chunk_upload(b"already_chunk_data")
        assert isinstance(result, PrepareChunkResult)
        assert result.address == "addr_already_stored"
        assert result.already_stored is True
        assert result.upload_id == ""
        assert result.payments == []
        assert result.total_amount == ""

    def test_new_chunk_returns_wave_batch_intent(self, client: RestClient):
        result = client.prepare_chunk_upload(b"new_chunk_data")
        assert result.already_stored is False
        assert result.address == "addr_chunk_new"
        assert result.upload_id == "chunk_up_1"
        assert result.payment_type == "wave_batch"
        assert len(result.payments) == 1
        assert result.payments[0].quote_hash == "qhC"
        assert result.payments[0].amount == "7"
        assert result.total_amount == "7"
        assert result.payment_vault_address == "0xVC"
        assert result.payment_token_address == "0xTC"
        assert result.rpc_url == "http://rpc.local"


class TestFinalizeChunkUpload:
    def test_returns_address_and_forwards_tx_hashes(self, client: RestClient, mock_server):
        addr = client.finalize_chunk_upload(
            upload_id="chunk_up_1",
            tx_hashes={"qhC": "tx_C"},
        )
        assert addr == "addr_chunk_new"
        req = mock_server._last_chunk_finalize_request
        assert req["upload_id"] == "chunk_up_1"
        assert req["tx_hashes"] == {"qhC": "tx_C"}


class TestErrorMapping:
    """Verify HTTP status codes are mapped to the correct exception types."""

    def test_404_raises_not_found(self, client: RestClient):
        from antd._rest import _check
        resp = client._http.get("/error/404")
        with pytest.raises(NotFoundError) as exc_info:
            _check(resp)
        assert exc_info.value.status_code == 404
        assert "not found" in str(exc_info.value)

    def test_400_raises_bad_request(self, client: RestClient):
        from antd._rest import _check
        resp = client._http.get("/error/400")
        with pytest.raises(BadRequestError) as exc_info:
            _check(resp)
        assert exc_info.value.status_code == 400
        assert "bad request" in str(exc_info.value)

    def test_502_raises_network_error(self, client: RestClient):
        from antd._rest import _check
        resp = client._http.get("/error/502")
        with pytest.raises(NetworkError) as exc_info:
            _check(resp)
        assert exc_info.value.status_code == 502
        assert "bad gateway" in str(exc_info.value)

    def test_502_with_other_code_still_raises_network_error(self, client: RestClient):
        from antd._rest import _check
        resp = client._http.get("/error/502-network")
        with pytest.raises(NetworkError) as exc_info:
            _check(resp)
        assert not isinstance(exc_info.value, PartialUploadError)
        assert exc_info.value.status_code == 502

    def test_502_partial_upload_via_streamed_check(self, client: RestClient):
        from antd._rest import _check_streamed
        with client._http.stream(
            "POST", "/v1/upload/finalize", json={"upload_id": "partial", "tx_hashes": {}},
        ) as resp:
            with pytest.raises(PartialUploadError) as exc_info:
                _check_streamed(resp)
        assert exc_info.value.chunks_failed == 12
        assert exc_info.value.retryable is True


class TestPartialUpload:
    """PARTIAL_UPLOAD (502 + `code`) surfaces as a typed error with counts."""

    def test_finalize_upload_carries_counts_and_retryable(self, client: RestClient):
        with pytest.raises(PartialUploadError) as exc_info:
            client.finalize_upload("partial", {"0xq1": "0xtx1"})
        err = exc_info.value
        assert err.status_code == 502
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (300, 12, 312)
        assert err.retryable is True
        assert str(err).startswith("Partial upload: 300/312 chunks stored, 12 failed")

    def test_finalize_merkle_upload_retryable_defaults_false(self, client: RestClient):
        # An older daemon (< 0.14.0) never sends `retryable`; the flag must
        # read False so callers fall back to the re-prepare path rather than
        # looping on an upload_id the daemon has already dropped.
        with pytest.raises(PartialUploadError) as exc_info:
            client.finalize_merkle_upload("partial-legacy", "0xw1")
        err = exc_info.value
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (300, 12, 312)
        assert err.retryable is False

    def test_is_a_network_error(self, client: RestClient):
        # Existing `except NetworkError` / `except AntdError` blocks keep
        # catching the 502 -- the subclass only adds detail.
        with pytest.raises(NetworkError):
            client.finalize_upload("partial", {})


# A well-formed PARTIAL_UPLOAD body as JSON text, with one field replaced by a
# raw JSON literal. Text rather than a dict so the literals json.dumps cannot
# produce (bare Infinity, over-long integers) reach the client verbatim.
_PARTIAL_FIELDS = {
    "error": '"Partial upload: 300/312 chunks stored, 12 failed after retries: quorum"',
    "code": '"PARTIAL_UPLOAD"',
    "chunks_stored": "300",
    "chunks_failed": "12",
    "total_chunks": "312",
    "retryable": "true",
}


def _partial_body(**overrides: str) -> bytes:
    fields = {**_PARTIAL_FIELDS, **overrides}
    return ("{" + ", ".join(f'"{k}": {v}' for k, v in fields.items()) + "}").encode()


def _finalize_raw(client: RestClient, mock_server, upload_id: str, raw: bytes):
    """Finalize against a mock 502 whose body is ``raw``; return what it raised."""
    mock_server._raw_finalize_bodies[upload_id] = raw
    with pytest.raises(NetworkError) as exc_info:
        client.finalize_upload(upload_id, {"0xq1": "0xtx1"})
    return exc_info.value


_COUNT_FIELDS = ("chunks_stored", "chunks_failed", "total_chunks")
_WELL_FORMED_COUNTS = {"chunks_stored": 300, "chunks_failed": 12, "total_chunks": 312}


def _int_digit_limit_applies(digits: int) -> bool:
    """True when this interpreter refuses ``int()`` of ``digits`` decimal
    digits, and so ``json.loads`` of such an integer: the 4300-digit default
    on Python >= 3.11 (and 3.10.7+), unless disabled."""
    get_limit = getattr(sys, "get_int_max_str_digits", None)
    if get_limit is None:
        return False
    limit = get_limit()
    return limit != 0 and digits > limit


class TestMalformedPartialUploadBody:
    """A malformed 502 PARTIAL_UPLOAD body read through the real client: a
    count that is not a non-negative JSON integer (<= u64 max) reads as 0,
    `retryable` needs the JSON literal `true`, `code` must be the exact
    string, and nothing escapes as a raw ValueError / TypeError /
    OverflowError. At worst the status mapping (502 -> NetworkError) applies."""

    @pytest.mark.parametrize("field", _COUNT_FIELDS)
    @pytest.mark.parametrize(
        "literal",
        ['"1"', "true", "1.5", "-1", "[]", "{}", "18446744073709551616", "Infinity", "NaN", "null"],
    )
    def test_malformed_count_reads_zero(self, client, mock_server, field, literal):
        err = _finalize_raw(client, mock_server, f"bad-{field}-{literal}", _partial_body(**{field: literal}))
        assert isinstance(err, PartialUploadError)
        assert {f: getattr(err, f) for f in _COUNT_FIELDS} == {**_WELL_FORMED_COUNTS, field: 0}
        assert err.retryable is True
        assert err.status_code == 502

    def test_u64_max_count_is_kept(self, client, mock_server):
        err = _finalize_raw(
            client, mock_server, "u64-max", _partial_body(chunks_failed="18446744073709551615"),
        )
        assert isinstance(err, PartialUploadError)
        assert err.chunks_failed == 18446744073709551615

    @pytest.mark.parametrize("literal", ['"true"', '"false"', "1", "{}", "null", "false"])
    def test_retryable_needs_json_true(self, client, mock_server, literal):
        err = _finalize_raw(client, mock_server, f"retryable-{literal}", _partial_body(retryable=literal))
        assert isinstance(err, PartialUploadError)
        assert err.retryable is False
        assert {f: getattr(err, f) for f in _COUNT_FIELDS} == _WELL_FORMED_COUNTS

    @pytest.mark.parametrize("literal", ["{}", "[]", "null", "1", '"partial_upload"'])
    def test_code_must_be_the_exact_string(self, client, mock_server, literal):
        raw = _partial_body(code=literal)
        err = _finalize_raw(client, mock_server, f"code-{literal}", raw)
        assert type(err) is NetworkError
        assert err.status_code == 502
        assert str(err).startswith("Partial upload: 300/312")

    def test_top_level_array_body_is_network_error(self, client, mock_server):
        err = _finalize_raw(client, mock_server, "array-body", b"[]")
        assert type(err) is NetworkError
        assert str(err) == "[]"

    def test_non_string_error_uses_raw_body_as_message(self, client, mock_server):
        raw = _partial_body(error="{}")
        err = _finalize_raw(client, mock_server, "error-object", raw)
        assert isinstance(err, PartialUploadError)
        assert str(err) == raw.decode()
        assert {f: getattr(err, f) for f in _COUNT_FIELDS} == _WELL_FORMED_COUNTS
        assert err.retryable is True

    def test_over_long_integer_never_escapes(self, client, mock_server):
        raw = _partial_body(chunks_failed="9" * 5000)
        err = _finalize_raw(client, mock_server, "huge-int", raw)
        assert err.status_code == 502
        if _int_digit_limit_applies(5000):
            # json.loads refuses it, so the body is unreadable and the status
            # mapping applies.
            assert type(err) is NetworkError
        else:
            # Decoded, but far above u64 max: the count reads as 0.
            assert isinstance(err, PartialUploadError)
            assert err.chunks_failed == 0

    def test_everything_malformed_at_once(self, client, mock_server):
        raw = _partial_body(
            error="{}", chunks_stored='"300"', chunks_failed="Infinity",
            total_chunks="[312]", retryable='"true"',
        )
        err = _finalize_raw(client, mock_server, "all-bad", raw)
        assert isinstance(err, PartialUploadError)
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks, err.retryable) == (0, 0, 0, False)
        assert str(err) == raw.decode()

    def test_check_directly(self, client, mock_server):
        mock_server._raw_finalize_bodies["direct"] = _partial_body(chunks_stored="Infinity", error="{}")
        resp = client._http.post("/v1/upload/finalize", json={"upload_id": "direct", "tx_hashes": {}})
        with pytest.raises(PartialUploadError) as exc_info:
            _check(resp)
        assert exc_info.value.chunks_stored == 0
        assert exc_info.value.chunks_failed == 12

    def test_streamed_check(self, client, mock_server):
        from antd._rest import _check_streamed
        mock_server._raw_finalize_bodies["streamed"] = _partial_body(
            chunks_failed="[12]", retryable='"true"',
        )
        with client._http.stream(
            "POST", "/v1/upload/finalize", json={"upload_id": "streamed", "tx_hashes": {}},
        ) as resp:
            with pytest.raises(PartialUploadError) as exc_info:
                _check_streamed(resp)
        assert (exc_info.value.chunks_failed, exc_info.value.retryable) == (0, False)

    @pytest.mark.asyncio
    async def test_async_streamed_check(self):
        raw = _partial_body(total_chunks="-1", error="{}")

        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(502, content=raw, headers={"content-type": "application/json"})

        async with httpx.AsyncClient(
            base_url="http://antd.test", transport=httpx.MockTransport(handler),
        ) as http:
            async with http.stream("POST", "/v1/upload/finalize") as resp:
                with pytest.raises(PartialUploadError) as exc_info:
                    await _acheck_streamed(resp)
        assert exc_info.value.total_chunks == 0
        assert exc_info.value.chunks_failed == 12
        assert str(exc_info.value) == raw.decode()


class TestDataStreamWithProgress:
    def test_ndjson_frames_parsed(self, client: RestClient):
        data = bytearray()
        progress = []
        meta = []
        with client.data_stream_with_progress("dm123") as frames:
            for frame in frames:
                if frame.is_meta:
                    meta.append(frame.meta)
                elif frame.is_progress:
                    progress.append(frame.progress)
                else:
                    data.extend(frame.data)
        assert bytes(data) == b"secret"
        assert meta == [6]
        assert len(progress) == 2
        assert progress[0].phase == "fetching"
        assert progress[1].fetched == 2 and progress[1].total == 2

    def test_ndjson_error_frame_raises(self, client: RestClient):
        from antd._rest import _parse_ndjson_frame
        from antd.exceptions import InternalError
        # The terminal error frame must surface mid-stream (a raw octet-stream
        # download cannot signal a failure after the body has started).
        with pytest.raises(InternalError):
            _parse_ndjson_frame('{"type":"error","message":"boom"}')
