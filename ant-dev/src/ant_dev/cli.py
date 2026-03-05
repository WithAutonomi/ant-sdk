"""CLI dispatcher for the ``ant`` command."""

from __future__ import annotations

import argparse
import sys


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="ant",
        description="Developer CLI for ant-sdk",
    )
    sub = parser.add_subparsers(dest="command")

    # ── dev ──
    dev = sub.add_parser("dev", help="Local development environment commands")
    dev_sub = dev.add_subparsers(dest="subcommand")

    # ant dev start
    p = dev_sub.add_parser("start", help="Start EVM testnet + local network + antd")
    p.add_argument("--autonomi-dir", help="Path to autonomi repo")
    p.add_argument("--no-build", action="store_true", help="Skip --build flag for antctl")

    # ant dev stop
    dev_sub.add_parser("stop", help="Tear down all local processes")

    # ant dev status
    dev_sub.add_parser("status", help="Show running processes and health")

    # ant dev example
    p = dev_sub.add_parser("example", help="Run a named example")
    p.add_argument("name", help="Example name: connect, data, chunks, files, pointers, scratchpads, graph, registers, vaults, private, all")
    p.add_argument("-l", "--language", default="python", choices=["python", "csharp"], help="Language (default: python)")

    # ant dev init
    p = dev_sub.add_parser("init", help="Scaffold a new project")
    p.add_argument("language", choices=["python", "csharp"], help="Project language")
    p.add_argument("--name", default="my-ant-project", help="Project name")
    p.add_argument("--dir", help="Output directory (default: ./<name>)")

    # ant dev wallet
    p = dev_sub.add_parser("wallet", help="Show or fund test wallet")
    p.add_argument("action", nargs="?", default="show", choices=["show", "fund"], help="Action (default: show)")

    # ant dev logs
    p = dev_sub.add_parser("logs", help="Show antd logs")
    p.add_argument("--follow", "-f", action="store_true", help="Stream logs continuously")

    # ant dev reset
    dev_sub.add_parser("reset", help="Stop + clean cache + restart")

    # ant dev playground
    p = dev_sub.add_parser("playground", help="Interactive Python REPL with SDK")
    p.add_argument("--transport", default="rest", choices=["rest", "grpc"], help="Transport (default: rest)")

    args = parser.parse_args(argv)

    if args.command != "dev":
        parser.print_help()
        sys.exit(1)

    if not args.subcommand:
        dev.print_help()
        sys.exit(1)

    # Dispatch to subcommand module
    if args.subcommand == "start":
        from .cmd_start import run
        run(args)
    elif args.subcommand == "stop":
        from .cmd_stop import run
        run(args)
    elif args.subcommand == "status":
        from .cmd_status import run
        run(args)
    elif args.subcommand == "example":
        from .cmd_example import run
        run(args)
    elif args.subcommand == "init":
        from .cmd_init import run
        run(args)
    elif args.subcommand == "wallet":
        from .cmd_wallet import run
        run(args)
    elif args.subcommand == "logs":
        from .cmd_logs import run
        run(args)
    elif args.subcommand == "reset":
        from .cmd_reset import run
        run(args)
    elif args.subcommand == "playground":
        from .cmd_playground import run
        run(args)


if __name__ == "__main__":
    main()
