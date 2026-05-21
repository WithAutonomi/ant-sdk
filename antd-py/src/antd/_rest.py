"""REST transport clients (sync and async) for antd daemon."""

from __future__ import annotations

import base64
from typing import TYPE_CHECKING

import httpx

from .exceptions import raise_for_http_status
from .models import (
    CandidateNodeEntry,
    DataPutPublicResult,
    DataPutResult,
    FilePutPublicResult,
    FilePutResult,
    FinalizeUploadResult,
    HealthStatus,
    PaymentInfo,
    PaymentMode,
    PoolCommitmentEntry,
    PrepareChunkResult,
    PrepareUploadResult,
    PutResult,
    UploadCostEstimate,
    WalletAddress,
    WalletBalance,
)


def _health_status_from_json(j: dict) -> HealthStatus:
    """Parse a /health JSON response. Diagnostic fields default to empty when
    talking to a pre-0.4.0 daemon."""
    return HealthStatus(
        ok=j.get("status") == "ok",
        network=j.get("network", "unknown"),
        version=j.get("version", ""),
        evm_network=j.get("evm_network", ""),
        uptime_seconds=int(j.get("uptime_seconds", 0)),
        build_commit=j.get("build_commit", ""),
        payment_token_address=j.get("payment_token_address", ""),
        payment_vault_address=j.get("payment_vault_address", ""),
    )


def _parse_file_put_result(j: dict) -> FilePutResult:
    """Parse a private file put JSON response into a ``FilePutResult``."""
    return FilePutResult(
        data_map=j.get("data_map", ""),
        storage_cost_atto=j.get("storage_cost_atto", ""),
        gas_cost_wei=j.get("gas_cost_wei", ""),
        chunks_stored=int(j.get("chunks_stored", 0)),
        payment_mode_used=j.get("payment_mode_used", ""),
    )


def _parse_file_put_public_result(j: dict) -> FilePutPublicResult:
    """Parse a public file put JSON response into a ``FilePutPublicResult``."""
    return FilePutPublicResult(
        address=j.get("address", ""),
        storage_cost_atto=j.get("storage_cost_atto", ""),
        gas_cost_wei=j.get("gas_cost_wei", ""),
        chunks_stored=int(j.get("chunks_stored", 0)),
        payment_mode_used=j.get("payment_mode_used", ""),
    )


def _parse_data_put_result(j: dict) -> DataPutResult:
    return DataPutResult(
        data_map=j.get("data_map", ""),
        chunks_stored=int(j.get("chunks_stored", 0)),
        payment_mode_used=j.get("payment_mode_used", ""),
    )


def _parse_data_put_public_result(j: dict) -> DataPutPublicResult:
    return DataPutPublicResult(
        address=j.get("address", ""),
        chunks_stored=int(j.get("chunks_stored", 0)),
        payment_mode_used=j.get("payment_mode_used", ""),
    )


def _parse_cost_estimate(j: dict) -> UploadCostEstimate:
    """Parse a cost-estimate JSON response into an UploadCostEstimate."""
    return UploadCostEstimate(
        cost=j.get("cost", ""),
        file_size=int(j.get("file_size", 0)),
        chunk_count=int(j.get("chunk_count", 0)),
        estimated_gas_cost_wei=j.get("estimated_gas_cost_wei", ""),
        payment_mode=j.get("payment_mode", ""),
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


def _parse_prepare_chunk_result(j: dict) -> PrepareChunkResult:
    """Parse a /v1/chunks/prepare JSON response into a PrepareChunkResult."""
    payments = [
        PaymentInfo(
            quote_hash=p["quote_hash"],
            rewards_address=p["rewards_address"],
            amount=p["amount"],
        )
        for p in j.get("payments", []) or []
    ]
    return PrepareChunkResult(
        address=j.get("address", ""),
        already_stored=bool(j.get("already_stored", False)),
        upload_id=j.get("upload_id") or "",
        payment_type=j.get("payment_type") or "",
        payments=payments,
        total_amount=j.get("total_amount") or "",
        payment_vault_address=j.get("payment_vault_address") or "",
        payment_token_address=j.get("payment_token_address") or "",
        rpc_url=j.get("rpc_url") or "",
    )


def _parse_finalize_upload_result(j: dict) -> FinalizeUploadResult:
    """Parse a /v1/upload/finalize JSON response.

    `data_map_address` is populated only when prepare was called with
    visibility="public" — the DataMap chunk was bundled into the same
    external-signer payment batch and stored on-network.
    """
    return FinalizeUploadResult(
        address=j.get("address") or "",
        chunks_stored=int(j.get("chunks_stored", 0) or 0),
        data_map=j.get("data_map") or "",
        data_map_address=j.get("data_map_address") or "",
    )


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
        return _health_status_from_json(j)

    # --- Data ---

    def data_put(self, data: bytes, payment_mode: PaymentMode = PaymentMode.AUTO) -> DataPutResult:
        """Store private encrypted data. Returns the caller-held DataMap (hex)."""
        resp = self._http.post("/v1/data", json={
            "data": _b64(data),
            "payment_mode": payment_mode.value,
        })
        _check(resp)
        return _parse_data_put_result(resp.json())

    def data_get(self, data_map: str) -> bytes:
        """Retrieve private data from a caller-held DataMap (hex)."""
        resp = self._http.post("/v1/data/get", json={"data_map": data_map})
        _check(resp)
        return _unb64(resp.json().get("data", ""))

    def data_put_public(self, data: bytes, payment_mode: PaymentMode = PaymentMode.AUTO) -> DataPutPublicResult:
        """Store public data. The DataMap is stored on-network as an extra
        chunk; the returned address is the shareable retrieval handle."""
        resp = self._http.post("/v1/data/public", json={
            "data": _b64(data),
            "payment_mode": payment_mode.value,
        })
        _check(resp)
        return _parse_data_put_public_result(resp.json())

    def data_get_public(self, address: str) -> bytes:
        resp = self._http.get(f"/v1/data/public/{address}")
        _check(resp)
        return _unb64(resp.json().get("data", ""))

    def data_cost(self, data: bytes, payment_mode: PaymentMode = PaymentMode.AUTO) -> UploadCostEstimate:
        """Pre-upload cost breakdown for the given bytes.

        The server samples a small number of chunk addresses and extrapolates,
        much faster than quoting every chunk on slow networks. Gas is advisory.
        """
        resp = self._http.post("/v1/data/cost", json={
            "data": _b64(data),
            "payment_mode": payment_mode.value,
        })
        _check(resp)
        return _parse_cost_estimate(resp.json())

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

    def prepare_chunk_upload(self, data: bytes) -> PrepareChunkResult:
        """Prepare a single chunk for external-signer publish.

        Returns either ``already_stored=True`` (no payment needed) or a
        wave-batch payment intent. After the external signer pays, call
        :meth:`finalize_chunk_upload` with the resulting tx hashes.
        """
        resp = self._http.post("/v1/chunks/prepare", json={"data": _b64(data)})
        _check(resp)
        return _parse_prepare_chunk_result(resp.json())

    def finalize_chunk_upload(self, upload_id: str, tx_hashes: dict[str, str]) -> str:
        """Submit a prepared chunk to the network after external payment.

        Returns the network address of the stored chunk (matches
        :attr:`PrepareChunkResult.address`).
        """
        resp = self._http.post("/v1/chunks/finalize", json={
            "upload_id": upload_id,
            "tx_hashes": tx_hashes,
        })
        _check(resp)
        return resp.json().get("address", "")

    # --- Files ---

    def file_put(self, path: str, payment_mode: PaymentMode = PaymentMode.AUTO) -> FilePutResult:
        """Upload a file privately. Returns the caller-held DataMap (hex)."""
        resp = self._http.post("/v1/files", json={
            "path": path,
            "payment_mode": payment_mode.value,
        })
        _check(resp)
        return _parse_file_put_result(resp.json())

    def file_get(self, data_map: str, dest_path: str) -> None:
        """Download a private file from a caller-held DataMap into ``dest_path``."""
        resp = self._http.post("/v1/files/get", json={
            "data_map": data_map,
            "dest_path": dest_path,
        })
        _check(resp)

    def file_put_public(self, path: str, payment_mode: PaymentMode = PaymentMode.AUTO) -> FilePutPublicResult:
        """Upload a file publicly. The DataMap is stored on-network as an
        extra chunk; the returned address is the shareable retrieval handle."""
        resp = self._http.post("/v1/files/public", json={
            "path": path,
            "payment_mode": payment_mode.value,
        })
        _check(resp)
        return _parse_file_put_public_result(resp.json())

    def file_get_public(self, address: str, dest_path: str) -> None:
        """Download a public file from an on-network DataMap address."""
        resp = self._http.post("/v1/files/public/get", json={
            "address": address,
            "dest_path": dest_path,
        })
        _check(resp)

    def file_cost(self, path: str, is_public: bool = True, payment_mode: PaymentMode = PaymentMode.AUTO) -> UploadCostEstimate:
        """Pre-upload cost breakdown for the file at ``path``.

        The server samples a small number of chunk addresses and extrapolates,
        much faster than quoting every chunk on slow networks. Gas is advisory.
        """
        resp = self._http.post("/v1/files/cost", json={
            "path": path,
            "is_public": is_public,
            "payment_mode": payment_mode.value,
        })
        _check(resp)
        return _parse_cost_estimate(resp.json())

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

    def prepare_upload(self, path: str, visibility: str | None = None) -> PrepareUploadResult:
        """Prepare a file upload for external signing.

        Args:
            path: Path to the file to upload.
            visibility: ``"public"`` to bundle the DataMap chunk into the
                same external-signer payment batch (the resulting
                ``data_map_address`` on finalize is the shareable retrieval
                handle). ``"private"`` or ``None`` keeps the existing
                private-only behaviour.
        """
        body: dict = {"path": path}
        if visibility is not None:
            body["visibility"] = visibility
        resp = self._http.post("/v1/upload/prepare", json=body)
        _check(resp)
        return _parse_prepare_result(resp.json())

    def prepare_upload_public(self, path: str) -> PrepareUploadResult:
        """Convenience wrapper: prepare a *public* file upload for external signing.

        Equivalent to :meth:`prepare_upload` with ``visibility="public"``.
        """
        return self.prepare_upload(path, visibility="public")

    def prepare_data_upload(self, data: bytes, visibility: str | None = None) -> PrepareUploadResult:
        """Prepare a data upload for external signing.

        Note: ``visibility="public"`` returns 501 from the daemon until
        upstream ant-client exposes ``data_prepare_upload_with_visibility``;
        use :meth:`prepare_upload_public` with a file path until then.
        """
        body: dict = {"data": _b64(data)}
        if visibility is not None:
            body["visibility"] = visibility
        resp = self._http.post("/v1/data/prepare", json=body)
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
        return _parse_finalize_upload_result(resp.json())

    def finalize_merkle_upload(
        self, upload_id: str, winner_pool_hash: str, store_data_map: bool = False,
    ) -> FinalizeUploadResult:
        """Finalize a merkle-batch upload after selecting a winning pool.

        Args:
            upload_id: The upload ID returned by prepare_upload.
            winner_pool_hash: Hash of the winning pool commitment.
            store_data_map: Whether to store the data map on-network. Kept for
                backward compat — for visibility="public" prepares the DataMap
                is already bundled in the external-signer batch and
                ``data_map_address`` on the result is the shareable handle.
        """
        resp = self._http.post("/v1/upload/finalize", json={
            "upload_id": upload_id,
            "winner_pool_hash": winner_pool_hash,
            "store_data_map": store_data_map,
        })
        _check(resp)
        return _parse_finalize_upload_result(resp.json())


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
        return _health_status_from_json(j)

    # --- Data ---

    async def data_put(self, data: bytes, payment_mode: PaymentMode = PaymentMode.AUTO) -> DataPutResult:
        """Store private encrypted data. Returns the caller-held DataMap (hex)."""
        resp = await self._http.post("/v1/data", json={
            "data": _b64(data),
            "payment_mode": payment_mode.value,
        })
        _check(resp)
        return _parse_data_put_result(resp.json())

    async def data_get(self, data_map: str) -> bytes:
        """Retrieve private data from a caller-held DataMap (hex)."""
        resp = await self._http.post("/v1/data/get", json={"data_map": data_map})
        _check(resp)
        return _unb64(resp.json().get("data", ""))

    async def data_put_public(self, data: bytes, payment_mode: PaymentMode = PaymentMode.AUTO) -> DataPutPublicResult:
        """Store public data. Returns the on-network DataMap address."""
        resp = await self._http.post("/v1/data/public", json={
            "data": _b64(data),
            "payment_mode": payment_mode.value,
        })
        _check(resp)
        return _parse_data_put_public_result(resp.json())

    async def data_get_public(self, address: str) -> bytes:
        resp = await self._http.get(f"/v1/data/public/{address}")
        _check(resp)
        return _unb64(resp.json().get("data", ""))

    async def data_cost(self, data: bytes, payment_mode: PaymentMode = PaymentMode.AUTO) -> UploadCostEstimate:
        """Pre-upload cost breakdown for the given bytes."""
        resp = await self._http.post("/v1/data/cost", json={
            "data": _b64(data),
            "payment_mode": payment_mode.value,
        })
        _check(resp)
        return _parse_cost_estimate(resp.json())

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

    async def prepare_chunk_upload(self, data: bytes) -> PrepareChunkResult:
        """Prepare a single chunk for external-signer publish.

        See :meth:`RestClient.prepare_chunk_upload`.
        """
        resp = await self._http.post("/v1/chunks/prepare", json={"data": _b64(data)})
        _check(resp)
        return _parse_prepare_chunk_result(resp.json())

    async def finalize_chunk_upload(self, upload_id: str, tx_hashes: dict[str, str]) -> str:
        """Submit a prepared chunk to the network after external payment."""
        resp = await self._http.post("/v1/chunks/finalize", json={
            "upload_id": upload_id,
            "tx_hashes": tx_hashes,
        })
        _check(resp)
        return resp.json().get("address", "")

    # --- Files ---

    async def file_put(self, path: str, payment_mode: PaymentMode = PaymentMode.AUTO) -> FilePutResult:
        """Upload a file privately. Returns the caller-held DataMap (hex)."""
        resp = await self._http.post("/v1/files", json={
            "path": path,
            "payment_mode": payment_mode.value,
        })
        _check(resp)
        return _parse_file_put_result(resp.json())

    async def file_get(self, data_map: str, dest_path: str) -> None:
        """Download a private file from a caller-held DataMap into ``dest_path``."""
        resp = await self._http.post("/v1/files/get", json={
            "data_map": data_map,
            "dest_path": dest_path,
        })
        _check(resp)

    async def file_put_public(self, path: str, payment_mode: PaymentMode = PaymentMode.AUTO) -> FilePutPublicResult:
        """Upload a file publicly. Returns the on-network DataMap address."""
        resp = await self._http.post("/v1/files/public", json={
            "path": path,
            "payment_mode": payment_mode.value,
        })
        _check(resp)
        return _parse_file_put_public_result(resp.json())

    async def file_get_public(self, address: str, dest_path: str) -> None:
        """Download a public file from an on-network DataMap address."""
        resp = await self._http.post("/v1/files/public/get", json={
            "address": address,
            "dest_path": dest_path,
        })
        _check(resp)

    async def file_cost(self, path: str, is_public: bool = True, payment_mode: PaymentMode = PaymentMode.AUTO) -> UploadCostEstimate:
        """Pre-upload cost breakdown for the file at ``path``."""
        resp = await self._http.post("/v1/files/cost", json={
            "path": path,
            "is_public": is_public,
            "payment_mode": payment_mode.value,
        })
        _check(resp)
        return _parse_cost_estimate(resp.json())

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

    async def prepare_upload(self, path: str, visibility: str | None = None) -> PrepareUploadResult:
        """Prepare a file upload for external signing.

        See :meth:`RestClient.prepare_upload` for the ``visibility`` semantics.
        """
        body: dict = {"path": path}
        if visibility is not None:
            body["visibility"] = visibility
        resp = await self._http.post("/v1/upload/prepare", json=body)
        _check(resp)
        return _parse_prepare_result(resp.json())

    async def prepare_upload_public(self, path: str) -> PrepareUploadResult:
        """Convenience wrapper: prepare a *public* file upload for external signing."""
        return await self.prepare_upload(path, visibility="public")

    async def prepare_data_upload(self, data: bytes, visibility: str | None = None) -> PrepareUploadResult:
        """Prepare a data upload for external signing.

        Note: ``visibility="public"`` returns 501 from the daemon until upstream
        ant-client exposes ``data_prepare_upload_with_visibility``.
        """
        body: dict = {"data": _b64(data)}
        if visibility is not None:
            body["visibility"] = visibility
        resp = await self._http.post("/v1/data/prepare", json=body)
        _check(resp)
        return _parse_prepare_result(resp.json())

    async def finalize_upload(self, upload_id: str, tx_hashes: dict[str, str]) -> FinalizeUploadResult:
        """Finalize an upload after an external signer has submitted payment transactions."""
        resp = await self._http.post("/v1/upload/finalize", json={
            "upload_id": upload_id,
            "tx_hashes": tx_hashes,
        })
        _check(resp)
        return _parse_finalize_upload_result(resp.json())

    async def finalize_merkle_upload(
        self, upload_id: str, winner_pool_hash: str, store_data_map: bool = False,
    ) -> FinalizeUploadResult:
        """Finalize a merkle-batch upload after selecting a winning pool."""
        resp = await self._http.post("/v1/upload/finalize", json={
            "upload_id": upload_id,
            "winner_pool_hash": winner_pool_hash,
            "store_data_map": store_data_map,
        })
        _check(resp)
        return _parse_finalize_upload_result(resp.json())
