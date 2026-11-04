"""``ant dev stop`` stops only what ``ant dev start`` recorded, and deletes nothing."""

from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

import pytest

from ant_dev import cmd_stop, env
from ant_dev.process import process_start_time, stop_recorded

posix_only = pytest.mark.skipif(sys.platform == "win32", reason="POSIX signals")


def sleeper(*, ignore_sigterm: bool = False, script: Path | None = None) -> subprocess.Popen:
    code = "import signal, time\n"
    if ignore_sigterm:
        code += "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
    code += "print('ready', flush=True)\ntime.sleep(300)\n"
    if script is None:
        args = [sys.executable, "-c", code]
    else:
        script.write_text(code)
        args = [sys.executable, str(script)]
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, text=True)
    # Wait until the handler, if any, is in place.
    assert proc.stdout.readline().strip() == "ready"
    return proc


@pytest.fixture
def procs():
    started: list[subprocess.Popen] = []
    yield started
    for proc in started:
        if proc.poll() is None:
            proc.kill()
        proc.wait()


def test_a_start_time_is_stable_and_none_once_the_process_exits(procs):
    proc = sleeper()
    procs.append(proc)
    started = process_start_time(proc.pid)
    assert started
    assert process_start_time(proc.pid) == started
    proc.kill()
    proc.wait()
    assert process_start_time(proc.pid) is None


@posix_only
def test_a_process_that_exits_on_sigterm_is_stopped(procs):
    proc = sleeper()
    procs.append(proc)
    assert stop_recorded(proc.pid, process_start_time(proc.pid), 30) == "stopped"
    assert proc.wait(5) == -15


@posix_only
def test_a_process_that_ignores_sigterm_is_killed_after_the_timeout(procs):
    proc = sleeper(ignore_sigterm=True)
    procs.append(proc)
    began = time.monotonic()
    assert stop_recorded(proc.pid, process_start_time(proc.pid), 2) == "killed"
    assert time.monotonic() - began >= 2
    assert proc.wait(5) == -9


@pytest.mark.skipif(sys.platform != "win32", reason="Windows kills the tree")
def test_on_windows_the_process_tree_is_killed(procs, tmp_path):
    child_pid = tmp_path / "child.pid"
    code = (
        "import subprocess, sys, time\n"
        "c = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(300)'])\n"
        f"open({str(child_pid)!r}, 'w').write(str(c.pid))\n"
        "print('ready', flush=True)\n"
        "time.sleep(300)\n"
    )
    proc = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, text=True)
    procs.append(proc)
    assert proc.stdout.readline().strip() == "ready"
    child = int(child_pid.read_text())
    child_started = process_start_time(child)
    assert child_started
    assert stop_recorded(proc.pid, process_start_time(proc.pid), 30) == "killed"
    proc.wait(5)
    assert process_start_time(child) != child_started


def test_a_pid_with_another_start_time_is_left_alone(procs):
    proc = sleeper()
    procs.append(proc)
    assert stop_recorded(proc.pid, "not when it started", 2) == "replaced"
    assert proc.poll() is None


def test_a_pid_recorded_without_a_start_time_is_left_alone(procs):
    proc = sleeper()
    procs.append(proc)
    assert stop_recorded(proc.pid, None, 2) == "unverified"
    assert proc.poll() is None


def test_a_pid_that_is_not_running_is_gone(procs):
    proc = sleeper()
    started = process_start_time(proc.pid)
    proc.kill()
    proc.wait()
    assert stop_recorded(proc.pid, started, 2) == "gone"
    assert stop_recorded(None, None, 2) == "gone"


@pytest.fixture
def home(tmp_path, monkeypatch):
    # HOME too, so a stop that deleted under ~/.local/share/ant would delete
    # the files this test checks.
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("USERPROFILE", str(tmp_path))
    state_dir = tmp_path / ".ant-dev"
    monkeypatch.setattr(env, "STATE_FILE", state_dir / "state.json")
    monkeypatch.setattr(env, "STATE_DIR", state_dir)
    monkeypatch.setattr(cmd_stop, "DEVNET_MANIFEST", state_dir / "devnet-manifest.json")
    state_dir.mkdir()
    return tmp_path


def test_stop_signals_only_what_start_recorded_and_deletes_nothing(procs, home):
    antd = sleeper()
    devnet = sleeper()
    # Named so that the patterns the old stop killed by would match it.
    (home / "bin").mkdir()
    other_anvil = sleeper(script=home / "bin" / "anvil")
    procs += [antd, devnet, other_anvil]
    env.save_state({
        "antd_pid": antd.pid,
        "antd_started": process_start_time(antd.pid),
        "devnet_pid": devnet.pid,
        "devnet_started": process_start_time(devnet.pid),
    })
    # What the old stop deleted: a real node's data, and in-progress uploads.
    data = home / ".local" / "share" / "ant"
    for sub in ("nodes/node-1/record", "spill/spill_1/chunk"):
        (data / sub).parent.mkdir(parents=True)
        (data / sub).write_text("not the devnet's")

    cmd_stop.run(None)

    antd.wait(10)
    devnet.wait(10)
    assert other_anvil.poll() is None
    assert (data / "nodes/node-1/record").read_text() == "not the devnet's"
    assert (data / "spill/spill_1/chunk").read_text() == "not the devnet's"
    assert not env.STATE_FILE.exists()


def test_stop_leaves_a_pid_that_is_no_longer_its_own(procs, home, capsys):
    other = sleeper()
    procs.append(other)
    env.STATE_FILE.write_text(json.dumps({
        "devnet_pid": other.pid,
        "devnet_started": "when the devnet that had this PID started",
    }))

    cmd_stop.run(None)

    assert other.poll() is None
    assert f"Left PID {other.pid} alone" in capsys.readouterr().out
