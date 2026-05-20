"""gRPC transport clients (sync and async) for antd daemon."""

from __future__ import annotations

import grpc
import grpc.aio

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
from .models import (
    DataPutPublicResult,
    DataPutResult,
    FilePutPublicResult,
    FilePutResult,
    HealthStatus,
    PaymentMode,
    PutResult,
    UploadCostEstimate,
)


def _health_status_from_resp(resp) -> HealthStatus:
    """Convert a HealthCheckResponse pb message into a HealthStatus."""
    return HealthStatus(
        ok=resp.status == "ok",
        network=resp.network or "unknown",
        version=resp.version,
        evm_network=resp.evm_network,
        uptime_seconds=resp.uptime_seconds,
        build_commit=resp.build_commit,
        payment_token_address=resp.payment_token_address,
        payment_vault_address=resp.payment_vault_address,
    )


def _file_put_result_from_resp(resp) -> FilePutResult:
    return FilePutResult(
        data_map=resp.data_map,
        storage_cost_atto=resp.storage_cost_atto,
        gas_cost_wei=resp.gas_cost_wei,
        chunks_stored=resp.chunks_stored,
        payment_mode_used=resp.payment_mode_used,
    )


def _file_put_public_result_from_resp(resp) -> FilePutPublicResult:
    return FilePutPublicResult(
        address=resp.address,
        storage_cost_atto=resp.storage_cost_atto,
        gas_cost_wei=resp.gas_cost_wei,
        chunks_stored=resp.chunks_stored,
        payment_mode_used=resp.payment_mode_used,
    )


def _estimate_from_cost(resp) -> UploadCostEstimate:
    """Convert a pb::Cost response (from GetCost / GetFileCost) into an estimate."""
    return UploadCostEstimate(
        cost=resp.atto_tokens,
        file_size=resp.file_size,
        chunk_count=resp.chunk_count,
        estimated_gas_cost_wei=resp.estimated_gas_cost_wei,
        payment_mode=resp.payment_mode,
    )

from antd._proto.antd.v1 import data_pb2, data_pb2_grpc
from antd._proto.antd.v1 import chunks_pb2, chunks_pb2_grpc
from antd._proto.antd.v1 import files_pb2, files_pb2_grpc
from antd._proto.antd.v1 import health_pb2, health_pb2_grpc


# gRPC status code -> exception class mapping
_GRPC_CODE_MAP: dict[grpc.StatusCode, type[AntdError]] = {
    grpc.StatusCode.NOT_FOUND: NotFoundError,
    grpc.StatusCode.ALREADY_EXISTS: AlreadyExistsError,
    grpc.StatusCode.ABORTED: ForkError,
    grpc.StatusCode.INVALID_ARGUMENT: BadRequestError,
    grpc.StatusCode.FAILED_PRECONDITION: PaymentError,
    grpc.StatusCode.UNAVAILABLE: NetworkError,
    grpc.StatusCode.RESOURCE_EXHAUSTED: TooLargeError,
    grpc.StatusCode.INTERNAL: InternalError,
}


def _handle_rpc_error(e: grpc.RpcError) -> None:
    code = e.code()
    details = e.details() or str(e)
    exc_class = _GRPC_CODE_MAP.get(code, AntdError)
    raise exc_class(details, code.value[0]) from e


class GrpcClient:
    """Synchronous gRPC client for the antd daemon."""

    DEFAULT_TARGET = "localhost:50051"

    @classmethod
    def auto_discover(cls, **kwargs) -> tuple["GrpcClient", str]:
        """Create a client using daemon port discovery, falling back to the default target.

        Returns:
            A tuple of ``(client, resolved_target)`` where *resolved_target* is
            the gRPC target that was actually used (discovered or default).
        """
        from ._discover import discover_grpc_target

        target = discover_grpc_target() or cls.DEFAULT_TARGET
        return cls(target=target, **kwargs), target

    def __init__(self, target: str = "localhost:50051"):
        self._channel = grpc.insecure_channel(target)
        self._health = health_pb2_grpc.HealthServiceStub(self._channel)
        self._data = data_pb2_grpc.DataServiceStub(self._channel)
        self._chunks = chunks_pb2_grpc.ChunkServiceStub(self._channel)
        self._files = files_pb2_grpc.FileServiceStub(self._channel)

    def close(self) -> None:
        self._channel.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    # --- Health ---

    def health(self) -> HealthStatus:
        try:
            resp = self._health.Check(health_pb2.HealthCheckRequest())
            return _health_status_from_resp(resp)
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.UNAVAILABLE:
                return HealthStatus(ok=False, network="unknown")
            return HealthStatus(ok=True, network="unknown")

    # --- Data ---

    def data_put(self, data: bytes, payment_mode: PaymentMode = PaymentMode.AUTO) -> DataPutResult:
        """Store private encrypted data. Returns the caller-held DataMap (hex)."""
        try:
            resp = self._data.Put(data_pb2.PutDataRequest(data=data, payment_mode=payment_mode.value))
            return DataPutResult(data_map=resp.data_map)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def data_get(self, data_map: str) -> bytes:
        """Retrieve private data from a caller-held DataMap (hex)."""
        try:
            resp = self._data.Get(data_pb2.GetDataRequest(data_map=data_map))
            return resp.data
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def data_put_public(self, data: bytes, payment_mode: PaymentMode = PaymentMode.AUTO) -> DataPutPublicResult:
        """Store public data. Returns the on-network DataMap address."""
        try:
            resp = self._data.PutPublic(data_pb2.PutPublicDataRequest(data=data, payment_mode=payment_mode.value))
            return DataPutPublicResult(address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def data_get_public(self, address: str) -> bytes:
        try:
            resp = self._data.GetPublic(data_pb2.GetPublicDataRequest(address=address))
            return resp.data
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def data_cost(self, data: bytes, payment_mode: PaymentMode = PaymentMode.AUTO) -> UploadCostEstimate:
        """Pre-upload cost breakdown for the given bytes."""
        try:
            resp = self._data.Cost(data_pb2.DataCostRequest(data=data, payment_mode=payment_mode.value))
            return _estimate_from_cost(resp)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Chunks ---

    def chunk_put(self, data: bytes) -> PutResult:
        try:
            resp = self._chunks.Put(chunks_pb2.PutChunkRequest(data=data))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def chunk_get(self, address: str) -> bytes:
        try:
            resp = self._chunks.Get(chunks_pb2.GetChunkRequest(address=address))
            return resp.data
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Files ---

    def file_put(self, path: str, payment_mode: PaymentMode = PaymentMode.AUTO) -> FilePutResult:
        """Upload a file privately. Returns the caller-held DataMap (hex)."""
        try:
            resp = self._files.Put(files_pb2.PutFileRequest(path=path, payment_mode=payment_mode.value))
            return _file_put_result_from_resp(resp)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def file_get(self, data_map: str, dest_path: str) -> None:
        """Download a private file from a caller-held DataMap."""
        try:
            self._files.Get(files_pb2.GetFileRequest(data_map=data_map, dest_path=dest_path))
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def file_put_public(self, path: str, payment_mode: PaymentMode = PaymentMode.AUTO) -> FilePutPublicResult:
        """Upload a file publicly. Returns the on-network DataMap address."""
        try:
            resp = self._files.PutPublic(files_pb2.PutFileRequest(path=path, payment_mode=payment_mode.value))
            return _file_put_public_result_from_resp(resp)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def file_get_public(self, address: str, dest_path: str) -> None:
        """Download a public file from an on-network DataMap address."""
        try:
            self._files.GetPublic(files_pb2.GetFilePublicRequest(address=address, dest_path=dest_path))
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def file_cost(self, path: str, is_public: bool = True, payment_mode: PaymentMode = PaymentMode.AUTO) -> UploadCostEstimate:
        """Pre-upload cost breakdown for the file at ``path``."""
        try:
            resp = self._files.Cost(files_pb2.FileCostRequest(
                path=path, is_public=is_public, payment_mode=payment_mode.value))
            return _estimate_from_cost(resp)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Wallet (not yet available via gRPC) ---

    def wallet_address(self):
        raise NotImplementedError("wallet_address is not yet supported via gRPC")

    def wallet_balance(self):
        raise NotImplementedError("wallet_balance is not yet supported via gRPC")

    def wallet_approve(self) -> bool:
        raise NotImplementedError("wallet_approve is not yet supported via gRPC")

    # --- External Signer (not yet available via gRPC) ---

    def prepare_upload(self, path: str):
        raise NotImplementedError("prepare_upload is not yet supported via gRPC")

    def prepare_data_upload(self, data: bytes):
        raise NotImplementedError("prepare_data_upload is not yet supported via gRPC")

    def finalize_upload(self, upload_id: str, tx_hashes: dict):
        raise NotImplementedError("finalize_upload is not yet supported via gRPC")


class AsyncGrpcClient:
    """Asynchronous gRPC client for the antd daemon."""

    DEFAULT_TARGET = "localhost:50051"

    @classmethod
    def auto_discover(cls, **kwargs) -> tuple["AsyncGrpcClient", str]:
        """Create a client using daemon port discovery, falling back to the default target.

        Returns:
            A tuple of ``(client, resolved_target)`` where *resolved_target* is
            the gRPC target that was actually used (discovered or default).
        """
        from ._discover import discover_grpc_target

        target = discover_grpc_target() or cls.DEFAULT_TARGET
        return cls(target=target, **kwargs), target

    def __init__(self, target: str = "localhost:50051"):
        self._channel = grpc.aio.insecure_channel(target)
        self._health = health_pb2_grpc.HealthServiceStub(self._channel)
        self._data = data_pb2_grpc.DataServiceStub(self._channel)
        self._chunks = chunks_pb2_grpc.ChunkServiceStub(self._channel)
        self._files = files_pb2_grpc.FileServiceStub(self._channel)

    async def close(self) -> None:
        await self._channel.close()

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        await self.close()

    # --- Health ---

    async def health(self) -> HealthStatus:
        try:
            resp = await self._health.Check(health_pb2.HealthCheckRequest())
            return _health_status_from_resp(resp)
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.UNAVAILABLE:
                return HealthStatus(ok=False, network="unknown")
            return HealthStatus(ok=True, network="unknown")

    # --- Data ---

    async def data_put(self, data: bytes, payment_mode: PaymentMode = PaymentMode.AUTO) -> DataPutResult:
        """Store private encrypted data. Returns the caller-held DataMap (hex)."""
        try:
            resp = await self._data.Put(data_pb2.PutDataRequest(data=data, payment_mode=payment_mode.value))
            return DataPutResult(data_map=resp.data_map)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def data_get(self, data_map: str) -> bytes:
        """Retrieve private data from a caller-held DataMap (hex)."""
        try:
            resp = await self._data.Get(data_pb2.GetDataRequest(data_map=data_map))
            return resp.data
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def data_put_public(self, data: bytes, payment_mode: PaymentMode = PaymentMode.AUTO) -> DataPutPublicResult:
        """Store public data. Returns the on-network DataMap address."""
        try:
            resp = await self._data.PutPublic(data_pb2.PutPublicDataRequest(data=data, payment_mode=payment_mode.value))
            return DataPutPublicResult(address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def data_get_public(self, address: str) -> bytes:
        try:
            resp = await self._data.GetPublic(data_pb2.GetPublicDataRequest(address=address))
            return resp.data
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def data_cost(self, data: bytes, payment_mode: PaymentMode = PaymentMode.AUTO) -> UploadCostEstimate:
        """Pre-upload cost breakdown for the given bytes."""
        try:
            resp = await self._data.Cost(data_pb2.DataCostRequest(data=data, payment_mode=payment_mode.value))
            return _estimate_from_cost(resp)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Chunks ---

    async def chunk_put(self, data: bytes) -> PutResult:
        try:
            resp = await self._chunks.Put(chunks_pb2.PutChunkRequest(data=data))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def chunk_get(self, address: str) -> bytes:
        try:
            resp = await self._chunks.Get(chunks_pb2.GetChunkRequest(address=address))
            return resp.data
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Files ---

    async def file_put(self, path: str, payment_mode: PaymentMode = PaymentMode.AUTO) -> FilePutResult:
        """Upload a file privately. Returns the caller-held DataMap (hex)."""
        try:
            resp = await self._files.Put(files_pb2.PutFileRequest(path=path, payment_mode=payment_mode.value))
            return _file_put_result_from_resp(resp)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def file_get(self, data_map: str, dest_path: str) -> None:
        """Download a private file from a caller-held DataMap."""
        try:
            await self._files.Get(files_pb2.GetFileRequest(data_map=data_map, dest_path=dest_path))
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def file_put_public(self, path: str, payment_mode: PaymentMode = PaymentMode.AUTO) -> FilePutPublicResult:
        """Upload a file publicly. Returns the on-network DataMap address."""
        try:
            resp = await self._files.PutPublic(files_pb2.PutFileRequest(path=path, payment_mode=payment_mode.value))
            return _file_put_public_result_from_resp(resp)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def file_get_public(self, address: str, dest_path: str) -> None:
        """Download a public file from an on-network DataMap address."""
        try:
            await self._files.GetPublic(files_pb2.GetFilePublicRequest(address=address, dest_path=dest_path))
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def file_cost(self, path: str, is_public: bool = True, payment_mode: PaymentMode = PaymentMode.AUTO) -> UploadCostEstimate:
        """Pre-upload cost breakdown for the file at ``path``."""
        try:
            resp = await self._files.Cost(files_pb2.FileCostRequest(
                path=path, is_public=is_public, payment_mode=payment_mode.value))
            return _estimate_from_cost(resp)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Wallet (not yet available via gRPC) ---

    async def wallet_address(self):
        raise NotImplementedError("wallet_address is not yet supported via gRPC")

    async def wallet_balance(self):
        raise NotImplementedError("wallet_balance is not yet supported via gRPC")

    async def wallet_approve(self) -> bool:
        raise NotImplementedError("wallet_approve is not yet supported via gRPC")

    # --- External Signer (not yet available via gRPC) ---

    async def prepare_upload(self, path: str):
        raise NotImplementedError("prepare_upload is not yet supported via gRPC")

    async def prepare_data_upload(self, data: bytes):
        raise NotImplementedError("prepare_data_upload is not yet supported via gRPC")

    async def finalize_upload(self, upload_id: str, tx_hashes: dict):
        raise NotImplementedError("finalize_upload is not yet supported via gRPC")
