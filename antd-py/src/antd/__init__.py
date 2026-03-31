"""Python SDK for the antd daemon (Autonomi network).

Provides REST and gRPC clients with identical APIs.

Usage:
    from antd import AntdClient
    client = AntdClient()  # REST by default
    result = client.data_put_public(b"hello")
    data = client.data_get_public(result.address)
"""

from __future__ import annotations

from .models import (
    Archive,
    ArchiveEntry,
    FinalizeUploadResult,
    HealthStatus,
    PaymentInfo,
    PrepareUploadResult,
    PutResult,
    WalletAddress,
    WalletBalance,
)
from ._discover import discover_daemon_url, discover_grpc_target
from .exceptions import (
    AntdError,
    AlreadyExistsError,
    BadRequestError,
    ForkError,
    InternalError,
    NetworkError,
    NotFoundError,
    PaymentError,
    TooLargeError,
)

__all__ = [
    # Discovery
    "discover_daemon_url",
    "discover_grpc_target",
    # Factory functions
    "AntdClient",
    "AsyncAntdClient",
    # Models
    "HealthStatus",
    "Archive",
    "ArchiveEntry",
    "PutResult",
    "WalletAddress",
    "WalletBalance",
    # Exceptions
    "AntdError",
    "AlreadyExistsError",
    "BadRequestError",
    "ForkError",
    "InternalError",
    "NetworkError",
    "NotFoundError",
    "PaymentError",
    "TooLargeError",
]


def AntdClient(transport: str = "rest", **kwargs):
    """Create a synchronous antd client.

    Args:
        transport: "rest" (default) or "grpc"
        **kwargs: Passed to the underlying client constructor.
            REST: base_url (default "http://localhost:8082"), timeout
            gRPC: target (default "localhost:50051")
    """
    if transport == "rest":
        from ._rest import RestClient
        return RestClient(**kwargs)
    elif transport == "grpc":
        from ._grpc import GrpcClient
        return GrpcClient(**kwargs)
    else:
        raise ValueError(f"Unknown transport: {transport!r}. Use 'rest' or 'grpc'.")


def AsyncAntdClient(transport: str = "rest", **kwargs):
    """Create an asynchronous antd client.

    Args:
        transport: "rest" (default) or "grpc"
        **kwargs: Passed to the underlying client constructor.
            REST: base_url (default "http://localhost:8082"), timeout
            gRPC: target (default "localhost:50051")
    """
    if transport == "rest":
        from ._rest import AsyncRestClient
        return AsyncRestClient(**kwargs)
    elif transport == "grpc":
        from ._grpc import AsyncGrpcClient
        return AsyncGrpcClient(**kwargs)
    else:
        raise ValueError(f"Unknown transport: {transport!r}. Use 'rest' or 'grpc'.")
