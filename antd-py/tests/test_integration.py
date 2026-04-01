"""Integration tests for antd RestClient against a live antd daemon.

Requires a running antd daemon (local mode, no wallet/peers).
Set ANTD_TEST_URL to override the default endpoint.

All tests are skipped if the daemon is unreachable.
"""

from __future__ import annotations

import os

import httpx
import pytest

from antd._rest import RestClient
from antd.exceptions import (
    AntdError,
    BadRequestError,
    NotFoundError,
    ServiceUnavailableError,
)

ANTD_TEST_URL = os.environ.get("ANTD_TEST_URL", "http://127.0.0.1:51105")


@pytest.fixture(scope="module")
def client():
    """Create a RestClient; skip the entire module if the daemon is unreachable."""
    c = RestClient(base_url=ANTD_TEST_URL, timeout=10.0)
    try:
        c.health()
    except (httpx.ConnectError, httpx.TimeoutException, OSError):
        c.close()
        pytest.skip(f"antd daemon not reachable at {ANTD_TEST_URL}")
    yield c
    c.close()


class TestHealth:
    def test_health_ok(self, client: RestClient):
        status = client.health()
        assert status.ok is True
        assert status.network == "local"


class TestDataGetPublic:
    def test_invalid_hex_raises_bad_request(self, client: RestClient):
        with pytest.raises(BadRequestError):
            client.data_get_public("invalid")

    def test_valid_hex_not_stored_raises_not_found(self, client: RestClient):
        fake_addr = "aa" * 32
        with pytest.raises((NotFoundError, AntdError)):
            client.data_get_public(fake_addr)


class TestDataPutPublic:
    def test_no_wallet_raises_service_unavailable(self, client: RestClient):
        with pytest.raises(ServiceUnavailableError):
            client.data_put_public(b"hello integration test")


class TestWallet:
    def test_wallet_address_raises_service_unavailable(self, client: RestClient):
        with pytest.raises(ServiceUnavailableError):
            client.wallet_address()

    def test_wallet_balance_raises_service_unavailable(self, client: RestClient):
        with pytest.raises(ServiceUnavailableError):
            client.wallet_balance()


class TestDataCost:
    def test_no_peers_raises_error(self, client: RestClient):
        with pytest.raises(AntdError):
            client.data_cost(b"cost estimate test")
