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


def stop_process(pid: int) -> bool:
    """Kill a process by PID. Returns True if it was running."""
    try:
        if sys.platform == "win32":
            subprocess.run(
                ["taskkill", "/F", "/T", "/PID", str(pid)],
                capture_output=True,
            )
        else:
            os.kill(pid, signal.SIGTERM)
        return True
    except (ProcessLookupError, OSError):
        return False


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
