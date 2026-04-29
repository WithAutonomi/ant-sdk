"""Daemon port-file discovery for antd.

The antd daemon writes a ``daemon.port`` file on startup containing:
  - Line 1: REST port
  - Line 2: gRPC port
  - Line 3: PID of the daemon process (optional, for staleness detection)

This module reads that file to auto-discover the daemon's listen addresses.
If a PID is present and the process is no longer running, the port file is
considered stale and discovery returns empty results.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

_PORT_FILE_NAME = "daemon.port"
_DATA_DIR_NAME = "ant"
_SDK_SUBDIR_NAME = "sdk"


def discover_daemon_url() -> str:
    """Return the REST base URL from the daemon port file, or ``""`` on failure."""
    rest, _ = _read_port_file()
    if rest == 0:
        return ""
    return f"http://127.0.0.1:{rest}"


def discover_grpc_target() -> str:
    """Return the gRPC target from the daemon port file, or ``""`` on failure."""
    _, grpc = _read_port_file()
    if grpc == 0:
        return ""
    return f"127.0.0.1:{grpc}"


def _read_port_file() -> tuple[int, int]:
    """Read the daemon.port file and return ``(rest_port, grpc_port)``.

    A single-line file is valid (gRPC port will be 0).
    Returns ``(0, 0)`` on any error.
    """
    dir_path = _data_dir()
    if not dir_path:
        return 0, 0

    port_file = Path(dir_path) / _PORT_FILE_NAME
    try:
        text = port_file.read_text(encoding="utf-8")
    except OSError:
        return 0, 0

    lines = text.strip().splitlines()
    if not lines:
        return 0, 0

    # Check PID staleness (line 3, if present)
    if len(lines) >= 3:
        pid = _parse_pid(lines[2])
        if pid is not None and not _is_process_alive(pid):
            return 0, 0

    rest_port = _parse_port(lines[0])
    grpc_port = _parse_port(lines[1]) if len(lines) >= 2 else 0
    return rest_port, grpc_port


def _parse_pid(s: str) -> int | None:
    """Parse a PID string, returning ``None`` if absent or invalid."""
    try:
        n = int(s.strip())
    except (ValueError, TypeError):
        return None
    if n > 0:
        return n
    return None


def _is_process_alive(pid: int) -> bool:
    """Return ``True`` if a process with *pid* is currently running."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        # Process exists but we lack permission to signal it — still alive.
        return True
    except OSError:
        return False
    return True


def _parse_port(s: str) -> int:
    """Parse a port string, returning 0 on failure."""
    try:
        n = int(s.strip())
    except (ValueError, TypeError):
        return 0
    if 1 <= n <= 65535:
        return n
    return 0


def _data_dir() -> str:
    """Return the platform-specific data directory for the antd SDK daemon, or ``""``.

    The ``sdk`` subdirectory keeps antd's port file separate from the
    ant-node daemon, which writes to the same ``ant`` umbrella dir.
    """
    if sys.platform == "win32":
        appdata = os.environ.get("APPDATA", "")
        if not appdata:
            return ""
        return os.path.join(appdata, _DATA_DIR_NAME, _SDK_SUBDIR_NAME)

    if sys.platform == "darwin":
        home = os.environ.get("HOME", "")
        if not home:
            return ""
        return os.path.join(home, "Library", "Application Support", _DATA_DIR_NAME, _SDK_SUBDIR_NAME)

    # Linux and others
    xdg = os.environ.get("XDG_DATA_HOME", "")
    if xdg:
        return os.path.join(xdg, _DATA_DIR_NAME, _SDK_SUBDIR_NAME)
    home = os.environ.get("HOME", "")
    if not home:
        return ""
    return os.path.join(home, ".local", "share", _DATA_DIR_NAME, _SDK_SUBDIR_NAME)
