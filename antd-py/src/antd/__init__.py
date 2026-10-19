"""Python SDK for the antd daemon (Autonomi network).

Provides REST and gRPC clients with identical APIs.

Usage:
    from antd import AntdClient
    client = AntdClient()  # REST by default
    result = client.data_put_public(b"hello")
    data = client.data_get_public(result.address)
"""

from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version as _dist_version

try:
    __version__ = _dist_version("antd")
except PackageNotFoundError:  # running from a source checkout that is not installed
    __version__ = "0.0.0"

from .models import (
    POINTER_FINAL_COUNTER,
    CandidateNodeEntry,
    DataPutPublicResult,
    DataPutResult,
    DownloadFrame,
    DownloadProgress,
    FilePutPublicResult,
    FilePutResult,
    FinalizeUploadResult,
    HealthStatus,
    PaymentInfo,
    PaymentMode,
    PointerController,
    PointerFinality,
    PointerFinalityStatus,
    PointerFinalizeResult,
    PointerFinalState,
    PointerKind,
    PointerOp,
    PointerPrepareResult,
    PointerRecord,
    PointerTarget,
    PointerTransferResult,
    PointerWriteResult,
    PoolCommitmentEntry,
    PrepareChunkResult,
    PrepareUploadResult,
    PutResult,
    SignedQuoteEntry,
    UploadCostEstimate,
    WalletAddress,
    WalletBalance,
)
from ._discover import discover_daemon_url, discover_grpc_target
from .exceptions import (
    AntdError,
    AlreadyExistsError,
    BadRequestError,
    CloseGroupShortfallError,
    ConflictError,
    ForkError,
    InternalError,
    NetworkError,
    NotFoundError,
    PartialUploadError,
    PaymentError,
    PointerFinalError,
    PointerForkedError,
    TooLargeError,
)

__all__ = [
    "__version__",
    # Discovery
    "discover_daemon_url",
    "discover_grpc_target",
    # Factory functions
    "AntdClient",
    "AsyncAntdClient",
    # Models
    "CandidateNodeEntry",
    "DataPutPublicResult",
    "DataPutResult",
    "DownloadFrame",
    "DownloadProgress",
    "FilePutPublicResult",
    "FilePutResult",
    "FinalizeUploadResult",
    "HealthStatus",
    "PaymentInfo",
    "PaymentMode",
    "PoolCommitmentEntry",
    "PrepareChunkResult",
    "PrepareUploadResult",
    "PutResult",
    "SignedQuoteEntry",
    "UploadCostEstimate",
    "WalletAddress",
    "WalletBalance",
    # Pointers
    "POINTER_FINAL_COUNTER",
    "PointerController",
    "PointerFinalState",
    "PointerFinality",
    "PointerFinalityStatus",
    "PointerFinalizeResult",
    "PointerKind",
    "PointerOp",
    "PointerPrepareResult",
    "PointerRecord",
    "PointerTarget",
    "PointerTransferResult",
    "PointerWriteResult",
    # Exceptions
    "AntdError",
    "AlreadyExistsError",
    "BadRequestError",
    "CloseGroupShortfallError",
    "ConflictError",
    "ForkError",
    "InternalError",
    "NetworkError",
    "NotFoundError",
    "PartialUploadError",
    "PaymentError",
    "PointerFinalError",
    "PointerForkedError",
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
