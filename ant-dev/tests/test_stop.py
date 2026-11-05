"""``ant dev stop`` stops only what ``ant dev start`` recorded, and deletes nothing."""

from __future__ import annotations

import ctypes
import errno
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest

from ant_dev import cmd_start, cmd_stop, env, process
from ant_dev.process import CannotCheck, process_start_time, stop_recorded

posix_only = pytest.mark.skipif(sys.platform == "win32", reason="POSIX signals")
windows_only = pytest.mark.skipif(sys.platform != "win32", reason="Windows process handles")
linux_pidfd = pytest.mark.skipif(not hasattr(os, "pidfd_open"), reason="Linux pidfds")


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


@pytest.fixture
def no_kills(monkeypatch):
    """Make every way stop_recorded kills a process do nothing, and wait 1 s."""
    monkeypatch.setattr(process, "KILL_WAIT", 1.0)
    monkeypatch.setattr(cmd_stop, "ANTD_STOP_TIMEOUT", 1.0)
    monkeypatch.setattr(cmd_stop, "DEVNET_STOP_TIMEOUT", 1.0)
    for name in ("_kill", "_pidfd_signal", "_win_terminate"):
        monkeypatch.setattr(process, name, lambda *args: None)


@pytest.fixture
def unreadable_start_times(monkeypatch):
    """Make reading any process's start time fail."""
    def fail(*args):
        raise CannotCheck("can't read it (test)")
    monkeypatch.setattr(process, "_win_created" if sys.platform == "win32" else "process_start_time", fail)


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
    assert stop_recorded(proc.pid, process_start_time(proc.pid), 30).outcome == "stopped"
    assert proc.wait(5) == -signal.SIGTERM


@posix_only
def test_a_process_that_ignores_sigterm_is_killed_after_the_timeout(procs):
    proc = sleeper(ignore_sigterm=True)
    procs.append(proc)
    began = time.monotonic()
    assert stop_recorded(proc.pid, process_start_time(proc.pid), 2).outcome == "killed"
    assert time.monotonic() - began >= 2
    assert proc.wait(5) == -signal.SIGKILL


@linux_pidfd
def test_on_linux_signals_go_through_a_pidfd(procs, monkeypatch):
    sent = []
    real = process._pidfd_signal
    monkeypatch.setattr(process, "_pidfd_signal", lambda fd, sig: (sent.append(sig), real(fd, sig)))
    monkeypatch.setattr(process, "_kill", lambda *args: pytest.fail("signalled by PID"))
    proc = sleeper()
    procs.append(proc)
    assert stop_recorded(proc.pid, process_start_time(proc.pid), 30).outcome == "stopped"
    assert sent == [signal.SIGTERM]


@linux_pidfd
def test_without_pidfds_it_signals_by_pid(procs, monkeypatch):
    def refuse(pid):
        raise OSError(errno.ENOSYS, "no pidfds (test)")
    monkeypatch.setattr(os, "pidfd_open", refuse)
    proc = sleeper()
    procs.append(proc)
    assert stop_recorded(proc.pid, process_start_time(proc.pid), 30).outcome == "stopped"
    assert proc.wait(5) == -signal.SIGTERM


def parent_and_child(procs, tmp_path) -> tuple[subprocess.Popen, int]:
    """A sleeper that has started a sleeper of its own, and that child's PID."""
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
    return proc, int(child_pid.read_text())


@pytest.fixture
def kill_child_afterwards():
    """PIDs of children to kill once the test is over."""
    children: list[int] = []
    yield children
    for pid in children:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass


def deny(monkeypatch, pid: int, access: str | None) -> list:
    """Make opening ``pid`` with ``access``, if given, fail as access denied;
    returns the handles opened on it otherwise."""
    real = process._win_open
    opened = []

    def win_open(p, a):
        if p == pid and access and a == getattr(process, access):
            raise CannotCheck(f"can't open PID {p}: access denied (test)")
        handle = real(p, a)
        if p == pid and handle:
            opened.append(handle)
        return handle

    monkeypatch.setattr(process, "_win_open", win_open)
    return opened


@windows_only
def test_on_windows_the_process_tree_is_killed(procs, tmp_path):
    proc, child = parent_and_child(procs, tmp_path)
    child_started = process_start_time(child)
    assert child_started
    assert stop_recorded(proc.pid, process_start_time(proc.pid), 30).outcome == "killed"
    proc.wait(5)
    assert process_start_time(child) != child_started


@windows_only
def test_on_windows_access_denied_is_unchecked_not_gone_or_replaced():
    # PID 4 is the System process, which no user process may open to kill,
    # administrators included (they may still open it to look). Were it
    # opened, its start time wouldn't match, so nothing is killed.
    assert stop_recorded(4, "any start time", 1).outcome == "unchecked"


@windows_only
def test_on_windows_a_process_it_may_not_kill_is_left_and_kept(procs, home, monkeypatch):
    proc = sleeper()
    procs.append(proc)
    record(devnet=proc)
    deny(monkeypatch, proc.pid, "_WIN_STOP")

    assert stop_recorded(proc.pid, process_start_time(proc.pid), 2).outcome == "unchecked"
    cmd_stop.run(None)

    assert proc.poll() is None
    assert env.load_state()["devnet_pid"] == proc.pid


@windows_only
def test_on_windows_a_child_it_may_not_kill_fails_the_stop_and_kills_nothing(
        procs, tmp_path, monkeypatch, kill_child_afterwards):
    proc, child = parent_and_child(procs, tmp_path)
    kill_child_afterwards.append(child)
    deny(monkeypatch, child, "_WIN_STOP")

    stop = stop_recorded(proc.pid, process_start_time(proc.pid), 30)

    assert stop.outcome == "failed"
    assert f"PID {child} (python.exe), started by PID {proc.pid}" in stop.detail
    assert proc.poll() is None
    assert process_start_time(child)


@windows_only
def test_on_windows_a_child_it_cannot_even_look_at_fails_the_stop(procs, tmp_path, monkeypatch,
                                                                  kill_child_afterwards):
    proc, child = parent_and_child(procs, tmp_path)
    kill_child_afterwards.append(child)
    real = process._win_open

    def win_open(p, a):
        if p == child:
            raise CannotCheck(f"can't open PID {p}: access denied (test)")
        return real(p, a)

    monkeypatch.setattr(process, "_win_open", win_open)

    stop = stop_recorded(proc.pid, process_start_time(proc.pid), 30)

    assert stop.outcome == "failed"
    assert f"PID {child} (python.exe)" in stop.detail
    assert proc.poll() is None


@windows_only
def test_on_windows_a_listed_child_that_started_before_its_parent_is_left(
        procs, tmp_path, monkeypatch, kill_child_afterwards):
    # As if the parent's PID had been reused: the "child" is older than it.
    proc, child = parent_and_child(procs, tmp_path)
    kill_child_afterwards.append(child)
    opened = deny(monkeypatch, child, "_WIN_STOP")
    real = process._win_created
    monkeypatch.setattr(process, "_win_created", lambda h: "1" if h in opened else real(h))

    assert stop_recorded(proc.pid, process_start_time(proc.pid), 30).outcome == "killed"
    proc.wait(5)
    monkeypatch.undo()
    assert process_start_time(child)


def fail_waits(monkeypatch, handles: list) -> None:
    """Make every wait on one of ``handles`` fail."""
    real = process._k32.WaitForSingleObject

    def wait(handle, ms):
        if handle in handles:
            ctypes.set_last_error(6)  # ERROR_INVALID_HANDLE
            return process._WAIT_FAILED
        return real(handle, ms)

    monkeypatch.setattr(process._k32, "WaitForSingleObject", wait)


@windows_only
@pytest.mark.parametrize("why", ["it may not kill it", "it outlives its kill",
                                 "the wait on its kill fails"])
def test_on_windows_stop_can_be_run_again_after_a_child_it_could_not_stop(
        procs, tmp_path, home, kill_child_afterwards, why):
    proc, child = parent_and_child(procs, tmp_path)
    kill_child_afterwards.append(child)
    child_started = process_start_time(child)
    record(devnet=proc)

    with pytest.MonkeyPatch.context() as mp:
        if why == "it may not kill it":
            deny(mp, child, "_WIN_STOP")
        else:
            # Its kill does nothing.
            opened = deny(mp, child, None)
            killed = []
            real = process._win_terminate
            mp.setattr(process, "_win_terminate",
                       lambda h: killed.append(h) if h in opened else real(h))
            mp.setattr(process, "KILL_WAIT", 1.0)
            if why == "the wait on its kill fails":
                fail_waits(mp, killed)
        cmd_stop.run(None)

    assert proc.poll() is None
    assert process_start_time(child) == child_started
    assert env.load_state()["devnet_pid"] == proc.pid

    cmd_stop.run(None)

    proc.wait(5)
    assert process_start_time(child) != child_started
    assert not env.STATE_FILE.exists()


@windows_only
def test_on_windows_a_failed_wait_is_not_taken_for_an_exit(procs, home, monkeypatch):
    proc = sleeper()
    procs.append(proc)
    record(devnet=proc)
    opened = deny(monkeypatch, proc.pid, None)
    fail_waits(monkeypatch, opened)

    with pytest.raises(CannotCheck):
        process_start_time(proc.pid)
    cmd_stop.run(None)

    assert proc.poll() is None
    assert env.load_state()["devnet_pid"] == proc.pid


@windows_only
@pytest.mark.parametrize("call", ["Process32FirstW", "Process32NextW"])
def test_on_windows_an_error_listing_the_processes_kills_nothing(
        procs, tmp_path, monkeypatch, kill_child_afterwards, call):
    proc, child = parent_and_child(procs, tmp_path)
    kill_child_afterwards.append(child)

    def fail(*args):
        ctypes.set_last_error(5)  # ERROR_ACCESS_DENIED
        return 0

    monkeypatch.setattr(process._k32, call, fail)

    stop = stop_recorded(proc.pid, process_start_time(proc.pid), 30)

    assert stop.outcome == "unchecked"
    assert "can't list processes" in stop.detail
    assert proc.poll() is None
    assert process_start_time(child)


def test_a_pid_with_another_start_time_is_left_alone(procs):
    proc = sleeper()
    procs.append(proc)
    assert stop_recorded(proc.pid, "not when it started", 2).outcome == "replaced"
    assert proc.poll() is None


def test_a_pid_recorded_without_a_start_time_is_left_alone(procs):
    proc = sleeper()
    procs.append(proc)
    assert stop_recorded(proc.pid, None, 2).outcome == "unverified"
    assert proc.poll() is None


def test_a_pid_whose_start_time_cannot_be_read_is_left_alone(procs, monkeypatch):
    proc = sleeper()
    procs.append(proc)
    started = process_start_time(proc.pid)
    def fail(*args):
        raise CannotCheck("can't read it (test)")
    monkeypatch.setattr(process, "_win_created" if sys.platform == "win32" else "process_start_time", fail)
    stop = stop_recorded(proc.pid, started, 2)
    assert stop == ("unchecked", "can't read it (test)")
    assert proc.poll() is None


@posix_only
def test_a_process_this_user_may_not_signal_cannot_be_checked(procs, monkeypatch):
    proc = sleeper()
    procs.append(proc)

    def refuse(pid, sig):
        raise PermissionError(errno.EPERM, "not permitted (test)")

    monkeypatch.setattr(os, "kill", refuse)
    with pytest.raises(CannotCheck):
        process._ps_start_time(proc.pid)


@posix_only
@pytest.mark.parametrize("pidfds", [True, False], ids=["pidfds", "no-pidfds"])
def test_a_signal_refused_after_the_check_fails_the_stop(procs, monkeypatch, pidfds):
    proc = sleeper()
    procs.append(proc)

    def refuse(*args):
        raise PermissionError(errno.EPERM, "not permitted (test)")

    if not pidfds and hasattr(os, "pidfd_open"):
        monkeypatch.setattr(os, "pidfd_open", lambda pid: (_ for _ in ()).throw(
            OSError(errno.ENOSYS, "no pidfds (test)")))
    monkeypatch.setattr(process, "_kill", refuse)
    monkeypatch.setattr(process, "_pidfd_signal", refuse)
    assert stop_recorded(proc.pid, process_start_time(proc.pid), 2).outcome == "failed"
    assert proc.poll() is None


def test_start_records_no_start_time_it_cannot_read(procs, monkeypatch):
    proc = sleeper()
    procs.append(proc)

    def fail(pid):
        raise CannotCheck("can't read it (test)")

    monkeypatch.setattr(cmd_start, "process_start_time", fail)
    assert cmd_start._start_time(proc.pid) is None


def test_a_process_still_running_after_it_was_killed_has_failed(procs, no_kills):
    proc = sleeper()
    procs.append(proc)
    assert stop_recorded(proc.pid, process_start_time(proc.pid), 1).outcome == "failed"
    assert proc.poll() is None


def test_a_pid_that_is_not_running_is_gone(procs):
    proc = sleeper()
    started = process_start_time(proc.pid)
    proc.kill()
    proc.wait()
    assert stop_recorded(proc.pid, started, 2).outcome == "gone"
    assert stop_recorded(None, None, 2).outcome == "gone"


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


def record(**procs: subprocess.Popen) -> None:
    state = {}
    for key, proc in procs.items():
        state[f"{key}_pid"] = proc.pid
        state[f"{key}_started"] = process_start_time(proc.pid)
    env.save_state(state)


def test_stop_signals_only_what_start_recorded_and_deletes_nothing(procs, home):
    antd = sleeper()
    devnet = sleeper()
    # Named so that the patterns the old stop killed by would match it.
    (home / "bin").mkdir()
    other_anvil = sleeper(script=home / "bin" / "anvil")
    procs += [antd, devnet, other_anvil]
    record(antd=antd, devnet=devnet)
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
    assert not env.STATE_FILE.exists()


def test_stop_keeps_the_state_of_what_it_could_not_stop(procs, home, capsys, no_kills):
    devnet = sleeper()
    procs.append(devnet)
    record(devnet=devnet)

    cmd_stop.run(None)

    assert devnet.poll() is None
    assert "Couldn't stop ant-devnet" in capsys.readouterr().out
    assert env.load_state()["devnet_pid"] == devnet.pid


def test_stop_keeps_the_state_of_what_it_could_not_check(procs, home, unreadable_start_times):
    devnet = sleeper()
    procs.append(devnet)
    env.save_state({"devnet_pid": devnet.pid, "devnet_started": "recorded"})

    cmd_stop.run(None)

    assert devnet.poll() is None
    assert env.load_state() == {"devnet_pid": devnet.pid, "devnet_started": "recorded"}


def test_stop_forgets_only_what_it_stopped(procs, home):
    antd = sleeper()
    devnet = sleeper()
    procs += [antd, devnet]
    record(antd=antd)
    state = env.load_state()
    state.update(devnet_pid=devnet.pid, devnet_started=None)
    env.save_state(state)

    cmd_stop.run(None)

    antd.wait(10)
    assert devnet.poll() is None
    assert env.load_state() == {"devnet_pid": devnet.pid, "devnet_started": None}
