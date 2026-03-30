"""``ant dev wallet [show|fund]`` — Show wallet info or fund the test wallet."""

from __future__ import annotations

import sys

import httpx

from .env import load_state

DEFAULT_REST_URL = "http://localhost:8082"

def _discover_rest_url() -> str:
    """Try to discover antd REST URL via port file, fall back to default."""
    try:
        from antd import discover_daemon_url
        url = discover_daemon_url()
        if url:
            return url
    except ImportError:
        pass
    return DEFAULT_REST_URL


def run(args) -> None:
    state = load_state()
    action = args.action
    rest_url = _discover_rest_url()

    if action == "show":
        if not state.get("wallet_configured"):
            print("No wallet configured. Is the local environment running?")
            print("  ant dev start")
            sys.exit(1)
        # Query wallet address and balance from antd (never display the key)
        try:
            addr_resp = httpx.get(f"{rest_url}/v1/wallet/address", timeout=5)
            bal_resp = httpx.get(f"{rest_url}/v1/wallet/balance", timeout=5)
            if addr_resp.status_code == 200 and bal_resp.status_code == 200:
                address = addr_resp.json().get("address", "unknown")
                balance = bal_resp.json().get("balance", "unknown")
                gas = bal_resp.json().get("gas_balance", "unknown")
                print(f"Address:     {address}")
                print(f"Balance:     {balance} atto")
                print(f"Gas balance: {gas} wei")
            else:
                print("Wallet not available. Is antd running with AUTONOMI_WALLET_KEY?")
                sys.exit(1)
        except (httpx.HTTPError, OSError):
            print("Cannot reach antd daemon. Is it running?")
            sys.exit(1)

    elif action == "fund":
        if not state.get("wallet_configured"):
            print("No wallet configured. Start the environment first.")
            sys.exit(1)
        # On local testnet the EVM testnet already funds this key.
        try:
            rest_url = _discover_rest_url()
            r = httpx.get(f"{rest_url}/health", timeout=5)
            data = r.json()
            if data.get("status") == "ok" or data.get("ok", False):
                print("Wallet is already funded on local testnet.")
            else:
                print("Daemon is not healthy. Check: ant dev status")
        except (httpx.HTTPError, OSError):
            print("Cannot reach antd daemon. Is it running?")
            sys.exit(1)
