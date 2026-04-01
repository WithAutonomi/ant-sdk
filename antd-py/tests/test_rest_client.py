"""Tests for antd._rest.RestClient using a local mock HTTP server."""

from __future__ import annotations

import base64
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from antd._rest import RestClient
from antd.exceptions import BadRequestError, NetworkError, NotFoundError
from antd.models import HealthStatus, PutResult, WalletAddress, WalletBalance


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
            self._json_response(200, {"status": "ok", "network": "local"})

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
            self._json_response(200, {"cost": "99"})

        elif path == "/v1/chunks":
            self._json_response(200, {"cost": "10", "address": "chunk_addr_1"})

        elif path == "/v1/wallet/approve":
            self._json_response(200, {"approved": True})

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
    def test_returns_cost_string(self, client: RestClient):
        cost = client.data_cost(b"estimate me")
        assert cost == "99"


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
