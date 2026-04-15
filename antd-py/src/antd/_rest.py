"""REST transport clients (sync and async) for antd daemon."""

from __future__ import annotations

import base64
from typing import TYPE_CHECKING

import httpx

from .exceptions import raise_for_http_status
from .models import (
    CandidateNodeEntry,
    FileUploadResult,
    FinalizeUploadResult,
    HealthStatus,
    PaymentInfo,
    PoolCommitmentEntry,
    PrepareUploadResult,
    PutResult,
    WalletAddress,
    WalletBalance,
)


def _parse_file_upload_result(j: dict) -> FileUploadResult:
    """Parse a file/dir upload public JSON response into a FileUploadResult."""
    return FileUploadResult(
        address=j.get("address", ""),
        storage_cost_atto=j.get("storage_cost_atto", ""),
        gas_cost_wei=j.get("gas_cost_wei", ""),
        chunks_stored=int(j.get("chunks_stored", 0)),
        payment_mode_used=j.get("payment_mode_used", ""),
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


def _parse_prepare_result(j: dict) -> PrepareUploadResult:
    """Parse a prepare-upload JSON response into a PrepareUploadResult."""
    payment_type = j.get("payment_type", "wave_batch")
    payments = [
        PaymentInfo(
            quote_hash=p["quote_hash"],
            rewards_address=p["rewards_address"],
            amount=p["amount"],
        )
        for p in j.get("payments", [])
    ]

    pool_commitments: list[PoolCommitmentEntry] = []
    if payment_type == "merkle_batch":
        for pc in j.get("pool_commitments", []):
            candidates = [
                CandidateNodeEntry(
                    rewards_address=c.get("rewards_address", ""),
                    amount=c.get("amount", ""),
                )
                for c in pc.get("candidates", [])
            ]
            pool_commitments.append(
                PoolCommitmentEntry(pool_hash=pc.get("pool_hash", ""), candidates=candidates)
            )

    return PrepareUploadResult(
        upload_id=j.get("upload_id", ""),
        payments=payments,
        total_amount=j.get("total_amount", ""),
        payment_vault_address=j.get("payment_vault_address", ""),
        payment_token_address=j.get("payment_token_address", ""),
        rpc_url=j.get("rpc_url", ""),
        payment_type=payment_type,
        depth=j.get("depth", 0),
        pool_commitments=pool_commitments,
        merkle_payment_timestamp=j.get("merkle_payment_timestamp", 0),
    )


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
        return PutResult(cost=j.get("cost", ""), address=j.get("address", ""))

    def data_get_public(self, address: str) -> bytes:
        resp = self._http.get(f"/v1/data/public/{address}")
        _check(resp)
        return _unb64(resp.json().get("data", ""))

    def data_put_private(self, data: bytes, payment_mode: str | None = None) -> PutResult:
        body: dict = {"data": _b64(data)}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = self._http.post("/v1/data/private", json=body)
        _check(resp)
        j = resp.json()
        return PutResult(cost=j.get("cost", ""), address=j.get("data_map", ""))

    def data_get_private(self, data_map: str) -> bytes:
        resp = self._http.get("/v1/data/private", params={"data_map": data_map})
        _check(resp)
        return _unb64(resp.json().get("data", ""))

    def data_cost(self, data: bytes) -> str:
        resp = self._http.post("/v1/data/cost", json={"data": _b64(data)})
        _check(resp)
        return resp.json().get("cost", "")

    # --- Chunks ---

    def chunk_put(self, data: bytes) -> PutResult:
        resp = self._http.post("/v1/chunks", json={"data": _b64(data)})
        _check(resp)
        j = resp.json()
        return PutResult(cost=j.get("cost", ""), address=j.get("address", ""))

    def chunk_get(self, address: str) -> bytes:
        resp = self._http.get(f"/v1/chunks/{address}")
        _check(resp)
        return _unb64(resp.json().get("data", ""))

    # --- Files ---

    def file_upload_public(self, path: str, payment_mode: str | None = None) -> FileUploadResult:
        body: dict = {"path": path}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = self._http.post("/v1/files/upload/public", json=body)
        _check(resp)
        return _parse_file_upload_result(resp.json())

    def file_download_public(self, address: str, dest_path: str) -> None:
        resp = self._http.post("/v1/files/download/public", json={
            "address": address,
            "dest_path": dest_path,
        })
        _check(resp)

    def dir_upload_public(self, path: str, payment_mode: str | None = None) -> FileUploadResult:
        body: dict = {"path": path}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = self._http.post("/v1/dirs/upload/public", json=body)
        _check(resp)
        return _parse_file_upload_result(resp.json())

    def dir_download_public(self, address: str, dest_path: str) -> None:
        resp = self._http.post("/v1/dirs/download/public", json={
            "address": address,
            "dest_path": dest_path,
        })
        _check(resp)

    def file_cost(self, path: str, is_public: bool = True) -> str:
        resp = self._http.post("/v1/cost/file", json={
            "path": path,
            "is_public": is_public,
        })
        _check(resp)
        return resp.json().get("cost", "")

    # --- Wallet ---

    def wallet_address(self) -> WalletAddress:
        resp = self._http.get("/v1/wallet/address")
        _check(resp)
        j = resp.json()
        return WalletAddress(address=j.get("address", ""))

    def wallet_balance(self) -> WalletBalance:
        resp = self._http.get("/v1/wallet/balance")
        _check(resp)
        j = resp.json()
        return WalletBalance(balance=j.get("balance", ""), gas_balance=j.get("gas_balance", ""))

    def wallet_approve(self) -> bool:
        """Approve the wallet to spend tokens on payment contracts (one-time operation)."""
        resp = self._http.post("/v1/wallet/approve", json={})
        _check(resp)
        j = resp.json()
        return j.get("approved", False)

    # --- External Signer (Two-Phase Upload) ---

    def prepare_upload(self, path: str) -> PrepareUploadResult:
        """Prepare a file upload for external signing.

        Returns payment details that an external signer must process
        before calling finalize_upload.
        """
        resp = self._http.post("/v1/upload/prepare", json={"path": path})
        _check(resp)
        return _parse_prepare_result(resp.json())

    def prepare_data_upload(self, data: bytes) -> PrepareUploadResult:
        """Prepare a data upload for external signing.

        Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
        Returns payment details that an external signer must process
        before calling finalize_upload.
        """
        resp = self._http.post("/v1/data/prepare", json={"data": _b64(data)})
        _check(resp)
        return _parse_prepare_result(resp.json())

    def finalize_upload(self, upload_id: str, tx_hashes: dict[str, str]) -> FinalizeUploadResult:
        """Finalize an upload after an external signer has submitted payment transactions.

        Args:
            upload_id: The upload ID returned by prepare_upload.
            tx_hashes: Map of quote_hash to tx_hash for each payment.
        """
        resp = self._http.post("/v1/upload/finalize", json={
            "upload_id": upload_id,
            "tx_hashes": tx_hashes,
        })
        _check(resp)
        j = resp.json()
        return FinalizeUploadResult(address=j.get("address", ""), chunks_stored=j.get("chunks_stored", 0))

    def finalize_merkle_upload(
        self, upload_id: str, winner_pool_hash: str, store_data_map: bool = False,
    ) -> FinalizeUploadResult:
        """Finalize a merkle-batch upload after selecting a winning pool.

        Args:
            upload_id: The upload ID returned by prepare_upload.
            winner_pool_hash: Hash of the winning pool commitment.
            store_data_map: Whether to store the data map on-network.
        """
        resp = self._http.post("/v1/upload/finalize", json={
            "upload_id": upload_id,
            "winner_pool_hash": winner_pool_hash,
            "store_data_map": store_data_map,
        })
        _check(resp)
        j = resp.json()
        return FinalizeUploadResult(address=j.get("address", ""), chunks_stored=j.get("chunks_stored", 0))


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
        return PutResult(cost=j.get("cost", ""), address=j.get("address", ""))

    async def data_get_public(self, address: str) -> bytes:
        resp = await self._http.get(f"/v1/data/public/{address}")
        _check(resp)
        return _unb64(resp.json().get("data", ""))

    async def data_put_private(self, data: bytes, payment_mode: str | None = None) -> PutResult:
        body: dict = {"data": _b64(data)}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = await self._http.post("/v1/data/private", json=body)
        _check(resp)
        j = resp.json()
        return PutResult(cost=j.get("cost", ""), address=j.get("data_map", ""))

    async def data_get_private(self, data_map: str) -> bytes:
        resp = await self._http.get("/v1/data/private", params={"data_map": data_map})
        _check(resp)
        return _unb64(resp.json().get("data", ""))

    async def data_cost(self, data: bytes) -> str:
        resp = await self._http.post("/v1/data/cost", json={"data": _b64(data)})
        _check(resp)
        return resp.json().get("cost", "")

    # --- Chunks ---

    async def chunk_put(self, data: bytes) -> PutResult:
        resp = await self._http.post("/v1/chunks", json={"data": _b64(data)})
        _check(resp)
        j = resp.json()
        return PutResult(cost=j.get("cost", ""), address=j.get("address", ""))

    async def chunk_get(self, address: str) -> bytes:
        resp = await self._http.get(f"/v1/chunks/{address}")
        _check(resp)
        return _unb64(resp.json().get("data", ""))

    # --- Files ---

    async def file_upload_public(self, path: str, payment_mode: str | None = None) -> FileUploadResult:
        body: dict = {"path": path}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = await self._http.post("/v1/files/upload/public", json=body)
        _check(resp)
        return _parse_file_upload_result(resp.json())

    async def file_download_public(self, address: str, dest_path: str) -> None:
        resp = await self._http.post("/v1/files/download/public", json={
            "address": address,
            "dest_path": dest_path,
        })
        _check(resp)

    async def dir_upload_public(self, path: str, payment_mode: str | None = None) -> FileUploadResult:
        body: dict = {"path": path}
        if payment_mode is not None:
            body["payment_mode"] = payment_mode
        resp = await self._http.post("/v1/dirs/upload/public", json=body)
        _check(resp)
        return _parse_file_upload_result(resp.json())

    async def dir_download_public(self, address: str, dest_path: str) -> None:
        resp = await self._http.post("/v1/dirs/download/public", json={
            "address": address,
            "dest_path": dest_path,
        })
        _check(resp)

    async def file_cost(self, path: str, is_public: bool = True) -> str:
        resp = await self._http.post("/v1/cost/file", json={
            "path": path,
            "is_public": is_public,
        })
        _check(resp)
        return resp.json().get("cost", "")

    # --- Wallet ---

    async def wallet_address(self) -> WalletAddress:
        resp = await self._http.get("/v1/wallet/address")
        _check(resp)
        j = resp.json()
        return WalletAddress(address=j.get("address", ""))

    async def wallet_balance(self) -> WalletBalance:
        resp = await self._http.get("/v1/wallet/balance")
        _check(resp)
        j = resp.json()
        return WalletBalance(balance=j.get("balance", ""), gas_balance=j.get("gas_balance", ""))

    async def wallet_approve(self) -> bool:
        """Approve the wallet to spend tokens on payment contracts (one-time operation)."""
        resp = await self._http.post("/v1/wallet/approve", json={})
        _check(resp)
        j = resp.json()
        return j.get("approved", False)

    # --- External Signer (Two-Phase Upload) ---

    async def prepare_upload(self, path: str) -> PrepareUploadResult:
        """Prepare a file upload for external signing.

        Returns payment details that an external signer must process
        before calling finalize_upload.
        """
        resp = await self._http.post("/v1/upload/prepare", json={"path": path})
        _check(resp)
        return _parse_prepare_result(resp.json())

    async def prepare_data_upload(self, data: bytes) -> PrepareUploadResult:
        """Prepare a data upload for external signing.

        Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
        Returns payment details that an external signer must process
        before calling finalize_upload.
        """
        resp = await self._http.post("/v1/data/prepare", json={"data": _b64(data)})
        _check(resp)
        return _parse_prepare_result(resp.json())

    async def finalize_upload(self, upload_id: str, tx_hashes: dict[str, str]) -> FinalizeUploadResult:
        """Finalize an upload after an external signer has submitted payment transactions.

        Args:
            upload_id: The upload ID returned by prepare_upload.
            tx_hashes: Map of quote_hash to tx_hash for each payment.
        """
        resp = await self._http.post("/v1/upload/finalize", json={
            "upload_id": upload_id,
            "tx_hashes": tx_hashes,
        })
        _check(resp)
        j = resp.json()
        return FinalizeUploadResult(address=j.get("address", ""), chunks_stored=j.get("chunks_stored", 0))

    async def finalize_merkle_upload(
        self, upload_id: str, winner_pool_hash: str, store_data_map: bool = False,
    ) -> FinalizeUploadResult:
        """Finalize a merkle-batch upload after selecting a winning pool.

        Args:
            upload_id: The upload ID returned by prepare_upload.
            winner_pool_hash: Hash of the winning pool commitment.
            store_data_map: Whether to store the data map on-network.
        """
        resp = await self._http.post("/v1/upload/finalize", json={
            "upload_id": upload_id,
            "winner_pool_hash": winner_pool_hash,
            "store_data_map": store_data_map,
        })
        _check(resp)
        j = resp.json()
        return FinalizeUploadResult(address=j.get("address", ""), chunks_stored=j.get("chunks_stored", 0))
