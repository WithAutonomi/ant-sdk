"""REST transport clients (sync and async) for antd daemon."""

from __future__ import annotations

import base64
from typing import TYPE_CHECKING

import httpx

from .exceptions import raise_for_http_status
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

if TYPE_CHECKING:
    pass


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


def _unb64(s: str) -> bytes:
    return base64.b64decode(s)


def _check(resp: httpx.Response) -> None:
    if resp.is_success:
        return
    try:
        body = resp.json()
        msg = body.get("error", resp.text)
    except Exception:
        msg = resp.text
    raise_for_http_status(resp.status_code, msg)


class RestClient:
    """Synchronous REST client for the antd daemon."""

    def __init__(self, base_url: str = "http://localhost:8080", timeout: float = 300.0):
        self._base = base_url.rstrip("/")
        self._http = httpx.Client(base_url=self._base, timeout=timeout)

    def close(self) -> None:
        self._http.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    # --- Health ---

    def health(self) -> HealthStatus:
        resp = self._http.get("/health")
        _check(resp)
        j = resp.json()
        return HealthStatus(ok=j.get("status") == "ok", network=j.get("network", "unknown"))

    # --- Data ---

    def data_put_public(self, data: bytes) -> PutResult:
        resp = self._http.post("/v1/data/public", json={"data": _b64(data)})
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    def data_get_public(self, address: str) -> bytes:
        resp = self._http.get(f"/v1/data/public/{address}")
        _check(resp)
        return _unb64(resp.json()["data"])

    def data_put_private(self, data: bytes) -> PutResult:
        resp = self._http.post("/v1/data/private", json={"data": _b64(data)})
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["data_map"])

    def data_get_private(self, data_map: str) -> bytes:
        resp = self._http.get("/v1/data/private", params={"data_map": data_map})
        _check(resp)
        return _unb64(resp.json()["data"])

    def data_cost(self, data: bytes) -> str:
        resp = self._http.post("/v1/data/cost", json={"data": _b64(data)})
        _check(resp)
        return resp.json()["cost"]

    # --- Chunks ---

    def chunk_put(self, data: bytes) -> PutResult:
        resp = self._http.post("/v1/chunks", json={"data": _b64(data)})
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    def chunk_get(self, address: str) -> bytes:
        resp = self._http.get(f"/v1/chunks/{address}")
        _check(resp)
        return _unb64(resp.json()["data"])

    # --- Pointers ---

    def pointer_create(self, owner_secret_key: str, target: PointerTarget) -> PutResult:
        resp = self._http.post("/v1/pointers", json={
            "owner_secret_key": owner_secret_key,
            "target": {"kind": target.kind, "address": target.address},
        })
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    def pointer_get(self, address: str) -> Pointer:
        resp = self._http.get(f"/v1/pointers/{address}")
        _check(resp)
        j = resp.json()
        return Pointer(
            address=j["address"],
            owner=j["owner"],
            counter=j["counter"],
            target=PointerTarget(kind=j["target"]["kind"], address=j["target"]["address"]),
        )

    def pointer_exists(self, address: str) -> bool:
        resp = self._http.head(f"/v1/pointers/{address}")
        if resp.status_code == 404:
            return False
        _check(resp)
        return True

    def pointer_update(self, owner_secret_key: str, target: PointerTarget) -> None:
        resp = self._http.put(f"/v1/pointers/{owner_secret_key}", json={
            "owner_secret_key": owner_secret_key,
            "target": {"kind": target.kind, "address": target.address},
        })
        _check(resp)

    def pointer_cost(self, public_key: str) -> str:
        resp = self._http.post("/v1/pointers/cost", json={"public_key": public_key})
        _check(resp)
        return resp.json()["cost"]

    # --- Scratchpads ---

    def scratchpad_create(self, owner_secret_key: str, content_type: int, data: bytes) -> PutResult:
        resp = self._http.post("/v1/scratchpads", json={
            "owner_secret_key": owner_secret_key,
            "content_type": content_type,
            "data": _b64(data),
        })
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    def scratchpad_get(self, address: str) -> Scratchpad:
        resp = self._http.get(f"/v1/scratchpads/{address}")
        _check(resp)
        j = resp.json()
        return Scratchpad(
            address=j["address"],
            data_encoding=j["data_encoding"],
            data=_unb64(j["data"]),
            counter=j["counter"],
        )

    def scratchpad_exists(self, address: str) -> bool:
        resp = self._http.head(f"/v1/scratchpads/{address}")
        if resp.status_code == 404:
            return False
        _check(resp)
        return True

    def scratchpad_update(self, owner_secret_key: str, content_type: int, data: bytes) -> None:
        resp = self._http.put(f"/v1/scratchpads/{owner_secret_key}", json={
            "owner_secret_key": owner_secret_key,
            "content_type": content_type,
            "data": _b64(data),
        })
        _check(resp)

    def scratchpad_cost(self, public_key: str) -> str:
        resp = self._http.post("/v1/scratchpads/cost", json={"public_key": public_key})
        _check(resp)
        return resp.json()["cost"]

    # --- Graph ---

    def graph_entry_put(self, owner_secret_key: str, parents: list[str], content: str,
                        descendants: list[GraphDescendant]) -> PutResult:
        resp = self._http.post("/v1/graph", json={
            "owner_secret_key": owner_secret_key,
            "parents": parents,
            "content": content,
            "descendants": [{"public_key": d.public_key, "content": d.content} for d in descendants],
        })
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    def graph_entry_get(self, address: str) -> GraphEntry:
        resp = self._http.get(f"/v1/graph/{address}")
        _check(resp)
        j = resp.json()
        return GraphEntry(
            owner=j["owner"],
            parents=j.get("parents", []),
            content=j["content"],
            descendants=[GraphDescendant(public_key=d["public_key"], content=d["content"])
                         for d in j.get("descendants", [])],
        )

    def graph_entry_exists(self, address: str) -> bool:
        resp = self._http.head(f"/v1/graph/{address}")
        if resp.status_code == 404:
            return False
        _check(resp)
        return True

    def graph_entry_cost(self, public_key: str) -> str:
        resp = self._http.post("/v1/graph/cost", json={"public_key": public_key})
        _check(resp)
        return resp.json()["cost"]

    # --- Registers ---

    def register_create(self, owner_secret_key: str, initial_value: str) -> PutResult:
        resp = self._http.post("/v1/registers", json={
            "owner_secret_key": owner_secret_key,
            "initial_value": initial_value,
        })
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    def register_get(self, address: str) -> Register:
        resp = self._http.get(f"/v1/registers/{address}")
        _check(resp)
        return Register(value=resp.json()["value"])

    def register_update(self, owner_secret_key: str, new_value: str) -> PutResult:
        resp = self._http.put(f"/v1/registers/{owner_secret_key}", json={
            "owner_secret_key": owner_secret_key,
            "new_value": new_value,
        })
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address="")

    def register_cost(self, public_key: str) -> str:
        resp = self._http.post("/v1/registers/cost", json={"public_key": public_key})
        _check(resp)
        return resp.json()["cost"]

    # --- Vaults ---

    def vault_get(self, secret_key: str) -> Vault:
        resp = self._http.get("/v1/vaults", params={"secret_key": secret_key})
        _check(resp)
        j = resp.json()
        return Vault(data=_unb64(j["data"]), content_type=j["content_type"])

    def vault_put(self, secret_key: str, data: bytes, content_type: int) -> str:
        resp = self._http.post("/v1/vaults", json={
            "secret_key": secret_key,
            "data": _b64(data),
            "content_type": content_type,
        })
        _check(resp)
        return resp.json()["cost"]

    def vault_cost(self, secret_key: str, max_size: int) -> str:
        resp = self._http.post("/v1/vaults/cost", json={
            "secret_key": secret_key,
            "max_size": max_size,
        })
        _check(resp)
        return resp.json()["cost"]

    # --- Files ---

    def file_upload_public(self, path: str) -> PutResult:
        resp = self._http.post("/v1/files/upload/public", json={"path": path})
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    def file_download_public(self, address: str, dest_path: str) -> None:
        resp = self._http.post("/v1/files/download/public", json={
            "address": address,
            "dest_path": dest_path,
        })
        _check(resp)

    def dir_upload_public(self, path: str) -> PutResult:
        resp = self._http.post("/v1/dirs/upload/public", json={"path": path})
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    def dir_download_public(self, address: str, dest_path: str) -> None:
        resp = self._http.post("/v1/dirs/download/public", json={
            "address": address,
            "dest_path": dest_path,
        })
        _check(resp)

    def archive_get_public(self, address: str) -> Archive:
        resp = self._http.get(f"/v1/archives/public/{address}")
        _check(resp)
        j = resp.json()
        entries = [
            ArchiveEntry(
                path=e["path"], address=e["address"],
                created=e["created"], modified=e["modified"], size=e["size"],
            )
            for e in j.get("entries", [])
        ]
        return Archive(entries=entries)

    def archive_put_public(self, archive: Archive) -> PutResult:
        resp = self._http.post("/v1/archives/public", json={
            "entries": [
                {"path": e.path, "address": e.address,
                 "created": e.created, "modified": e.modified, "size": e.size}
                for e in archive.entries
            ],
        })
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    def file_cost(self, path: str, is_public: bool = True, include_archive: bool = False) -> str:
        resp = self._http.post("/v1/cost/file", json={
            "path": path,
            "is_public": is_public,
            "include_archive": include_archive,
        })
        _check(resp)
        return resp.json()["cost"]


class AsyncRestClient:
    """Asynchronous REST client for the antd daemon."""

    def __init__(self, base_url: str = "http://localhost:8080", timeout: float = 300.0):
        self._base = base_url.rstrip("/")
        self._http = httpx.AsyncClient(base_url=self._base, timeout=timeout)

    async def close(self) -> None:
        await self._http.aclose()

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        await self.close()

    # --- Health ---

    async def health(self) -> HealthStatus:
        resp = await self._http.get("/health")
        _check(resp)
        j = resp.json()
        return HealthStatus(ok=j.get("status") == "ok", network=j.get("network", "unknown"))

    # --- Data ---

    async def data_put_public(self, data: bytes) -> PutResult:
        resp = await self._http.post("/v1/data/public", json={"data": _b64(data)})
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    async def data_get_public(self, address: str) -> bytes:
        resp = await self._http.get(f"/v1/data/public/{address}")
        _check(resp)
        return _unb64(resp.json()["data"])

    async def data_put_private(self, data: bytes) -> PutResult:
        resp = await self._http.post("/v1/data/private", json={"data": _b64(data)})
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["data_map"])

    async def data_get_private(self, data_map: str) -> bytes:
        resp = await self._http.get("/v1/data/private", params={"data_map": data_map})
        _check(resp)
        return _unb64(resp.json()["data"])

    async def data_cost(self, data: bytes) -> str:
        resp = await self._http.post("/v1/data/cost", json={"data": _b64(data)})
        _check(resp)
        return resp.json()["cost"]

    # --- Chunks ---

    async def chunk_put(self, data: bytes) -> PutResult:
        resp = await self._http.post("/v1/chunks", json={"data": _b64(data)})
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    async def chunk_get(self, address: str) -> bytes:
        resp = await self._http.get(f"/v1/chunks/{address}")
        _check(resp)
        return _unb64(resp.json()["data"])

    # --- Pointers ---

    async def pointer_create(self, owner_secret_key: str, target: PointerTarget) -> PutResult:
        resp = await self._http.post("/v1/pointers", json={
            "owner_secret_key": owner_secret_key,
            "target": {"kind": target.kind, "address": target.address},
        })
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    async def pointer_get(self, address: str) -> Pointer:
        resp = await self._http.get(f"/v1/pointers/{address}")
        _check(resp)
        j = resp.json()
        return Pointer(
            address=j["address"],
            owner=j["owner"],
            counter=j["counter"],
            target=PointerTarget(kind=j["target"]["kind"], address=j["target"]["address"]),
        )

    async def pointer_exists(self, address: str) -> bool:
        resp = await self._http.head(f"/v1/pointers/{address}")
        if resp.status_code == 404:
            return False
        _check(resp)
        return True

    async def pointer_update(self, owner_secret_key: str, target: PointerTarget) -> None:
        resp = await self._http.put(f"/v1/pointers/{owner_secret_key}", json={
            "owner_secret_key": owner_secret_key,
            "target": {"kind": target.kind, "address": target.address},
        })
        _check(resp)

    async def pointer_cost(self, public_key: str) -> str:
        resp = await self._http.post("/v1/pointers/cost", json={"public_key": public_key})
        _check(resp)
        return resp.json()["cost"]

    # --- Scratchpads ---

    async def scratchpad_create(self, owner_secret_key: str, content_type: int, data: bytes) -> PutResult:
        resp = await self._http.post("/v1/scratchpads", json={
            "owner_secret_key": owner_secret_key,
            "content_type": content_type,
            "data": _b64(data),
        })
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    async def scratchpad_get(self, address: str) -> Scratchpad:
        resp = await self._http.get(f"/v1/scratchpads/{address}")
        _check(resp)
        j = resp.json()
        return Scratchpad(
            address=j["address"],
            data_encoding=j["data_encoding"],
            data=_unb64(j["data"]),
            counter=j["counter"],
        )

    async def scratchpad_exists(self, address: str) -> bool:
        resp = await self._http.head(f"/v1/scratchpads/{address}")
        if resp.status_code == 404:
            return False
        _check(resp)
        return True

    async def scratchpad_update(self, owner_secret_key: str, content_type: int, data: bytes) -> None:
        resp = await self._http.put(f"/v1/scratchpads/{owner_secret_key}", json={
            "owner_secret_key": owner_secret_key,
            "content_type": content_type,
            "data": _b64(data),
        })
        _check(resp)

    async def scratchpad_cost(self, public_key: str) -> str:
        resp = await self._http.post("/v1/scratchpads/cost", json={"public_key": public_key})
        _check(resp)
        return resp.json()["cost"]

    # --- Graph ---

    async def graph_entry_put(self, owner_secret_key: str, parents: list[str], content: str,
                              descendants: list[GraphDescendant]) -> PutResult:
        resp = await self._http.post("/v1/graph", json={
            "owner_secret_key": owner_secret_key,
            "parents": parents,
            "content": content,
            "descendants": [{"public_key": d.public_key, "content": d.content} for d in descendants],
        })
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    async def graph_entry_get(self, address: str) -> GraphEntry:
        resp = await self._http.get(f"/v1/graph/{address}")
        _check(resp)
        j = resp.json()
        return GraphEntry(
            owner=j["owner"],
            parents=j.get("parents", []),
            content=j["content"],
            descendants=[GraphDescendant(public_key=d["public_key"], content=d["content"])
                         for d in j.get("descendants", [])],
        )

    async def graph_entry_exists(self, address: str) -> bool:
        resp = await self._http.head(f"/v1/graph/{address}")
        if resp.status_code == 404:
            return False
        _check(resp)
        return True

    async def graph_entry_cost(self, public_key: str) -> str:
        resp = await self._http.post("/v1/graph/cost", json={"public_key": public_key})
        _check(resp)
        return resp.json()["cost"]

    # --- Registers ---

    async def register_create(self, owner_secret_key: str, initial_value: str) -> PutResult:
        resp = await self._http.post("/v1/registers", json={
            "owner_secret_key": owner_secret_key,
            "initial_value": initial_value,
        })
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    async def register_get(self, address: str) -> Register:
        resp = await self._http.get(f"/v1/registers/{address}")
        _check(resp)
        return Register(value=resp.json()["value"])

    async def register_update(self, owner_secret_key: str, new_value: str) -> PutResult:
        resp = await self._http.put(f"/v1/registers/{owner_secret_key}", json={
            "owner_secret_key": owner_secret_key,
            "new_value": new_value,
        })
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address="")

    async def register_cost(self, public_key: str) -> str:
        resp = await self._http.post("/v1/registers/cost", json={"public_key": public_key})
        _check(resp)
        return resp.json()["cost"]

    # --- Vaults ---

    async def vault_get(self, secret_key: str) -> Vault:
        resp = await self._http.get("/v1/vaults", params={"secret_key": secret_key})
        _check(resp)
        j = resp.json()
        return Vault(data=_unb64(j["data"]), content_type=j["content_type"])

    async def vault_put(self, secret_key: str, data: bytes, content_type: int) -> str:
        resp = await self._http.post("/v1/vaults", json={
            "secret_key": secret_key,
            "data": _b64(data),
            "content_type": content_type,
        })
        _check(resp)
        return resp.json()["cost"]

    async def vault_cost(self, secret_key: str, max_size: int) -> str:
        resp = await self._http.post("/v1/vaults/cost", json={
            "secret_key": secret_key,
            "max_size": max_size,
        })
        _check(resp)
        return resp.json()["cost"]

    # --- Files ---

    async def file_upload_public(self, path: str) -> PutResult:
        resp = await self._http.post("/v1/files/upload/public", json={"path": path})
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    async def file_download_public(self, address: str, dest_path: str) -> None:
        resp = await self._http.post("/v1/files/download/public", json={
            "address": address,
            "dest_path": dest_path,
        })
        _check(resp)

    async def dir_upload_public(self, path: str) -> PutResult:
        resp = await self._http.post("/v1/dirs/upload/public", json={"path": path})
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    async def dir_download_public(self, address: str, dest_path: str) -> None:
        resp = await self._http.post("/v1/dirs/download/public", json={
            "address": address,
            "dest_path": dest_path,
        })
        _check(resp)

    async def archive_get_public(self, address: str) -> Archive:
        resp = await self._http.get(f"/v1/archives/public/{address}")
        _check(resp)
        j = resp.json()
        entries = [
            ArchiveEntry(
                path=e["path"], address=e["address"],
                created=e["created"], modified=e["modified"], size=e["size"],
            )
            for e in j.get("entries", [])
        ]
        return Archive(entries=entries)

    async def archive_put_public(self, archive: Archive) -> PutResult:
        resp = await self._http.post("/v1/archives/public", json={
            "entries": [
                {"path": e.path, "address": e.address,
                 "created": e.created, "modified": e.modified, "size": e.size}
                for e in archive.entries
            ],
        })
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    async def file_cost(self, path: str, is_public: bool = True, include_archive: bool = False) -> str:
        resp = await self._http.post("/v1/cost/file", json={
            "path": path,
            "is_public": is_public,
            "include_archive": include_archive,
        })
        _check(resp)
        return resp.json()["cost"]
