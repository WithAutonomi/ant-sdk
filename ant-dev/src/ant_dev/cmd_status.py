"""``ant dev status`` — Show running processes and daemon health."""

from __future__ import annotations

import os
import sys

import httpx

from .env import is_windows, load_state
from .process import is_alive


def _color(code: str, text: str) -> str:
    if is_windows() and "WT_SESSION" not in os.environ:
        return text
    return f"\033[{code}m{text}\033[0m"

green  = lambda t: _color("0;32", t)
red    = lambda t: _color("0;31", t)
cyan   = lambda t: _color("0;36", t)
white  = lambda t: _color("1;37", t)


def run(args) -> None:
    state = load_state()

    if not state:
        print("No local environment running. Use 'ant dev start' to start one.")
        sys.exit(0)

    print()
    print(cyan("=== antd Local Environment Status ==="))
    print()

    # Process status
    processes = [
        ("Ant devnet", "devnet_pid"),
        ("antd daemon", "antd_pid"),
    ]

    for label, key in processes:
        pid = state.get(key, 0)
        alive = is_alive(pid) if pid else False
        status = green("running") if alive else red("stopped")
        print(f"  {label:20s}  PID {pid or '-':>8}  {status}")

    # Health check
    print()
    try:
        r = httpx.get("http://localhost:8082/health", timeout=5)
        data = r.json()
        ok = data.get("status") == "ok" or data.get("ok", False)
        network = data.get("network", "unknown")
        health = green("healthy") if ok else red("unhealthy")
        print(f"  REST health:        {health}")
        print(f"  Network:            {white(network)}")
    except (httpx.HTTPError, OSError):
        print(f"  REST health:        {red('unreachable')}")

    # Wallet key
    if key := state.get("wallet_key"):
        print(f"  Wallet key:         {key[:10]}...")

    print()
