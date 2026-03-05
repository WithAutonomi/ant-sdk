"""``ant dev start`` — Start EVM testnet + local network + antd daemon.

Python port of scripts/start-local.sh / scripts/start-local.ps1.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

from .env import (
    bootstrap_cache_path,
    find_autonomi_dir,
    find_sdk_root,
    is_windows,
    LOG_FILE,
    save_state,
    STATE_DIR,
)
from .process import start_process, wait_for_http, wait_for_pattern


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
    autonomi_dir = Path(args.autonomi_dir) if args.autonomi_dir else find_autonomi_dir()
    sdk_root = find_sdk_root()
    antd_dir = sdk_root / "antd"
    no_build = getattr(args, "no_build", False)

    STATE_DIR.mkdir(parents=True, exist_ok=True)

    evm_log = STATE_DIR / "evm-testnet.log"
    network_log = STATE_DIR / "network.log"

    # Clean old logs
    for f in (evm_log, network_log, LOG_FILE):
        if f.exists():
            f.unlink()

    print()
    print(cyan("=== antd Local Test Environment ==="))
    print()

    # ── 1. Start EVM testnet ──
    print(yellow("[1/4] Starting EVM testnet..."))
    evm_cmd = ["cargo", "run", "--bin", "evm-testnet"]
    evm_proc = start_process(evm_cmd, cwd=autonomi_dir, log_file=evm_log)
    print(gray(f"       PID {evm_proc.pid}"))

    # Wait for SECRET_KEY
    print(gray("       Waiting for secret key..."))
    wallet_key = wait_for_pattern(evm_log, r"SECRET_KEY=(\S+)", timeout=300)
    if not wallet_key:
        print(red("       Timed out waiting for SECRET_KEY"))
        evm_proc.kill()
        sys.exit(1)
    print(green(f"       Got wallet key: {wallet_key[:10]}..."))

    # ── 2. Start local network ──
    print(yellow("[2/4] Starting local Autonomi network..."))

    # Clear old bootstrap cache
    cache_file = bootstrap_cache_path()
    if cache_file.exists():
        cache_file.unlink()
        print(gray("       Cleared old bootstrap cache"))

    net_cmd = [
        "cargo", "run", "--release", "--bin", "antctl", "--",
        "local", "run", "--clean",
        "--rewards-address", "0xd10A556E6A5111b5D4Dd5Ae06761d41F6CE1D499",
    ]
    if not no_build:
        net_cmd.insert(net_cmd.index("--clean"), "--build")

    net_proc = start_process(net_cmd, cwd=autonomi_dir, log_file=network_log)
    print(gray(f"       PID {net_proc.pid}"))

    # Wait for bootstrap cache to contain peers
    print(gray("       Waiting for network (this may take a while with --build)..."))
    peer_addr = None
    for _ in range(120):
        time.sleep(3)
        if cache_file.exists():
            try:
                cache = json.loads(cache_file.read_text())
                peers = cache.get("peers", [])
                if peers and len(peers) > 0:
                    peer_addr = peers[0][1][0]
                    break
            except (json.JSONDecodeError, KeyError, IndexError, OSError):
                pass

    if not peer_addr:
        print(red("       Could not find local peers in bootstrap cache!"))
        evm_proc.kill()
        net_proc.kill()
        sys.exit(1)
    print(green(f"       Found peer: {peer_addr[:40]}..."))

    # ── 3. Start antd ──
    print(yellow("[3/4] Starting antd..."))
    antd_env = {
        "AUTONOMI_WALLET_KEY": wallet_key,
        "ANT_PEERS": peer_addr,
    }
    antd_cmd = ["cargo", "run", "--", "--network", "local"]
    antd_proc = start_process(antd_cmd, cwd=antd_dir, env=antd_env, log_file=LOG_FILE)
    print(gray(f"       PID {antd_proc.pid}"))

    # ── 4. Health check ──
    print(yellow("[4/4] Waiting for antd to be ready..."))
    ready = wait_for_http("http://localhost:8080/health", timeout=180)

    # Save state
    save_state({
        "evm_pid": evm_proc.pid,
        "net_pid": net_proc.pid,
        "antd_pid": antd_proc.pid,
        "wallet_key": wallet_key,
        "peer_addr": peer_addr,
    })

    print()
    if ready:
        print(green("=== Ready! ==="))
        print()
        print(white("  REST:  http://localhost:8080"))
        print(white("  gRPC:  localhost:50051"))
        print(white(f"  Key:   {wallet_key[:10]}..."))
        print()
        print(gray("Quick test:"))
        print(gray("  curl http://localhost:8080/health"))
        print()
        print(gray("To tear down:"))
        print(gray("  ant dev stop"))
    else:
        print(red("=== antd did not respond within timeout ==="))
        print(gray("Check logs: ant dev logs"))
        sys.exit(1)
