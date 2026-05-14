"""Tests for antd._rest.RestClient using a local mock HTTP server."""

from __future__ import annotations

import base64
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from antd._rest import RestClient
from antd.exceptions import BadRequestError, NetworkError, NotFoundError
from antd.models import (
    CandidateNodeEntry,
    FinalizeUploadResult,
    HealthStatus,
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

        elif path == "/v1/data/private":
            # data_map comes as query param
            self._json_response(200, {"data": _b64(b"private-payload")})

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

        else:
            self._json_response(404, {"error": f"unknown route: {path}"})

    # --- POST routes ---

    def do_POST(self):  # noqa: N802
        body = self._read_body()
        path = self.path

        if path == "/v1/data/public":
            self._json_response(200, {"cost": "42", "address": "abc123"})

        elif path == "/v1/data/private":
            self._json_response(200, {"cost": "50", "data_map": "dm_xyz"})

        elif path == "/v1/data/cost":
            self._json_response(200, {
                "cost": "99",
                "file_size": 4,
                "chunk_count": 3,
                "estimated_gas_cost_wei": "150000000000000",
                "payment_mode": "single",
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
                })

        elif path == "/v1/upload/finalize":
            req = json.loads(body) if body else {}
            # Store the request so tests can inspect it
            self.server._last_finalize_request = req
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
        result = client.data_put_public(b"hello world")
        assert isinstance(result, PutResult)
        assert result.cost == "42"
        assert result.address == "abc123"


class TestDataGetPublic:
    def test_returns_decoded_bytes(self, client: RestClient):
        data = client.data_get_public("myaddr")
        assert data == b"public-myaddr"


class TestDataPutPrivate:
    def test_returns_put_result_with_data_map(self, client: RestClient):
        result = client.data_put_private(b"secret data")
        assert isinstance(result, PutResult)
        assert result.cost == "50"
        # data_map is stored in the address field of PutResult
        assert result.address == "dm_xyz"


class TestDataGetPrivate:
    def test_returns_decoded_bytes(self, client: RestClient):
        data = client.data_get_private("some_data_map")
        assert data == b"private-payload"


class TestDataCost:
    def test_returns_full_breakdown(self, client: RestClient):
        est = client.data_cost(b"estimate me")
        assert est.cost == "99"
        assert est.file_size == 4
        assert est.chunk_count == 3
        assert est.estimated_gas_cost_wei == "150000000000000"
        assert est.payment_mode == "single"


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
