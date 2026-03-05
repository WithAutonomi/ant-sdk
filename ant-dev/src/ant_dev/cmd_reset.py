"""``ant dev reset`` — Stop + clear bootstrap cache + restart."""

from __future__ import annotations

import shutil
import sys

from .env import bootstrap_cache_path


def run(args) -> None:
    # 1. Stop
    print("Stopping environment...")
    from .cmd_stop import run as stop_run

    class _FakeArgs:
        pass

    stop_run(_FakeArgs())

    # 2. Clear bootstrap cache
    cache = bootstrap_cache_path()
    cache_dir = cache.parent
    if cache_dir.exists():
        shutil.rmtree(cache_dir, ignore_errors=True)
        print(f"Cleared bootstrap cache: {cache_dir}")

    # 3. Restart
    print("\nRestarting environment...")
    from .cmd_start import run as start_run

    class _StartArgs:
        autonomi_dir = None
        no_build = False

    start_run(_StartArgs())
