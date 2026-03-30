"""``ant dev start`` — Start ant devnet + antd daemon.

Starts a local ant-devnet (replacing the old EVM testnet + antctl flow)
and then launches the antd gateway daemon pointed at it.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

from .env import (
    DEVNET_MANIFEST,
    find_ant_node_dir,
    find_sdk_root,
    is_windows,
    LOG_FILE,
    save_state,
    STATE_DIR,
)
from .process import start_process, wait_for_http

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


# ── ANSI colours (disabled on Windows without VT support) ──

def _color(code: str, text: str) -> str:
    if is_windows() and "WT_SESSION" not in os.environ:
        return text
    return f"\033[{code}m{text}\033[0m"

cyan    = lambda t: _color("0;36", t)
yellow  = lambda t: _color("1;33", t)
green   = lambda t: _color("0;32", t)
red     = lambda t: _color("0;31", t)
gray    = lambda t: _color("0;90", t)
white   = lambda t: _color("1;37", t)


def run(args) -> None:
    ant_node_dir = Path(args.ant_node_dir) if getattr(args, "ant_node_dir", None) else find_ant_node_dir()
    sdk_root = find_sdk_root()
    antd_dir = sdk_root / "antd"
    no_build = getattr(args, "no_build", False)
    enable_evm = getattr(args, "enable_evm", False)

    STATE_DIR.mkdir(parents=True, exist_ok=True)

    devnet_log = STATE_DIR / "devnet.log"

    # Clean old logs and manifest
    for f in (devnet_log, LOG_FILE, DEVNET_MANIFEST):
        if f.exists():
            f.unlink()

    print()
    print(cyan("=== antd Local Test Environment ==="))
    print()

    # ── 1. Start ant-devnet ──
    print(yellow("[1/3] Starting ant devnet..."))

    devnet_cmd = [
        "cargo", "run", "--release", "--bin", "ant-devnet", "--",
        "--preset", "default",
        "--enable-evm",
        "--manifest", str(DEVNET_MANIFEST),
    ]

    devnet_proc = start_process(devnet_cmd, cwd=ant_node_dir, log_file=devnet_log)
    print(gray(f"       PID {devnet_proc.pid}"))

    # Wait for manifest file to be written
    print(gray("       Waiting for devnet to be ready (this may take a while on first build)..."))
    manifest = None
    for _ in range(180):  # 6 minutes max
        time.sleep(2)
        if DEVNET_MANIFEST.exists():
            try:
                manifest = json.loads(DEVNET_MANIFEST.read_text())
                if manifest.get("bootstrap"):
                    break
            except (json.JSONDecodeError, OSError):
                pass
            manifest = None

    if not manifest:
        print(red("       Timed out waiting for devnet manifest"))
        devnet_proc.kill()
        sys.exit(1)

    bootstrap_peers = manifest["bootstrap"]
    wallet_key = None
    if manifest.get("evm"):
        wallet_key = manifest["evm"].get("wallet_private_key", "")
        # Strip 0x prefix if present — antd expects raw hex
        if wallet_key.startswith("0x"):
            wallet_key = wallet_key[2:]

    print(green(f"       Devnet ready: {manifest['node_count']} nodes, base port {manifest['base_port']}"))
    print(green(f"       Bootstrap: {bootstrap_peers[0][:50]}..."))

    # ── 2. Start antd ──
    print(yellow("[2/3] Starting antd..."))
    antd_env = {
        "ANTD_PEERS": ",".join(bootstrap_peers),
    }
    if wallet_key:
        antd_env["AUTONOMI_WALLET_KEY"] = wallet_key
    if manifest.get("evm"):
        evm = manifest["evm"]
        antd_env["EVM_RPC_URL"] = evm.get("rpc_url", "")
        antd_env["EVM_PAYMENT_TOKEN_ADDRESS"] = evm.get("payment_token_address", "")
        antd_env["EVM_DATA_PAYMENTS_ADDRESS"] = evm.get("data_payments_address", "")
        if evm.get("merkle_payments_address"):
            antd_env["EVM_MERKLE_PAYMENTS_ADDRESS"] = evm["merkle_payments_address"]

    antd_cmd = ["cargo", "run", "--", "--network", "local"]
    antd_proc = start_process(antd_cmd, cwd=antd_dir, env=antd_env, log_file=LOG_FILE)
    print(gray(f"       PID {antd_proc.pid}"))

    # ── 3. Health check ──
    print(yellow("[3/3] Waiting for antd to be ready..."))
    ready = wait_for_http("http://localhost:8082/health", timeout=180)

    # Save state
    save_state({
        "devnet_pid": devnet_proc.pid,
        "antd_pid": antd_proc.pid,
        "wallet_key": wallet_key or "",
        "bootstrap_peers": bootstrap_peers,
    })

    print()
    if ready:
        rest_url = _discover_rest_url()
        print(green("=== Ready! ==="))
        print()
        print(white(f"  REST:  {rest_url}"))
        print(white("  gRPC:  localhost:50051"))
        if wallet_key:
            print(white(f"  Key:   {wallet_key[:10]}..."))
        print()
        print(gray("Quick test:"))
        print(gray(f"  curl {rest_url}/health"))
        print()
        print(gray("To tear down:"))
        print(gray("  ant dev stop"))
    else:
        print(red("=== antd did not respond within timeout ==="))
        print(gray("Check logs: ant dev logs"))
        sys.exit(1)
