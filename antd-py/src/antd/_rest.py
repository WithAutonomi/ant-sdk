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
    PutResult,
    WalletAddress,
    WalletBalance,
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

    DEFAULT_BASE_URL = "http://localhost:8082"

    def __init__(self, base_url: str = "http://localhost:8082", timeout: float = 300.0):
        self._base = base_url.rstrip("/")
        self._http = httpx.Client(base_url=self._base, timeout=timeout)

    @classmethod
    def auto_discover(cls, **kwargs) -> tuple["RestClient", str]:
        """Create a client using daemon port discovery, falling back to the default URL.

        Returns:
            A tuple of ``(client, resolved_url)`` where *resolved_url* is the
            URL that was actually used (discovered or default).
        """
        from ._discover import discover_daemon_url

        url = discover_daemon_url() or cls.DEFAULT_BASE_URL
        return cls(base_url=url, **kwargs), url

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

    def data_put_public(self, data: bytes, payment_mode: str | None = None) -> PutResult:
        body: dict = {"data": _b64(data)}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = self._http.post("/v1/data/public", json=body)
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    def data_get_public(self, address: str) -> bytes:
        resp = self._http.get(f"/v1/data/public/{address}")
        _check(resp)
        return _unb64(resp.json()["data"])

    def data_put_private(self, data: bytes, payment_mode: str | None = None) -> PutResult:
        body: dict = {"data": _b64(data)}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = self._http.post("/v1/data/private", json=body)
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

    # --- Files ---

    def file_upload_public(self, path: str, payment_mode: str | None = None) -> PutResult:
        body: dict = {"path": path}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = self._http.post("/v1/files/upload/public", json=body)
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    def file_download_public(self, address: str, dest_path: str) -> None:
        resp = self._http.post("/v1/files/download/public", json={
            "address": address,
            "dest_path": dest_path,
        })
        _check(resp)

    def dir_upload_public(self, path: str, payment_mode: str | None = None) -> PutResult:
        body: dict = {"path": path}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = self._http.post("/v1/dirs/upload/public", json=body)
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

    # --- Wallet ---

    def wallet_address(self) -> WalletAddress:
        resp = self._http.get("/v1/wallet/address")
        _check(resp)
        j = resp.json()
        return WalletAddress(address=j["address"])

    def wallet_balance(self) -> WalletBalance:
        resp = self._http.get("/v1/wallet/balance")
        _check(resp)
        j = resp.json()
        return WalletBalance(balance=j["balance"], gas_balance=j["gas_balance"])

    def wallet_approve(self) -> bool:
        """Approve the wallet to spend tokens on payment contracts (one-time operation)."""
        resp = self._http.post("/v1/wallet/approve", json={})
        _check(resp)
        j = resp.json()
        return j.get("approved", False)


class AsyncRestClient:
    """Asynchronous REST client for the antd daemon."""

    DEFAULT_BASE_URL = "http://localhost:8082"

    def __init__(self, base_url: str = "http://localhost:8082", timeout: float = 300.0):
        self._base = base_url.rstrip("/")
        self._http = httpx.AsyncClient(base_url=self._base, timeout=timeout)

    @classmethod
    def auto_discover(cls, **kwargs) -> tuple["AsyncRestClient", str]:
        """Create a client using daemon port discovery, falling back to the default URL.

        Returns:
            A tuple of ``(client, resolved_url)`` where *resolved_url* is the
            URL that was actually used (discovered or default).
        """
        from ._discover import discover_daemon_url

        url = discover_daemon_url() or cls.DEFAULT_BASE_URL
        return cls(base_url=url, **kwargs), url

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

    async def data_put_public(self, data: bytes, payment_mode: str | None = None) -> PutResult:
        body: dict = {"data": _b64(data)}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = await self._http.post("/v1/data/public", json=body)
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    async def data_get_public(self, address: str) -> bytes:
        resp = await self._http.get(f"/v1/data/public/{address}")
        _check(resp)
        return _unb64(resp.json()["data"])

    async def data_put_private(self, data: bytes, payment_mode: str | None = None) -> PutResult:
        body: dict = {"data": _b64(data)}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = await self._http.post("/v1/data/private", json=body)
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

    # --- Files ---

    async def file_upload_public(self, path: str, payment_mode: str | None = None) -> PutResult:
        body: dict = {"path": path}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = await self._http.post("/v1/files/upload/public", json=body)
        _check(resp)
        j = resp.json()
        return PutResult(cost=j["cost"], address=j["address"])

    async def file_download_public(self, address: str, dest_path: str) -> None:
        resp = await self._http.post("/v1/files/download/public", json={
            "address": address,
            "dest_path": dest_path,
        })
        _check(resp)

    async def dir_upload_public(self, path: str, payment_mode: str | None = None) -> PutResult:
        body: dict = {"path": path}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = await self._http.post("/v1/dirs/upload/public", json=body)
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

    # --- Wallet ---

    async def wallet_address(self) -> WalletAddress:
        resp = await self._http.get("/v1/wallet/address")
        _check(resp)
        j = resp.json()
        return WalletAddress(address=j["address"])

    async def wallet_balance(self) -> WalletBalance:
        resp = await self._http.get("/v1/wallet/balance")
        _check(resp)
        j = resp.json()
        return WalletBalance(balance=j["balance"], gas_balance=j["gas_balance"])

    async def wallet_approve(self) -> bool:
        """Approve the wallet to spend tokens on payment contracts (one-time operation)."""
        resp = await self._http.post("/v1/wallet/approve", json={})
        _check(resp)
        j = resp.json()
        return j.get("approved", False)
