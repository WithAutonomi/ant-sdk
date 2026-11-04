"""Cross-platform process management: start, stop, health checks."""

from __future__ import annotations

import os
import re
import select
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import NamedTuple

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
# How long to wait for a process to go once it has been killed.
KILL_WAIT = 10.0


class CannotCheck(Exception):
    """A process's start time couldn't be read: not the same as no process."""


class Stop(NamedTuple):
    """What ``stop_recorded`` did.

    ``outcome`` is one of:

    - ``"stopped"``: it exited on SIGTERM.
    - ``"killed"``: it was killed (SIGKILL; on Windows, always).
    - ``"gone"``: it wasn't running.
    - ``"replaced"``: the PID now belongs to another process, left alone.
    - ``"unverified"``: no start time was recorded, so it was left alone.
    - ``"unchecked"``: its start time couldn't be read, so it was left alone.
    - ``"failed"``: it was still running after it was killed.
    """

    outcome: str
    detail: str = ""


def process_start_time(pid: int) -> str | None:
    """When process ``pid`` started, or None if no running process has that PID.

    ``ant dev start`` records this next to each PID it launches, and ``ant dev
    stop`` stops a PID only while its start time still matches. Raises
    ``CannotCheck`` if the start time couldn't be read.
    """
    if pid <= 0:
        return None
    if sys.platform == "win32":
        handle = _win_open(pid, _WIN_QUERY)
        if not isinstance(handle, int):
            return handle
        try:
            return _win_created(handle)
        finally:
            _k32.CloseHandle(handle)
    if sys.platform.startswith("linux"):
        try:
            stat = Path(f"/proc/{pid}/stat").read_text()
        except (FileNotFoundError, ProcessLookupError):
            return None
        except OSError as e:
            raise CannotCheck(f"can't read /proc/{pid}/stat: {e}") from e
        # The command name in field 2 is in parentheses and can hold spaces,
        # so count from the last ")": field 3 is the state, field 22 the
        # start time in clock ticks since boot.
        fields = stat[stat.rindex(")") + 2:].split()
        return None if fields[0] == "Z" else fields[19]
    return _ps_start_time(pid)


# Never equal to a recorded start time: ant dev start only records processes
# it launched, which run as this user.
_NOT_THIS_USERS = "a process this user can't signal"


def _ps_start_time(pid: int) -> str | None:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return None
    except PermissionError:
        return _NOT_THIS_USERS
    try:
        result = subprocess.run(
            ["ps", "-o", "stat=", "-o", "lstart=", "-p", str(pid)],
            capture_output=True, text=True, timeout=30,
            env={**os.environ, "LC_ALL": "C", "TZ": "UTC"},
        )
    except (OSError, subprocess.SubprocessError) as e:
        raise CannotCheck(f"ps failed: {e}") from e
    state, _, started = result.stdout.strip().partition(" ")
    if not started.strip():
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return None
        raise CannotCheck(f"ps gave no start time for PID {pid}: {result.stderr.strip()}")
    return None if state.startswith("Z") else started.strip()


def _verdict(current: str | None, started: str | None) -> Stop | None:
    """Why not to signal a process whose start time is ``current``, if any."""
    if current is None:
        return Stop("gone")
    if not started:
        return Stop("unverified")
    if current != started:
        return Stop("replaced")
    return None


def stop_recorded(pid: int | None, started: str | None, timeout: float) -> Stop:
    """Stop the process ``ant dev start`` recorded as ``pid``, and nothing else.

    On POSIX it sends SIGTERM and waits up to ``timeout`` seconds for the
    process to exit, then sends SIGKILL. Windows has no SIGTERM, so there it
    kills the process and its descendants at once.

    On Linux and Windows it first opens a handle that refers to one process
    for as long as it is open (a pidfd; a process handle), checks the start
    time only then, and signals only through the handle, so no other process
    can be signalled even if the PID is reused. Elsewhere (macOS), and on Linux
    without pidfds (before 5.3, or in a sandbox that refuses them), it is
    best effort: the check and each signal are separate, so a PID reused in
    between could be signalled. On macOS ``ps`` gives start times only to the
    second, so a PID reused within the same second could pass the check too.
    """
    if not pid:
        return Stop("gone")
    try:
        if sys.platform == "win32":
            return _win_stop(pid, started)
        if hasattr(os, "pidfd_open"):
            try:
                pidfd = os.pidfd_open(pid)
            except ProcessLookupError:
                return Stop("gone")
            except OSError:
                pass
            else:
                try:
                    return _pidfd_stop(pidfd, pid, started, timeout)
                finally:
                    os.close(pidfd)
        return _posix_stop(pid, started, timeout)
    except CannotCheck as e:
        return Stop("unchecked", str(e))


def _pidfd_signal(pidfd: int, sig: int) -> None:
    signal.pidfd_send_signal(pidfd, sig)


def _pidfd_stop(pidfd: int, pid: int, started: str | None, timeout: float) -> Stop:
    # Read the start time only once the pidfd is open: if it is the recorded
    # one, the pidfd refers to the process ant dev start launched, which has
    # had this PID since before the pidfd was opened.
    verdict = _verdict(process_start_time(pid), started)
    if verdict:
        return verdict

    def exited(seconds: float) -> bool:
        poller = select.poll()
        poller.register(pidfd, select.POLLIN)
        return bool(poller.poll(int(seconds * 1000)))

    try:
        _pidfd_signal(pidfd, signal.SIGTERM)
        if exited(timeout):
            return Stop("stopped")
        _pidfd_signal(pidfd, signal.SIGKILL)
    except ProcessLookupError:
        return Stop("stopped")
    if exited(KILL_WAIT):
        return Stop("killed")
    return Stop("failed", f"PID {pid} was still running {KILL_WAIT:.0f} s after SIGKILL")


def _kill(pid: int, sig: int) -> None:
    os.kill(pid, sig)


def _posix_stop(pid: int, started: str | None, timeout: float) -> Stop:
    verdict = _verdict(process_start_time(pid), started)
    if verdict:
        return verdict

    def exited(seconds: float) -> bool:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if process_start_time(pid) != started:
                return True
            time.sleep(0.5)
        return process_start_time(pid) != started

    try:
        _kill(pid, signal.SIGTERM)
        # `exited` checks the start time last, just before the SIGKILL.
        if exited(timeout):
            return Stop("stopped")
        _kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        return Stop("stopped")
    if exited(KILL_WAIT):
        return Stop("killed")
    return Stop("failed", f"PID {pid} was still running {KILL_WAIT:.0f} s after SIGKILL")


# ── Windows: process handles ──
#
# A process handle refers to one process for as long as it is open, and
# Windows doesn't reuse a PID while any handle to its process is open.

if sys.platform == "win32":
    import ctypes
    from ctypes import wintypes

    _k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _k32.OpenProcess.restype = wintypes.HANDLE
    _k32.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
    _k32.CloseHandle.argtypes = (wintypes.HANDLE,)
    _k32.GetProcessTimes.argtypes = (wintypes.HANDLE,) + (ctypes.POINTER(wintypes.FILETIME),) * 4
    _k32.WaitForSingleObject.restype = wintypes.DWORD
    _k32.WaitForSingleObject.argtypes = (wintypes.HANDLE, wintypes.DWORD)
    _k32.TerminateProcess.argtypes = (wintypes.HANDLE, wintypes.UINT)
    _k32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    _k32.CreateToolhelp32Snapshot.argtypes = (wintypes.DWORD, wintypes.DWORD)

    class _ProcessEntry(ctypes.Structure):
        _fields_ = [
            ("dwSize", wintypes.DWORD),
            ("cntUsage", wintypes.DWORD),
            ("th32ProcessID", wintypes.DWORD),
            ("th32DefaultHeapID", ctypes.c_size_t),
            ("th32ModuleID", wintypes.DWORD),
            ("cntThreads", wintypes.DWORD),
            ("th32ParentProcessID", wintypes.DWORD),
            ("pcPriClassBase", wintypes.LONG),
            ("dwFlags", wintypes.DWORD),
            ("szExeFile", wintypes.WCHAR * 260),
        ]

    _k32.Process32FirstW.argtypes = (wintypes.HANDLE, ctypes.POINTER(_ProcessEntry))
    _k32.Process32NextW.argtypes = (wintypes.HANDLE, ctypes.POINTER(_ProcessEntry))

    _SYNCHRONIZE = 0x00100000
    _WIN_QUERY = 0x1000 | _SYNCHRONIZE  # PROCESS_QUERY_LIMITED_INFORMATION
    _WIN_STOP = _WIN_QUERY | 0x0001  # PROCESS_TERMINATE
    _INVALID_HANDLE = wintypes.HANDLE(-1).value
    _WAIT_TIMEOUT = 0x102


def _win_open(pid: int, access: int):
    """A handle on process ``pid``, None if there is none, or ``_NOT_THIS_USERS``."""
    handle = _k32.OpenProcess(access, False, pid)
    if handle:
        return handle
    error = ctypes.get_last_error()
    if error == 87:  # ERROR_INVALID_PARAMETER: no such process
        return None
    if error == 5:  # ERROR_ACCESS_DENIED
        return _NOT_THIS_USERS
    raise CannotCheck(f"can't open PID {pid}: {ctypes.WinError(error)}")


def _win_created(handle) -> str | None:
    """When the process started, in 100 ns units, or None if it has exited."""
    if _k32.WaitForSingleObject(handle, 0) != _WAIT_TIMEOUT:
        return None
    created, exited, kernel, user = (wintypes.FILETIME() for _ in range(4))
    if not _k32.GetProcessTimes(handle, ctypes.byref(created), ctypes.byref(exited),
                                ctypes.byref(kernel), ctypes.byref(user)):
        raise CannotCheck(f"can't read a start time: {ctypes.WinError(ctypes.get_last_error())}")
    return str(created.dwHighDateTime << 32 | created.dwLowDateTime)


def _win_children() -> dict[int, list[int]]:
    """Each running process's PID, keyed by the PID of the process that started it."""
    snapshot = _k32.CreateToolhelp32Snapshot(0x2, 0)  # TH32CS_SNAPPROCESS
    if snapshot == _INVALID_HANDLE:
        raise CannotCheck(f"can't list processes: {ctypes.WinError(ctypes.get_last_error())}")
    children: dict[int, list[int]] = {}
    try:
        entry = _ProcessEntry()
        entry.dwSize = ctypes.sizeof(entry)
        more = _k32.Process32FirstW(snapshot, ctypes.byref(entry))
        while more:
            children.setdefault(entry.th32ParentProcessID, []).append(entry.th32ProcessID)
            more = _k32.Process32NextW(snapshot, ctypes.byref(entry))
    finally:
        _k32.CloseHandle(snapshot)
    return children


def _win_terminate(handle) -> None:
    _k32.TerminateProcess(handle, 1)


def _win_stop(pid: int, started: str | None) -> Stop:
    root = _win_open(pid, _WIN_STOP)
    if not isinstance(root, int):
        return _verdict(root, started)
    handles = [root]
    try:
        created = _win_created(root)
        verdict = _verdict(created, started)
        if verdict:
            return verdict
        # The processes it started, and theirs, each held by a handle before
        # it is checked. A process lists the PID of the one that started it,
        # which may since have exited and had its PID reused: so a child
        # counts only if it started after its parent.
        children = _win_children()
        tree = [(pid, int(created))]
        seen = {pid}
        while tree:
            parent, parent_created = tree.pop()
            for child in children.get(parent, []):
                if child in seen:
                    continue
                seen.add(child)
                handle = _win_open(child, _WIN_STOP)
                if not isinstance(handle, int):
                    continue
                child_created = _win_created(handle)
                if child_created is None or int(child_created) < parent_created:
                    _k32.CloseHandle(handle)
                    continue
                handles.append(handle)
                tree.append((child, int(child_created)))
        for handle in handles:
            _win_terminate(handle)
        deadline = time.monotonic() + KILL_WAIT
        for handle in handles:
            _k32.WaitForSingleObject(handle, max(0, int((deadline - time.monotonic()) * 1000)))
        alive = sum(_k32.WaitForSingleObject(h, 0) == _WAIT_TIMEOUT for h in handles)
        if alive:
            return Stop("failed", f"{alive} of its {len(handles)} processes were still running"
                                  f" {KILL_WAIT:.0f} s after they were killed")
        return Stop("killed")
    finally:
        for handle in handles:
            _k32.CloseHandle(handle)


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
