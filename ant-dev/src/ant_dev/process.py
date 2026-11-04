"""Cross-platform process management: start, stop, health checks."""

from __future__ import annotations

import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

import httpx


def start_process(
    cmd: list[str],
    cwd: str | Path | None = None,
    env: dict[str, str] | None = None,
    log_file: str | Path | None = None,
) -> subprocess.Popen:
    """Start a subprocess, optionally redirecting output to a log file."""
    merged_env = {**os.environ, **(env or {})}
    kwargs: dict = dict(
        cwd=str(cwd) if cwd else None,
        env=merged_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if log_file:
        fh = open(log_file, "w")
        kwargs["stdout"] = fh
        kwargs["stderr"] = subprocess.STDOUT

    if sys.platform == "win32":
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP

    return subprocess.Popen(cmd, **kwargs)


# ant-devnet stops its nodes one at a time, and gives each node's writers up
# to 15 s to finish, so a clean stop can take a while.
DEVNET_STOP_TIMEOUT = 120.0
ANTD_STOP_TIMEOUT = 30.0


def process_start_time(pid: int) -> str | None:
    """When process ``pid`` started, or None if no running process has that PID.

    ``ant dev start`` records this next to each PID it launches. ``ant dev
    stop`` signals a PID only while its start time still matches, so a PID
    the OS has since given to another process is left alone.
    """
    if pid <= 0:
        return None
    if sys.platform.startswith("linux"):
        try:
            stat = Path(f"/proc/{pid}/stat").read_text()
        except OSError:
            return None
        # The command name in field 2 is in parentheses and can hold spaces,
        # so count from the last ")": field 3 is the state, field 22 the
        # start time in clock ticks since boot.
        fields = stat[stat.rindex(")") + 2:].split()
        return None if fields[0] == "Z" else fields[19]
    if sys.platform == "win32":
        cmd = [
            "powershell", "-NoProfile", "-NonInteractive", "-Command",
            f"(Get-Process -Id {pid} -ErrorAction Stop).StartTime"
            ".ToUniversalTime().ToString('o')",
        ]
    else:
        cmd = ["ps", "-o", "stat=", "-o", "lstart=", "-p", str(pid)]
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=30,
            env={**os.environ, "LC_ALL": "C", "TZ": "UTC"},
        )
    except (OSError, subprocess.SubprocessError):
        return None
    out = result.stdout.strip()
    if result.returncode != 0 or not out:
        return None
    if sys.platform == "win32":
        return out
    state, _, started = out.partition(" ")
    return None if state.startswith("Z") else started.strip()


def stop_recorded(pid: int | None, started: str | None, timeout: float) -> str:
    """Stop the process ``ant dev start`` recorded as ``pid``, and nothing else.

    On POSIX it sends SIGTERM and waits up to ``timeout`` seconds for the
    process to exit, then SIGKILL. Windows has no SIGTERM, so there it kills
    the process tree at once.

    Returns ``"stopped"`` (exited on SIGTERM), ``"killed"``, ``"gone"`` (not
    running), ``"unverified"`` (no start time recorded, so left alone) or
    ``"replaced"`` (the PID now belongs to another process, left alone).
    """
    current = process_start_time(pid) if pid else None
    if current is None:
        return "gone"
    if not started:
        return "unverified"
    if current != started:
        return "replaced"

    def wait(seconds: float) -> bool:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if process_start_time(pid) != started:
                return True
            time.sleep(0.5)
        return process_start_time(pid) != started

    if sys.platform == "win32":
        subprocess.run(
            ["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True,
        )
        wait(30)
        return "killed"
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return "gone"
    # `wait` checks the start time last, just before the SIGKILL.
    if wait(timeout):
        return "stopped"
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        return "stopped"
    wait(10)
    return "killed"


def is_alive(pid: int) -> bool:
    """Check if a process with the given PID is still running."""
    if pid <= 0:
        return False
    try:
        if sys.platform == "win32":
            result = subprocess.run(
                ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
                capture_output=True,
                text=True,
            )
            return str(pid) in result.stdout
        else:
            os.kill(pid, 0)
            return True
    except (ProcessLookupError, PermissionError, OSError):
        return False


def wait_for_pattern(
    file_path: str | Path,
    pattern: str,
    timeout: int = 300,
    interval: float = 2.0,
) -> str | None:
    """Wait for a regex pattern to appear in a file. Returns the first match group or None."""
    compiled = re.compile(pattern)
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            text = Path(file_path).read_text(errors="replace")
            m = compiled.search(text)
            if m:
                return m.group(1) if m.lastindex else m.group(0)
        except OSError:
            pass
        time.sleep(interval)
    return None


def wait_for_http(
    url: str,
    timeout: int = 180,
    interval: float = 3.0,
) -> bool:
    """Wait for an HTTP endpoint to return a successful response."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = httpx.get(url, timeout=5)
            if r.status_code == 200:
                return True
        except (httpx.HTTPError, OSError):
            pass
        time.sleep(interval)
    return False
