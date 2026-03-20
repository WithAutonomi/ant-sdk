"""``ant dev reset`` — Stop + restart."""

from __future__ import annotations


def run(args) -> None:
    # 1. Stop
    print("Stopping environment...")
    from .cmd_stop import run as stop_run

    class _FakeArgs:
        pass

    stop_run(_FakeArgs())

    # 2. Restart
    print("\nRestarting environment...")
    from .cmd_start import run as start_run

    class _StartArgs:
        saorsa_node_dir = None
        no_build = False
        enable_evm = False

    start_run(_StartArgs())
