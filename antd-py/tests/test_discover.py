"""Tests for antd._discover port-file discovery."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from antd._discover import (
    _data_dir,
    _is_process_alive,
    _read_port_file,
    discover_daemon_url,
    discover_grpc_target,
)


def _write_port_file(tmp_path: Path, content: str, monkeypatch) -> None:
    """Write a daemon.port file under tmp_path/ant/ and point env vars at it."""
    ant_dir = tmp_path / "ant"
    ant_dir.mkdir(exist_ok=True)
    (ant_dir / "daemon.port").write_text(content, encoding="utf-8")
    # Use XDG_DATA_HOME on all platforms for test isolation
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path))
    # Force sys.platform to linux so XDG_DATA_HOME is used
    monkeypatch.setattr("sys.platform", "linux")


class TestDiscoverDaemonUrl:
    def test_valid_file_both_lines(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "8082\n50051\n", monkeypatch)
        assert discover_daemon_url() == "http://127.0.0.1:8082"

    def test_valid_file_single_line(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "9000\n", monkeypatch)
        assert discover_daemon_url() == "http://127.0.0.1:9000"

    def test_missing_file(self, tmp_path, monkeypatch):
        monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path))
        monkeypatch.setattr("sys.platform", "linux")
        # No daemon.port file created
        assert discover_daemon_url() == ""

    def test_invalid_content(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "not_a_number\n", monkeypatch)
        assert discover_daemon_url() == ""

    def test_empty_file(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "", monkeypatch)
        assert discover_daemon_url() == ""

    def test_whitespace_handling(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "  8082  \n  50051  \n", monkeypatch)
        assert discover_daemon_url() == "http://127.0.0.1:8082"

    def test_port_zero(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "0\n50051\n", monkeypatch)
        assert discover_daemon_url() == ""

    def test_port_out_of_range(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "99999\n50051\n", monkeypatch)
        assert discover_daemon_url() == ""


class TestDiscoverGrpcTarget:
    def test_valid_file_both_lines(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "8082\n50051\n", monkeypatch)
        assert discover_grpc_target() == "127.0.0.1:50051"

    def test_single_line_no_grpc(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "8082\n", monkeypatch)
        assert discover_grpc_target() == ""

    def test_missing_file(self, tmp_path, monkeypatch):
        monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path))
        monkeypatch.setattr("sys.platform", "linux")
        assert discover_grpc_target() == ""

    def test_invalid_grpc_line(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "8082\nabc\n", monkeypatch)
        assert discover_grpc_target() == ""

    def test_whitespace_handling(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "  8082  \n  50051  \n", monkeypatch)
        assert discover_grpc_target() == "127.0.0.1:50051"


class TestStalePidDetection:
    """Port file with a PID that doesn't correspond to a running process."""

    def test_stale_pid_returns_empty_url(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "8082\n50051\n99999999\n", monkeypatch)
        assert discover_daemon_url() == ""

    def test_stale_pid_returns_empty_grpc(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "8082\n50051\n99999999\n", monkeypatch)
        assert discover_grpc_target() == ""

    def test_stale_pid_read_port_file(self, tmp_path, monkeypatch):
        _write_port_file(tmp_path, "8082\n50051\n99999999\n", monkeypatch)
        assert _read_port_file() == (0, 0)

    def test_alive_pid_returns_url(self, tmp_path, monkeypatch):
        """Use our own PID, which is guaranteed to be alive."""
        pid = os.getpid()
        _write_port_file(tmp_path, f"8082\n50051\n{pid}\n", monkeypatch)
        assert discover_daemon_url() == "http://127.0.0.1:8082"

    def test_alive_pid_returns_grpc(self, tmp_path, monkeypatch):
        pid = os.getpid()
        _write_port_file(tmp_path, f"8082\n50051\n{pid}\n", monkeypatch)
        assert discover_grpc_target() == "127.0.0.1:50051"

    def test_no_pid_line_still_works(self, tmp_path, monkeypatch):
        """Old two-line format without PID should still work."""
        _write_port_file(tmp_path, "8082\n50051\n", monkeypatch)
        assert discover_daemon_url() == "http://127.0.0.1:8082"

    def test_invalid_pid_line_treated_as_absent(self, tmp_path, monkeypatch):
        """Non-numeric PID line is ignored (not treated as stale)."""
        _write_port_file(tmp_path, "8082\n50051\nnotapid\n", monkeypatch)
        assert discover_daemon_url() == "http://127.0.0.1:8082"

    def test_is_process_alive_dead(self):
        assert _is_process_alive(99999999) is False

    def test_is_process_alive_self(self):
        assert _is_process_alive(os.getpid()) is True


class TestDataDir:
    def test_windows(self, monkeypatch):
        monkeypatch.setattr("sys.platform", "win32")
        monkeypatch.setenv("APPDATA", "C:\\Users\\test\\AppData\\Roaming")
        result = _data_dir()
        assert result == os.path.join("C:\\Users\\test\\AppData\\Roaming", "ant")

    def test_darwin(self, monkeypatch):
        monkeypatch.setattr("sys.platform", "darwin")
        monkeypatch.setenv("HOME", "/Users/test")
        result = _data_dir()
        assert result == os.path.join("/Users/test", "Library", "Application Support", "ant")

    def test_linux_xdg(self, monkeypatch):
        monkeypatch.setattr("sys.platform", "linux")
        monkeypatch.setenv("XDG_DATA_HOME", "/custom/data")
        result = _data_dir()
        assert result == os.path.join("/custom/data", "ant")

    def test_linux_no_xdg(self, monkeypatch):
        monkeypatch.setattr("sys.platform", "linux")
        monkeypatch.delenv("XDG_DATA_HOME", raising=False)
        monkeypatch.setenv("HOME", "/home/test")
        result = _data_dir()
        assert result == os.path.join("/home/test", ".local", "share", "ant")

    def test_linux_no_home(self, monkeypatch):
        monkeypatch.setattr("sys.platform", "linux")
        monkeypatch.delenv("XDG_DATA_HOME", raising=False)
        monkeypatch.delenv("HOME", raising=False)
        assert _data_dir() == ""

    def test_windows_no_appdata(self, monkeypatch):
        monkeypatch.setattr("sys.platform", "win32")
        monkeypatch.delenv("APPDATA", raising=False)
        assert _data_dir() == ""

    def test_darwin_no_home(self, monkeypatch):
        monkeypatch.setattr("sys.platform", "darwin")
        monkeypatch.delenv("HOME", raising=False)
        assert _data_dir() == ""
