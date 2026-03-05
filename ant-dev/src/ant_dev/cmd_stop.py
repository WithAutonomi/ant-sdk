"""``ant dev stop`` — Tear down all local processes.

Python port of scripts/kill-local.sh / scripts/kill-local.ps1.
"""

from __future__ import annotations

import os
import subprocess
import sys

from .env import clear_state, find_autonomi_dir, is_windows, load_state


def _color(code: str, text: str) -> str:
    if is_windows() and "WT_SESSION" not in os.environ:
        return text
    return f"\033[{code}m{text}\033[0m"

cyan   = lambda t: _color("0;36", t)
yellow = lambda t: _color("1;33", t)
green  = lambda t: _color("0;32", t)


def _kill_pid(pid: int) -> None:
    """Kill a process by PID, ignoring errors."""
    try:
        if sys.platform == "win32":
            subprocess.run(
                ["taskkill", "/F", "/T", "/PID", str(pid)],
                capture_output=True,
            )
        else:
            import signal
            os.kill(pid, signal.SIGTERM)
    except (ProcessLookupError, OSError):
        pass


def run(args) -> None:
    state = load_state()

    print()
    print(cyan("=== Tearing down local environment ==="))
    print()

    # 1. Kill antd
    print(yellow("[1/3] Stopping antd..."))
    if pid := state.get("antd_pid"):
        _kill_pid(pid)
    if sys.platform != "win32":
        subprocess.run(
            ["pkill", "-f", r"target/(debug|release)/antd"],
            capture_output=True,
        )
    print(green("       Done"))

    # 2. Kill local network via antctl
    print(yellow("[2/3] Stopping local network..."))
    if pid := state.get("net_pid"):
        _kill_pid(pid)
    try:
        autonomi_dir = find_autonomi_dir()
        subprocess.run(
            ["cargo", "run", "--release", "--bin", "antctl", "--", "local", "kill"],
            cwd=str(autonomi_dir),
            capture_output=True,
            timeout=60,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        pass
    print(green("       Done"))

    # 3. Kill EVM testnet
    print(yellow("[3/3] Stopping EVM testnet..."))
    if pid := state.get("evm_pid"):
        _kill_pid(pid)
    if sys.platform != "win32":
        subprocess.run(
            ["pkill", "-f", r"target/(debug|release)/evm-testnet"],
            capture_output=True,
        )
    print(green("       Done"))

    clear_state()

    print()
    print(cyan("=== Environment torn down ==="))
    print()
