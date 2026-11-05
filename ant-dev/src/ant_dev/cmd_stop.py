"""``ant dev stop`` -- Stop the processes ``ant dev start`` launched.

It stops only the PIDs ``ant dev start`` recorded, and only while each still
has the start time recorded with it (see ``process.stop_recorded`` for how
far that goes on each OS). It deletes no files: on SIGTERM ant-devnet shuts
its nodes down, stops its Anvil and removes its own run directory, and its
next run removes whatever a killed run left behind.
"""

from __future__ import annotations

import json
import os

from .env import DEVNET_MANIFEST, clear_state, is_windows, load_state, save_state
from .process import ANTD_STOP_TIMEOUT, DEVNET_STOP_TIMEOUT, Stop, stop_recorded


def _color(code: str, text: str) -> str:
    if is_windows() and "WT_SESSION" not in os.environ:
        return text
    return f"\033[{code}m{text}\033[0m"

cyan   = lambda t: _color("0;36", t)
yellow = lambda t: _color("1;33", t)
green  = lambda t: _color("0;32", t)
red    = lambda t: _color("0;31", t)
gray   = lambda t: _color("0;90", t)

# Outcomes after which the recorded process is no longer running as ours, so
# its entry can go from the state file.
_DONE = {"stopped", "killed", "gone", "replaced"}


def _anvil_url() -> str | None:
    try:
        return json.loads(DEVNET_MANIFEST.read_text()).get("evm", {}).get("rpc_url")
    except (OSError, ValueError, AttributeError):
        return None


def _stop(name: str, pid: int | None, started: str | None, timeout: float) -> Stop:
    result = stop_recorded(pid, started, timeout)
    outcome = result.outcome
    if outcome == "stopped":
        print(green("       Stopped"))
    elif outcome == "killed" and is_windows():
        # Windows has no SIGTERM: stop_recorded kills the process tree.
        print(green("       Stopped"))
    elif outcome == "killed":
        print(yellow(f"       Killed: {name} didn't exit within {timeout:.0f} s of SIGTERM"))
    elif outcome == "gone":
        print(green("       Not running"))
    elif outcome == "replaced":
        print(yellow(f"       Left PID {pid} alone: it now belongs to another process"))
    elif outcome == "unverified":
        print(yellow(f"       Left PID {pid} alone: ant dev start recorded no start time"
                     f" for it, so it may not be {name} any more."))
        print(gray(f"       If it is, stop it with: kill {pid}"))
    elif outcome == "unchecked":
        print(red(f"       Left PID {pid} alone: couldn't check that it is still {name}"
                  f" ({result.detail})"))
    else:
        print(red(f"       Couldn't stop {name}: {result.detail}"))
    return result


def run(args) -> None:
    state = load_state()

    print()
    print(cyan("=== Tearing down local environment ==="))
    print()

    if not state:
        print(gray("       ant dev start recorded nothing to stop (~/.ant-dev/state.json)."))
        if not is_windows():
            print(gray("       To look for its processes: pgrep -af 'ant-devnet|antd'"))
        print()
        return

    # antd first: it is the devnet's client.
    print(yellow("[1/2] Stopping antd..."))
    antd = _stop("antd", state.get("antd_pid"), state.get("antd_started"), ANTD_STOP_TIMEOUT)

    print(yellow("[2/2] Stopping ant devnet..."))
    anvil_url = _anvil_url()
    devnet = _stop("ant-devnet", state.get("devnet_pid"), state.get("devnet_started"),
                   DEVNET_STOP_TIMEOUT)
    if devnet.outcome == "killed":
        print(gray("       Its next run removes the run directory it left."))
        if anvil_url and not is_windows():
            print(gray(f"       Its Anvil may still be running, at {anvil_url}."))

    # Forget only what is no longer running as ours.
    for key, result in (("antd", antd), ("devnet", devnet)):
        if result.outcome in _DONE:
            state.pop(f"{key}_pid", None)
            state.pop(f"{key}_started", None)
    print()
    if "antd_pid" in state or "devnet_pid" in state:
        save_state(state)
        print(yellow("=== Not everything was stopped: ~/.ant-dev/state.json still records it ==="))
        print(gray("    Run ant dev stop again once it is sorted out."))
    else:
        clear_state()
        print(cyan("=== Environment torn down ==="))
    print()
