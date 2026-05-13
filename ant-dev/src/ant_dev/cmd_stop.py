"""``ant dev stop`` -- Tear down all local processes."""

from __future__ import annotations

import os
import shutil
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


def _pkill(pattern: str) -> None:
    """Best-effort pkill on POSIX; no-op on Windows."""
    if sys.platform == "win32":
        return
    subprocess.run(["pkill", "-9", "-f", pattern], capture_output=True)


def run(args) -> None:
    state = load_state()

    print()
    print(cyan("=== Tearing down local environment ==="))
    print()

    # 1. Kill antd
    print(yellow("[1/2] Stopping antd..."))
    if pid := state.get("antd_pid"):
        _kill_pid(pid)
    _pkill(r"target/(debug|release)/antd")
    print(green("       Done"))

    # 2. Kill devnet + the orphan children it leaves behind.
    #
    # ant-devnet does ``std::mem::forget(testnet)`` on the AnvilInstance to
    # keep anvil running across the scope, then relies on process exit to
    # clean it up. That cleanup only fires on graceful Drop -- SIGTERM/
    # SIGKILL skip destructors, so anvil orphans every time we stop. Reap
    # it explicitly, plus any antnode children spawned by ant-devnet.
    # Tracked upstream in WithAutonomi/ant-sdk#73.
    print(yellow("[2/2] Stopping ant devnet..."))
    if pid := state.get("devnet_pid"):
        _kill_pid(pid)
    _pkill(r"target/(debug|release)/ant-devnet")
    _pkill(r"(^|/)anvil( |$)")
    _pkill(r"target/(debug|release)/antnode")
    print(green("       Done"))

    # ant-devnet does not clean up ~/.local/share/ant/ on SIGTERM either
    # (same destructor-skip cause). Stale node identities accumulating
    # there have caused subsequent ``ant dev start`` runs to flake/hang.
    # Wipe known transient data dirs so the next start is from a clean slate.
    if sys.platform != "win32":
        for sub in ("nodes", "spill"):
            path = os.path.expanduser(f"~/.local/share/ant/{sub}")
            if os.path.isdir(path):
                shutil.rmtree(path, ignore_errors=True)

    clear_state()

    print()
    print(cyan("=== Environment torn down ==="))
    print()
