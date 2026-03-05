"""``ant dev playground`` — Interactive Python REPL with pre-connected SDK client."""

from __future__ import annotations

import code
import sys


BANNER = """\
ant-sdk Playground
==================
Pre-loaded objects:
  client     - AntdClient (sync, {transport})
  aclient    - AsyncAntdClient (async, {transport})

All SDK types are imported:
  HealthStatus, PutResult, Pointer, PointerTarget, Scratchpad,
  GraphEntry, GraphDescendant, Register, Vault, Archive, ArchiveEntry

All exceptions are imported:
  AntdError, NotFoundError, BadRequestError, PaymentError, ...

Try:
  >>> status = client.health()
  >>> print(status.network)

  >>> result = client.data_put_public(b"hello playground!")
  >>> print(result.address)

  >>> data = client.data_get_public(result.address)
  >>> print(data.decode())
"""


def run(args) -> None:
    transport = args.transport

    try:
        from antd import (
            AntdClient,
            AsyncAntdClient,
            # Models
            HealthStatus,
            PutResult,
            Pointer,
            PointerTarget,
            Scratchpad,
            GraphEntry,
            GraphDescendant,
            Register,
            Vault,
            Archive,
            ArchiveEntry,
            # Exceptions
            AntdError,
            NotFoundError,
            AlreadyExistsError,
            BadRequestError,
            ForkError,
            InternalError,
            NetworkError,
            PaymentError,
            TooLargeError,
        )
    except ImportError:
        print("Error: antd package not installed.")
        print("Install it with: pip install antd[rest]")
        sys.exit(1)

    # Create clients
    client = AntdClient(transport=transport)
    aclient = AsyncAntdClient(transport=transport)

    # Test connection
    try:
        status = client.health()
        print(f"Connected to antd ({status.network} network)")
    except Exception as e:
        print(f"Warning: could not connect to antd daemon: {e}")
        print("The client is still available but calls will fail until antd is running.")
        print()

    # Build namespace
    namespace = {
        "client": client,
        "aclient": aclient,
        # Models
        "HealthStatus": HealthStatus,
        "PutResult": PutResult,
        "Pointer": Pointer,
        "PointerTarget": PointerTarget,
        "Scratchpad": Scratchpad,
        "GraphEntry": GraphEntry,
        "GraphDescendant": GraphDescendant,
        "Register": Register,
        "Vault": Vault,
        "Archive": Archive,
        "ArchiveEntry": ArchiveEntry,
        # Exceptions
        "AntdError": AntdError,
        "NotFoundError": NotFoundError,
        "AlreadyExistsError": AlreadyExistsError,
        "BadRequestError": BadRequestError,
        "ForkError": ForkError,
        "InternalError": InternalError,
        "NetworkError": NetworkError,
        "PaymentError": PaymentError,
        "TooLargeError": TooLargeError,
        # Convenience
        "AntdClient": AntdClient,
        "AsyncAntdClient": AsyncAntdClient,
    }

    banner = BANNER.format(transport=transport)
    console = code.InteractiveConsole(locals=namespace)
    console.interact(banner=banner, exitmsg="Goodbye!")
