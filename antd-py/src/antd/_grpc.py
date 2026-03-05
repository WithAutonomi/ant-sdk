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
    Archive,
    ArchiveEntry,
    GraphDescendant,
    GraphEntry,
    HealthStatus,
    Pointer,
    PointerTarget,
    PutResult,
    Register,
    Scratchpad,
    Vault,
)

from antd._proto.antd.v1 import common_pb2
from antd._proto.antd.v1 import data_pb2, data_pb2_grpc
from antd._proto.antd.v1 import chunks_pb2, chunks_pb2_grpc
from antd._proto.antd.v1 import pointers_pb2, pointers_pb2_grpc
from antd._proto.antd.v1 import scratchpads_pb2, scratchpads_pb2_grpc
from antd._proto.antd.v1 import graph_pb2, graph_pb2_grpc
from antd._proto.antd.v1 import registers_pb2, registers_pb2_grpc
from antd._proto.antd.v1 import vaults_pb2, vaults_pb2_grpc
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

    def __init__(self, target: str = "localhost:50051"):
        self._channel = grpc.insecure_channel(target)
        self._health = health_pb2_grpc.HealthServiceStub(self._channel)
        self._data = data_pb2_grpc.DataServiceStub(self._channel)
        self._chunks = chunks_pb2_grpc.ChunkServiceStub(self._channel)
        self._pointers = pointers_pb2_grpc.PointerServiceStub(self._channel)
        self._scratchpads = scratchpads_pb2_grpc.ScratchpadServiceStub(self._channel)
        self._graph = graph_pb2_grpc.GraphServiceStub(self._channel)
        self._registers = registers_pb2_grpc.RegisterServiceStub(self._channel)
        self._vaults = vaults_pb2_grpc.VaultServiceStub(self._channel)
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
            return HealthStatus(ok=resp.status == "ok", network=resp.network or "unknown")
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.UNAVAILABLE:
                return HealthStatus(ok=False, network="unknown")
            return HealthStatus(ok=True, network="unknown")

    # --- Data ---

    def data_put_public(self, data: bytes) -> PutResult:
        try:
            resp = self._data.PutPublic(data_pb2.PutPublicDataRequest(data=data))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def data_get_public(self, address: str) -> bytes:
        try:
            resp = self._data.GetPublic(data_pb2.GetPublicDataRequest(address=address))
            return resp.data
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def data_put_private(self, data: bytes) -> PutResult:
        try:
            resp = self._data.PutPrivate(data_pb2.PutPrivateDataRequest(data=data))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.data_map)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def data_get_private(self, data_map: str) -> bytes:
        try:
            resp = self._data.GetPrivate(data_pb2.GetPrivateDataRequest(data_map=data_map))
            return resp.data
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def data_cost(self, data: bytes) -> str:
        try:
            resp = self._data.GetCost(data_pb2.DataCostRequest(data=data))
            return resp.atto_tokens
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

    # --- Pointers ---

    def pointer_create(self, owner_secret_key: str, target: PointerTarget) -> PutResult:
        try:
            resp = self._pointers.Create(pointers_pb2.CreatePointerRequest(
                owner_secret_key=owner_secret_key,
                target=common_pb2.PointerTarget(kind=target.kind, address=target.address),
            ))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def pointer_get(self, address: str) -> Pointer:
        try:
            resp = self._pointers.Get(pointers_pb2.GetPointerRequest(address=address))
            return Pointer(
                address=resp.address,
                owner=resp.owner,
                counter=resp.counter,
                target=PointerTarget(kind=resp.target.kind, address=resp.target.address),
            )
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def pointer_exists(self, address: str) -> bool:
        try:
            resp = self._pointers.CheckExistence(pointers_pb2.CheckPointerRequest(address=address))
            return resp.exists
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.NOT_FOUND:
                return False
            _handle_rpc_error(e)

    def pointer_update(self, owner_secret_key: str, target: PointerTarget) -> None:
        try:
            self._pointers.Update(pointers_pb2.UpdatePointerRequest(
                owner_secret_key=owner_secret_key,
                target=common_pb2.PointerTarget(kind=target.kind, address=target.address),
            ))
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def pointer_cost(self, public_key: str) -> str:
        try:
            resp = self._pointers.GetCost(pointers_pb2.PointerCostRequest(public_key=public_key))
            return resp.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Scratchpads ---

    def scratchpad_create(self, owner_secret_key: str, content_type: int, data: bytes) -> PutResult:
        try:
            resp = self._scratchpads.Create(scratchpads_pb2.CreateScratchpadRequest(
                owner_secret_key=owner_secret_key,
                content_type=content_type,
                data=data,
            ))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def scratchpad_get(self, address: str) -> Scratchpad:
        try:
            resp = self._scratchpads.Get(scratchpads_pb2.GetScratchpadRequest(address=address))
            return Scratchpad(
                address=resp.address,
                data_encoding=resp.data_encoding,
                data=resp.data,
                counter=resp.counter,
            )
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def scratchpad_exists(self, address: str) -> bool:
        try:
            resp = self._scratchpads.CheckExistence(
                scratchpads_pb2.CheckScratchpadRequest(address=address))
            return resp.exists
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.NOT_FOUND:
                return False
            _handle_rpc_error(e)

    def scratchpad_update(self, owner_secret_key: str, content_type: int, data: bytes) -> None:
        try:
            self._scratchpads.Update(scratchpads_pb2.UpdateScratchpadRequest(
                owner_secret_key=owner_secret_key,
                content_type=content_type,
                data=data,
            ))
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def scratchpad_cost(self, public_key: str) -> str:
        try:
            resp = self._scratchpads.GetCost(
                scratchpads_pb2.ScratchpadCostRequest(public_key=public_key))
            return resp.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Graph ---

    def graph_entry_put(self, owner_secret_key: str, parents: list[str], content: str,
                        descendants: list[GraphDescendant]) -> PutResult:
        try:
            resp = self._graph.Put(graph_pb2.PutGraphEntryRequest(
                owner_secret_key=owner_secret_key,
                parents=parents,
                content=content,
                descendants=[
                    common_pb2.GraphDescendant(public_key=d.public_key, content=d.content)
                    for d in descendants
                ],
            ))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def graph_entry_get(self, address: str) -> GraphEntry:
        try:
            resp = self._graph.Get(graph_pb2.GetGraphEntryRequest(address=address))
            return GraphEntry(
                owner=resp.owner,
                parents=list(resp.parents),
                content=resp.content,
                descendants=[
                    GraphDescendant(public_key=d.public_key, content=d.content)
                    for d in resp.descendants
                ],
            )
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def graph_entry_exists(self, address: str) -> bool:
        try:
            resp = self._graph.CheckExistence(graph_pb2.CheckGraphEntryRequest(address=address))
            return resp.exists
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.NOT_FOUND:
                return False
            _handle_rpc_error(e)

    def graph_entry_cost(self, public_key: str) -> str:
        try:
            resp = self._graph.GetCost(graph_pb2.GraphEntryCostRequest(public_key=public_key))
            return resp.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Registers ---

    def register_create(self, owner_secret_key: str, initial_value: str) -> PutResult:
        try:
            resp = self._registers.Create(registers_pb2.CreateRegisterRequest(
                owner_secret_key=owner_secret_key,
                initial_value=initial_value,
            ))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def register_get(self, address: str) -> Register:
        try:
            resp = self._registers.Get(registers_pb2.GetRegisterRequest(address=address))
            return Register(value=resp.value)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def register_update(self, owner_secret_key: str, new_value: str) -> PutResult:
        try:
            resp = self._registers.Update(registers_pb2.UpdateRegisterRequest(
                owner_secret_key=owner_secret_key,
                new_value=new_value,
            ))
            return PutResult(cost=resp.cost.atto_tokens, address="")
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def register_cost(self, public_key: str) -> str:
        try:
            resp = self._registers.GetCost(registers_pb2.RegisterCostRequest(public_key=public_key))
            return resp.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Vaults ---

    def vault_get(self, secret_key: str) -> Vault:
        try:
            resp = self._vaults.Get(vaults_pb2.GetVaultRequest(secret_key=secret_key))
            return Vault(data=resp.data, content_type=resp.content_type)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def vault_put(self, secret_key: str, data: bytes, content_type: int) -> str:
        try:
            resp = self._vaults.Put(vaults_pb2.PutVaultRequest(
                secret_key=secret_key,
                data=data,
                content_type=content_type,
            ))
            return resp.cost.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def vault_cost(self, secret_key: str, max_size: int) -> str:
        try:
            resp = self._vaults.GetCost(vaults_pb2.VaultCostRequest(
                secret_key=secret_key,
                max_size=max_size,
            ))
            return resp.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Files ---

    def file_upload_public(self, path: str) -> PutResult:
        try:
            resp = self._files.UploadPublic(files_pb2.UploadFileRequest(path=path))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def file_download_public(self, address: str, dest_path: str) -> None:
        try:
            self._files.DownloadPublic(files_pb2.DownloadPublicRequest(
                address=address, dest_path=dest_path))
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def dir_upload_public(self, path: str) -> PutResult:
        try:
            resp = self._files.DirUploadPublic(files_pb2.UploadFileRequest(path=path))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def dir_download_public(self, address: str, dest_path: str) -> None:
        try:
            self._files.DirDownloadPublic(files_pb2.DownloadPublicRequest(
                address=address, dest_path=dest_path))
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def archive_get_public(self, address: str) -> Archive:
        try:
            resp = self._files.ArchiveGetPublic(files_pb2.ArchiveGetRequest(address=address))
            entries = [
                ArchiveEntry(
                    path=e.path, address=e.address,
                    created=e.created, modified=e.modified, size=e.size,
                )
                for e in resp.entries
            ]
            return Archive(entries=entries)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def archive_put_public(self, archive: Archive) -> PutResult:
        try:
            pb_entries = [
                files_pb2.ArchiveEntry(
                    path=e.path, address=e.address,
                    created=e.created, modified=e.modified, size=e.size,
                )
                for e in archive.entries
            ]
            resp = self._files.ArchivePutPublic(files_pb2.ArchivePutRequest(entries=pb_entries))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    def file_cost(self, path: str, is_public: bool = True, include_archive: bool = False) -> str:
        try:
            resp = self._files.GetFileCost(files_pb2.FileCostRequest(
                path=path, is_public=is_public, include_archive=include_archive))
            return resp.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)


class AsyncGrpcClient:
    """Asynchronous gRPC client for the antd daemon."""

    def __init__(self, target: str = "localhost:50051"):
        self._channel = grpc.aio.insecure_channel(target)
        self._health = health_pb2_grpc.HealthServiceStub(self._channel)
        self._data = data_pb2_grpc.DataServiceStub(self._channel)
        self._chunks = chunks_pb2_grpc.ChunkServiceStub(self._channel)
        self._pointers = pointers_pb2_grpc.PointerServiceStub(self._channel)
        self._scratchpads = scratchpads_pb2_grpc.ScratchpadServiceStub(self._channel)
        self._graph = graph_pb2_grpc.GraphServiceStub(self._channel)
        self._registers = registers_pb2_grpc.RegisterServiceStub(self._channel)
        self._vaults = vaults_pb2_grpc.VaultServiceStub(self._channel)
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
            return HealthStatus(ok=resp.status == "ok", network=resp.network or "unknown")
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.UNAVAILABLE:
                return HealthStatus(ok=False, network="unknown")
            return HealthStatus(ok=True, network="unknown")

    # --- Data ---

    async def data_put_public(self, data: bytes) -> PutResult:
        try:
            resp = await self._data.PutPublic(data_pb2.PutPublicDataRequest(data=data))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def data_get_public(self, address: str) -> bytes:
        try:
            resp = await self._data.GetPublic(data_pb2.GetPublicDataRequest(address=address))
            return resp.data
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def data_put_private(self, data: bytes) -> PutResult:
        try:
            resp = await self._data.PutPrivate(data_pb2.PutPrivateDataRequest(data=data))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.data_map)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def data_get_private(self, data_map: str) -> bytes:
        try:
            resp = await self._data.GetPrivate(data_pb2.GetPrivateDataRequest(data_map=data_map))
            return resp.data
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def data_cost(self, data: bytes) -> str:
        try:
            resp = await self._data.GetCost(data_pb2.DataCostRequest(data=data))
            return resp.atto_tokens
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

    # --- Pointers ---

    async def pointer_create(self, owner_secret_key: str, target: PointerTarget) -> PutResult:
        try:
            resp = await self._pointers.Create(pointers_pb2.CreatePointerRequest(
                owner_secret_key=owner_secret_key,
                target=common_pb2.PointerTarget(kind=target.kind, address=target.address),
            ))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def pointer_get(self, address: str) -> Pointer:
        try:
            resp = await self._pointers.Get(pointers_pb2.GetPointerRequest(address=address))
            return Pointer(
                address=resp.address,
                owner=resp.owner,
                counter=resp.counter,
                target=PointerTarget(kind=resp.target.kind, address=resp.target.address),
            )
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def pointer_exists(self, address: str) -> bool:
        try:
            resp = await self._pointers.CheckExistence(
                pointers_pb2.CheckPointerRequest(address=address))
            return resp.exists
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.NOT_FOUND:
                return False
            _handle_rpc_error(e)

    async def pointer_update(self, owner_secret_key: str, target: PointerTarget) -> None:
        try:
            await self._pointers.Update(pointers_pb2.UpdatePointerRequest(
                owner_secret_key=owner_secret_key,
                target=common_pb2.PointerTarget(kind=target.kind, address=target.address),
            ))
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def pointer_cost(self, public_key: str) -> str:
        try:
            resp = await self._pointers.GetCost(
                pointers_pb2.PointerCostRequest(public_key=public_key))
            return resp.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Scratchpads ---

    async def scratchpad_create(self, owner_secret_key: str, content_type: int,
                                data: bytes) -> PutResult:
        try:
            resp = await self._scratchpads.Create(scratchpads_pb2.CreateScratchpadRequest(
                owner_secret_key=owner_secret_key,
                content_type=content_type,
                data=data,
            ))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def scratchpad_get(self, address: str) -> Scratchpad:
        try:
            resp = await self._scratchpads.Get(
                scratchpads_pb2.GetScratchpadRequest(address=address))
            return Scratchpad(
                address=resp.address,
                data_encoding=resp.data_encoding,
                data=resp.data,
                counter=resp.counter,
            )
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def scratchpad_exists(self, address: str) -> bool:
        try:
            resp = await self._scratchpads.CheckExistence(
                scratchpads_pb2.CheckScratchpadRequest(address=address))
            return resp.exists
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.NOT_FOUND:
                return False
            _handle_rpc_error(e)

    async def scratchpad_update(self, owner_secret_key: str, content_type: int,
                                data: bytes) -> None:
        try:
            await self._scratchpads.Update(scratchpads_pb2.UpdateScratchpadRequest(
                owner_secret_key=owner_secret_key,
                content_type=content_type,
                data=data,
            ))
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def scratchpad_cost(self, public_key: str) -> str:
        try:
            resp = await self._scratchpads.GetCost(
                scratchpads_pb2.ScratchpadCostRequest(public_key=public_key))
            return resp.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Graph ---

    async def graph_entry_put(self, owner_secret_key: str, parents: list[str], content: str,
                              descendants: list[GraphDescendant]) -> PutResult:
        try:
            resp = await self._graph.Put(graph_pb2.PutGraphEntryRequest(
                owner_secret_key=owner_secret_key,
                parents=parents,
                content=content,
                descendants=[
                    common_pb2.GraphDescendant(public_key=d.public_key, content=d.content)
                    for d in descendants
                ],
            ))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def graph_entry_get(self, address: str) -> GraphEntry:
        try:
            resp = await self._graph.Get(graph_pb2.GetGraphEntryRequest(address=address))
            return GraphEntry(
                owner=resp.owner,
                parents=list(resp.parents),
                content=resp.content,
                descendants=[
                    GraphDescendant(public_key=d.public_key, content=d.content)
                    for d in resp.descendants
                ],
            )
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def graph_entry_exists(self, address: str) -> bool:
        try:
            resp = await self._graph.CheckExistence(
                graph_pb2.CheckGraphEntryRequest(address=address))
            return resp.exists
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.NOT_FOUND:
                return False
            _handle_rpc_error(e)

    async def graph_entry_cost(self, public_key: str) -> str:
        try:
            resp = await self._graph.GetCost(
                graph_pb2.GraphEntryCostRequest(public_key=public_key))
            return resp.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Registers ---

    async def register_create(self, owner_secret_key: str, initial_value: str) -> PutResult:
        try:
            resp = await self._registers.Create(registers_pb2.CreateRegisterRequest(
                owner_secret_key=owner_secret_key,
                initial_value=initial_value,
            ))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def register_get(self, address: str) -> Register:
        try:
            resp = await self._registers.Get(registers_pb2.GetRegisterRequest(address=address))
            return Register(value=resp.value)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def register_update(self, owner_secret_key: str, new_value: str) -> PutResult:
        try:
            resp = await self._registers.Update(registers_pb2.UpdateRegisterRequest(
                owner_secret_key=owner_secret_key,
                new_value=new_value,
            ))
            return PutResult(cost=resp.cost.atto_tokens, address="")
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def register_cost(self, public_key: str) -> str:
        try:
            resp = await self._registers.GetCost(
                registers_pb2.RegisterCostRequest(public_key=public_key))
            return resp.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Vaults ---

    async def vault_get(self, secret_key: str) -> Vault:
        try:
            resp = await self._vaults.Get(vaults_pb2.GetVaultRequest(secret_key=secret_key))
            return Vault(data=resp.data, content_type=resp.content_type)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def vault_put(self, secret_key: str, data: bytes, content_type: int) -> str:
        try:
            resp = await self._vaults.Put(vaults_pb2.PutVaultRequest(
                secret_key=secret_key,
                data=data,
                content_type=content_type,
            ))
            return resp.cost.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def vault_cost(self, secret_key: str, max_size: int) -> str:
        try:
            resp = await self._vaults.GetCost(vaults_pb2.VaultCostRequest(
                secret_key=secret_key,
                max_size=max_size,
            ))
            return resp.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    # --- Files ---

    async def file_upload_public(self, path: str) -> PutResult:
        try:
            resp = await self._files.UploadPublic(files_pb2.UploadFileRequest(path=path))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def file_download_public(self, address: str, dest_path: str) -> None:
        try:
            await self._files.DownloadPublic(files_pb2.DownloadPublicRequest(
                address=address, dest_path=dest_path))
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def dir_upload_public(self, path: str) -> PutResult:
        try:
            resp = await self._files.DirUploadPublic(files_pb2.UploadFileRequest(path=path))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def dir_download_public(self, address: str, dest_path: str) -> None:
        try:
            await self._files.DirDownloadPublic(files_pb2.DownloadPublicRequest(
                address=address, dest_path=dest_path))
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def archive_get_public(self, address: str) -> Archive:
        try:
            resp = await self._files.ArchiveGetPublic(
                files_pb2.ArchiveGetRequest(address=address))
            entries = [
                ArchiveEntry(
                    path=e.path, address=e.address,
                    created=e.created, modified=e.modified, size=e.size,
                )
                for e in resp.entries
            ]
            return Archive(entries=entries)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def archive_put_public(self, archive: Archive) -> PutResult:
        try:
            pb_entries = [
                files_pb2.ArchiveEntry(
                    path=e.path, address=e.address,
                    created=e.created, modified=e.modified, size=e.size,
                )
                for e in archive.entries
            ]
            resp = await self._files.ArchivePutPublic(
                files_pb2.ArchivePutRequest(entries=pb_entries))
            return PutResult(cost=resp.cost.atto_tokens, address=resp.address)
        except grpc.RpcError as e:
            _handle_rpc_error(e)

    async def file_cost(self, path: str, is_public: bool = True,
                        include_archive: bool = False) -> str:
        try:
            resp = await self._files.GetFileCost(files_pb2.FileCostRequest(
                path=path, is_public=is_public, include_archive=include_archive))
            return resp.atto_tokens
        except grpc.RpcError as e:
            _handle_rpc_error(e)
