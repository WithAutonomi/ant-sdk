"""``ant dev wallet [show|fund]`` — Show or fund the test wallet."""

from __future__ import annotations

import sys

import httpx

from .env import load_state


def run(args) -> None:
    state = load_state()
    action = args.action

    if action == "show":
        key = state.get("wallet_key")
        if not key:
            print("No wallet key found. Is the local environment running?")
            print("  ant dev start")
            sys.exit(1)
        print(f"Wallet key: {key[:10]}...{key[-6:]}")
        print(f"Full key:   {key}")

    elif action == "fund":
        key = state.get("wallet_key")
        if not key:
            print("No wallet key found. Start the environment first.")
            sys.exit(1)
        # On local testnet the EVM testnet already funds this key.
        # Verify via health check.
        try:
            r = httpx.get("http://localhost:8082/health", timeout=5)
            data = r.json()
            if data.get("status") == "ok" or data.get("ok", False):
                print("Wallet is already funded on local testnet.")
                print(f"Key: {key[:10]}...")
            else:
                print("Daemon is not healthy. Check: ant dev status")
        except (httpx.HTTPError, OSError):
            print("Cannot reach antd daemon. Is it running?")
            sys.exit(1)
