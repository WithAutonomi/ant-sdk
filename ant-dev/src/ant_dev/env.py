"""Shared configuration: paths, state file I/O, platform detection."""

from __future__ import annotations

import json
import os
import platform
import sys
from pathlib import Path


def find_sdk_root() -> Path:
    """Find the ant-sdk repo root by walking up from this file."""
    d = Path(__file__).resolve().parent
    for _ in range(10):
        if (d / "antd" / "Cargo.toml").exists():
            return d
        d = d.parent
    # Fallback: current working directory
    cwd = Path.cwd()
    if (cwd / "antd" / "Cargo.toml").exists():
        return cwd
    raise FileNotFoundError(
        "Cannot locate ant-sdk root. Run from inside the repo or set --sdk-root."
    )


def find_autonomi_dir() -> Path:
    """Resolve the autonomi repo directory."""
    env = os.environ.get("AUTONOMI_DIR")
    if env:
        return Path(env)
    # Default: sibling directory to ant-sdk
    sibling = find_sdk_root().parent / "autonomi"
    if sibling.exists():
        return sibling
    raise FileNotFoundError(
        "Cannot find autonomi repo. Set AUTONOMI_DIR or place it next to ant-sdk."
    )


def bootstrap_cache_path() -> Path:
    """Platform-specific bootstrap cache file path."""
    system = platform.system()
    if system == "Darwin":
        base = Path.home() / "Library" / "Application Support"
    elif system == "Windows":
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return base / "autonomi" / "bootstrap_cache" / "version_1" / "bootstrap_cache_local_1_1.0.json"


# ── State file ──

STATE_DIR = Path.home() / ".ant-dev"
STATE_FILE = STATE_DIR / "state.json"
LOG_FILE = STATE_DIR / "antd.log"


def load_state() -> dict:
    """Load state from ~/.ant-dev/state.json, or return empty dict."""
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            return {}
    return {}


def save_state(state: dict) -> None:
    """Write state to ~/.ant-dev/state.json."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2))


def clear_state() -> None:
    """Remove the state file."""
    if STATE_FILE.exists():
        STATE_FILE.unlink()


def is_windows() -> bool:
    return sys.platform == "win32"
