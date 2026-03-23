"""``ant dev stop`` — Tear down all local processes."""

from __future__ import annotations

import os
import subprocess
import sys

from .env import clear_state, is_windows, load_state


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
    print(yellow("[1/2] Stopping antd..."))
    if pid := state.get("antd_pid"):
        _kill_pid(pid)
    if sys.platform != "win32":
        subprocess.run(
            ["pkill", "-f", r"target/(debug|release)/antd"],
            capture_output=True,
        )
    print(green("       Done"))

    # 2. Kill devnet
    print(yellow("[2/2] Stopping ant devnet..."))
    if pid := state.get("devnet_pid"):
        _kill_pid(pid)
    if sys.platform != "win32":
        subprocess.run(
            ["pkill", "-f", r"target/(debug|release)/ant-devnet"],
            capture_output=True,
        )
    print(green("       Done"))

    clear_state()

    print()
    print(cyan("=== Environment torn down ==="))
    print()
