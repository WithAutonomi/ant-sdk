"""Port discovery for the antd daemon.

The antd daemon writes a ``daemon.port`` file on startup containing two lines:
  - Line 1: REST port
  - Line 2: gRPC port

This module reads that file using platform-specific data directory paths to
auto-discover the daemon without requiring manual configuration.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

_PORT_FILE_NAME = "daemon.port"
_DATA_DIR_NAME = "ant"


def _data_dir() -> Path | None:
    """Return the platform-specific data directory for ant, or None."""
    if sys.platform == "win32":
        appdata = os.environ.get("APPDATA")
        if not appdata:
            return None
        return Path(appdata) / _DATA_DIR_NAME

    if sys.platform == "darwin":
        home = os.environ.get("HOME")
        if not home:
            return None
        return Path(home) / "Library" / "Application Support" / _DATA_DIR_NAME

    # Linux and other Unix-likes
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        return Path(xdg) / _DATA_DIR_NAME
    home = os.environ.get("HOME")
    if not home:
        return None
    return Path(home) / ".local" / "share" / _DATA_DIR_NAME


def _read_port_file() -> tuple[int, int]:
    """Read the daemon.port file and return (rest_port, grpc_port).

    Returns (0, 0) if the file is missing or unreadable.
    A single-line file is valid; grpc_port will be 0 in that case.
    """
    data_dir = _data_dir()
    if data_dir is None:
        return 0, 0

    port_file = data_dir / _PORT_FILE_NAME
    try:
        text = port_file.read_text().strip()
    except (OSError, ValueError):
        return 0, 0

    lines = text.splitlines()
    if not lines:
        return 0, 0

    rest_port = _parse_port(lines[0])
    grpc_port = _parse_port(lines[1]) if len(lines) >= 2 else 0
    return rest_port, grpc_port


def _parse_port(s: str) -> int:
    """Parse a port string, returning 0 on failure."""
    try:
        n = int(s.strip())
        if 1 <= n <= 65535:
            return n
    except ValueError:
        pass
    return 0


def discover_daemon_url() -> str:
    """Read the daemon.port file and return the REST base URL.

    Returns ``"http://127.0.0.1:{port}"`` on success, or ``""`` if the port
    file is not found or unreadable.
    """
    rest, _ = _read_port_file()
    if rest == 0:
        return ""
    return f"http://127.0.0.1:{rest}"


def discover_grpc_target() -> str:
    """Read the daemon.port file and return the gRPC target.

    Returns ``"127.0.0.1:{port}"`` on success, or ``""`` if the port file
    is not found or has no gRPC line.
    """
    _, grpc = _read_port_file()
    if grpc == 0:
        return ""
    return f"127.0.0.1:{grpc}"
