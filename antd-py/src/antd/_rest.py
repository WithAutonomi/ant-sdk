"""REST transport clients (sync and async) for antd daemon."""

from __future__ import annotations

import base64
import json
from collections.abc import AsyncIterator, Iterator, Sequence
from contextlib import asynccontextmanager, contextmanager
from typing import TYPE_CHECKING

import httpx

from . import _pointers
from .exceptions import InternalError, raise_for_http_error
from .models import (
    BuiltManifest,
    CandidateNodeEntry,
    DataPutPublicResult,
    DataPutResult,
    DecodedManifest,
    DownloadFrame,
    DownloadProgress,
    FilePutPublicResult,
    FilePutResult,
    FinalizeUploadResult,
    HealthStatus,
    ManifestEntryInput,
    PaymentInfo,
    PaymentMode,
    PointerController,
    PointerFinality,
    PointerFinalizeResult,
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
    UploadCostEstimate,
    WalletAddress,
    WalletBalance,
)
from . import _manifests


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


def _error_details(resp: httpx.Response) -> tuple[str, object]:
    """Return ``(message, body)`` for an error response. Never raises.

    ``body`` is the decoded JSON, or ``None`` when the response is not JSON
    (including JSON Python cannot decode, such as an integer longer than
    4300 digits). ``message`` is the body's ``error`` when that is a string,
    otherwise the raw response text: a non-JSON body, a body that is not an
    object, or an ``error`` that is missing or not a string.
    """
    text = resp.text
    try:
        body = resp.json()
    except Exception:
        return text, None
    error = body.get("error") if isinstance(body, dict) else None
    return (error if isinstance(error, str) else text), body


def _check(resp: httpx.Response) -> None:
    if resp.is_success:
        return
    msg, body = _error_details(resp)
    raise_for_http_error(resp.status_code, msg, body)


def _json_object(resp: httpx.Response) -> dict:
    """The response's JSON object; anything else reads as an empty object, so
    the pointer parsers report a missing counter rather than a raw error."""
    try:
        j = resp.json()
    except ValueError:
        return {}
    return j if isinstance(j, dict) else {}


def _check_streamed(resp: httpx.Response) -> None:
    """Like :func:`_check` but for a streamed response: the body must be read
    before its text/JSON is available, so pull it in on the error path only."""
    if resp.is_success:
        return
    resp.read()
    msg, body = _error_details(resp)
    raise_for_http_error(resp.status_code, msg, body)


async def _acheck_streamed(resp: httpx.Response) -> None:
    """Async counterpart to :func:`_check_streamed`."""
    if resp.is_success:
        return
    await resp.aread()
    msg, body = _error_details(resp)
    raise_for_http_error(resp.status_code, msg, body)


# Media type that opts the stream endpoints into NDJSON progress framing.
_NDJSON_CONTENT_TYPE = "application/x-ndjson"


def _parse_ndjson_frame(line: str) -> DownloadFrame | None:
    """Parse one NDJSON download line into a :class:`DownloadFrame`. Returns
    ``None`` for the leading ``meta`` frame, blank lines, and unknown frame types
    (forward-compat). Raises :class:`InternalError` on a terminal ``error`` frame,
    which a raw octet-stream download cannot signal mid-stream."""
    line = line.strip()
    if not line:
        return None
    frame = json.loads(line)
    kind = frame.get("type")
    if kind == "data":
        return DownloadFrame(data=base64.b64decode(frame.get("chunk", "")))
    if kind == "progress":
        return DownloadFrame(progress=DownloadProgress(
            phase=frame.get("phase", ""),
            fetched=int(frame.get("fetched", 0)),
            total=int(frame.get("total", 0)),
        ))
    if kind == "error":
        raise InternalError(frame.get("message", "stream error"), 500)
    if kind == "meta":
        return DownloadFrame(meta=int(frame.get("total_size", 0)))
    # Unknown frame types: skip for forward-compatibility.
    return None


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
        total_chunks=j.get("total_chunks", 0),
        already_stored_count=j.get("already_stored_count", 0),
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

    @contextmanager
    def data_stream(self, data_map: str) -> Iterator[Iterator[bytes]]:
        """Stream private data from a caller-held DataMap (hex), one decrypt
        batch at a time, instead of buffering the whole object. The streaming
        counterpart to :meth:`data_get`, suitable for large blobs.

        Use as a context manager; the yielded iterator produces raw byte chunks::

            with client.data_stream(data_map) as chunks:
                for chunk in chunks:
                    out.write(chunk)
        """
        with self._http.stream("POST", "/v1/data/stream", json={"data_map": data_map}) as resp:
            _check_streamed(resp)
            yield resp.iter_bytes()

    @contextmanager
    def data_stream_public(self, address: str) -> Iterator[Iterator[bytes]]:
        """Stream public data by address — the streaming counterpart to
        :meth:`data_get_public`. Use as a context manager (see
        :meth:`data_stream`)."""
        with self._http.stream("GET", f"/v1/data/public/{address}/stream") as resp:
            _check_streamed(resp)
            yield resp.iter_bytes()

    @contextmanager
    def data_stream_with_progress(self, data_map: str) -> Iterator[Iterator[DownloadFrame]]:
        """:meth:`data_stream` with interleaved fetch-progress frames. Opts into
        NDJSON framing (``Accept: application/x-ndjson``); the yielded iterator
        produces :class:`DownloadFrame`s — each a plaintext chunk or a
        :class:`DownloadProgress` update::

            with client.data_stream_with_progress(data_map) as frames:
                for frame in frames:
                    if frame.is_progress:
                        bar.update(frame.progress.fetched, frame.progress.total)
                    else:
                        out.write(frame.data)
        """
        headers = {"Accept": _NDJSON_CONTENT_TYPE}
        with self._http.stream("POST", "/v1/data/stream", json={"data_map": data_map}, headers=headers) as resp:
            _check_streamed(resp)
            yield (f for line in resp.iter_lines() if (f := _parse_ndjson_frame(line)) is not None)

    @contextmanager
    def data_stream_public_with_progress(self, address: str) -> Iterator[Iterator[DownloadFrame]]:
        """:meth:`data_stream_public` with interleaved fetch-progress frames.
        See :meth:`data_stream_with_progress`."""
        headers = {"Accept": _NDJSON_CONTENT_TYPE}
        with self._http.stream("GET", f"/v1/data/public/{address}/stream", headers=headers) as resp:
            _check_streamed(resp)
            yield (f for line in resp.iter_lines() if (f := _parse_ndjson_frame(line)) is not None)

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

    # --- Manifests ---
    #
    # ADR-0006 `.ant` files and `ant://` links (antd 0.16.0 or
    # later). The daemon builds and decodes them through
    # ant-core, so callers never handle the format. Nothing is uploaded or
    # paid for: these calls only read the network (the embedding policy on
    # build, ``resolve`` on decode), so they can time out and are safe to
    # retry. The ``.ant`` bytes travel as base64 over REST; these methods take
    # and return raw bytes.

    def build_manifest(
        self,
        entries: Sequence[ManifestEntryInput],
        *,
        name: str | None = None,
        torrent_info_hashes: Sequence[str] | None = None,
        embed_roots: bool = True,
    ) -> BuiltManifest:
        """Build a ``.ant`` manifest from DataMaps and public addresses already
        in hand (``POST /v1/manifests/build``). Nothing is uploaded or paid
        for.

        Args:
            entries: The files, each with exactly one of ``data_map`` or
                ``address``; checked before anything is sent.
            name: A suggested root directory name (one portable path
                component).
            torrent_info_hashes: BitTorrent info hashes of the same files:
                hex, 40 characters for v1 and/or 64 for v2.
            embed_roots: ``True`` (default): the daemon resolves each shrunk
                DataMap's root (fetching its wrapper records) and embeds the
                root when it is at most 64 KiB, so recipients skip that fetch
                (ADR-0006's policy). ``False`` embeds DataMaps exactly as
                given.

        Returns:
            The ``.ant`` bytes, the ``ant://manifest/`` link when it fits
            1,500 bytes (``None`` otherwise), and the entries in encoded
            order (sorted by effective name).

        Raises:
            BadRequestError: an entry with both or neither of ``data_map``
                and ``address`` (refused before sending, ``status_code`` 0),
                or one the daemon refused, such as an invalid path; the
                message names ``entries[i]``.
        """
        _manifests.check_entries(entries)
        hashes = _manifests.check_torrent_info_hashes(torrent_info_hashes)
        resp = self._http.post(
            "/v1/manifests/build",
            json=_manifests.build_body(entries, name, hashes, embed_roots),
        )
        _check(resp)
        return _manifests.built_from_json(resp.json())

    def decode_manifest(self, manifest: bytes, resolve: bool = False) -> DecodedManifest:
        """Decode ``.ant`` bytes (``POST /v1/manifests/decode``).

        With ``resolve``, the daemon fetches each entry's DataMap (and wrapper
        records) to report ``exact_size`` and confirm the DataMap is on the
        network; content chunks are not fetched, and one entry's failure is
        reported in its ``error`` rather than failing the call.

        Raises:
            BadRequestError: empty bytes (refused before sending), or bytes
                that are not a manifest.
        """
        body = _manifests.decode_bytes_body(_manifests.manifest_bytes(manifest), resolve)
        resp = self._http.post("/v1/manifests/decode", json=body)
        _check(resp)
        return _manifests.decoded_from_json(resp.json())

    def decode_manifest_link(self, link: str, resolve: bool = False) -> DecodedManifest:
        """Decode an ``ant://`` manifest link, a file link or a bare 64-hex
        address (``POST /v1/manifests/decode``). A file link or address reads
        as ``source="file_link"`` with one public entry and no path. See
        :meth:`decode_manifest` for ``resolve``.

        Raises:
            BadRequestError: an empty link (refused before sending), or one the
                daemon cannot parse.
        """
        body = _manifests.decode_link_body(_manifests.check_link(link), resolve)
        resp = self._http.post("/v1/manifests/decode", json=body)
        _check(resp)
        return _manifests.decoded_from_json(resp.json())

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

        Raises:
            PartialUploadError: some chunks stored, others still unstored
                after the daemon's retries (HTTP 502 ``PARTIAL_UPLOAD`` /
                gRPC ``ABORTED``). The payment persists. ``retryable``: the
                daemon kept the paid attempt, so call this method again with
                the same arguments, bounding the loop. ``retention_known``
                and not ``retryable``: the daemon confirmed it kept nothing,
                so re-prepare the same content (already-stored chunks are
                skipped). Not ``retention_known``: the daemon may still hold
                the paid attempt, so stop, keep the ``upload_id`` and payment
                artefacts, and reconcile before re-preparing or paying
                again. See :class:`~antd.exceptions.PartialUploadError` and
                ``docs/external-signer-flow.md`` section 6.
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

        Raises:
            PartialUploadError: some chunks stored, others still unstored
                after the daemon's retries (HTTP 502 ``PARTIAL_UPLOAD`` /
                gRPC ``ABORTED``). The payment persists. ``retryable``: the
                daemon kept the paid attempt, so call this method again with
                the same arguments, bounding the loop. ``retention_known``
                and not ``retryable``: the daemon confirmed it kept nothing,
                so re-prepare the same content (already-stored chunks are
                skipped). Not ``retention_known``: the daemon may still hold
                the paid attempt, so stop, keep the ``upload_id`` and payment
                artefacts, and reconcile before re-preparing or paying
                again. See :class:`~antd.exceptions.PartialUploadError` and
                ``docs/external-signer-flow.md`` section 6.
        """
        resp = self._http.post("/v1/upload/finalize", json={
            "upload_id": upload_id,
            "winner_pool_hash": winner_pool_hash,
            "store_data_map": store_data_map,
        })
        _check(resp)
        return _parse_finalize_upload_result(resp.json())

    # --- Pointers ---
    #
    # Owner-signed, paid, mutable references (antd 0.16.0 or
    # later). antd signs with owner keys it loaded at startup
    # (``--pointer-keys``); a write names the pointer by its address
    # (``owner``), and pointer_keys() lists the ones it can write.
    #
    # Every write pays, about the price of one chunk, and every attempt pays
    # again. These methods never retry: do not retry pointer_create,
    # pointer_update, pointer_transfer or pointer_finalize automatically
    # (except a finalize whose CloseGroupShortfallError has retryable=True).
    # Reads are free to retry.

    def pointer_keys(self) -> list[str]:
        """The addresses of the pointers this daemon holds owner keys for
        (``GET /v1/pointers/keys``). Only these can be written through it."""
        resp = self._http.get("/v1/pointers/keys")
        _check(resp)
        return _pointers.keys_from_json(_json_object(resp))

    def pointer_create(
        self, owner: str, target: str, kind: PointerKind | str = PointerKind.CHUNK,
    ) -> PointerWriteResult:
        """Create the pointer at ``owner``, pointing at ``target``, paid by the
        daemon wallet (``POST /v1/pointers``). Pays; never retried.

        Args:
            owner: The pointer's address (hex, ``0x`` optional). The daemon
                must hold its key (:meth:`pointer_keys`).
            target: The address to point at (hex).
            kind: :attr:`PointerKind.CHUNK` (default), such as a public data
                address, or :attr:`PointerKind.POINTER` for a forwarding.

        Raises:
            AlreadyExistsError: the pointer exists (refused before paying);
                use :meth:`pointer_update`.
            ConflictError: a prepared write to it awaits payment.
            BadRequestError: no key is loaded for ``owner``, or a malformed
                address.
        """
        resp = self._http.post("/v1/pointers", json=_pointers.write_body(owner, target, kind))
        _check(resp)
        return _pointers.write_from_json(_json_object(resp))

    def pointer_update(
        self, owner: str, target: str, kind: PointerKind | str = PointerKind.CHUNK,
    ) -> PointerWriteResult:
        """Point the pointer at ``owner`` at ``target``, paid by the daemon
        wallet (``POST /v1/pointers/update``), creating it at counter 0 if it
        does not exist. Pays; never retried.

        Raises:
            PointerFinalError: the pointer was transferred or frozen
                (usually refused before paying; see :class:`PointerFinalError`).
            ConflictError: a prepared write to it awaits payment (refused
                before paying), or the update lost to a newer state while in
                flight (possibly after paying). Read the pointer before
                writing again.
        """
        resp = self._http.post("/v1/pointers/update", json=_pointers.write_body(owner, target, kind))
        _check(resp)
        return _pointers.write_from_json(_json_object(resp))

    def pointer_transfer(self, owner: str, recipient: str) -> PointerTransferResult:
        """Hand the pointer at ``owner`` over to the pointer at ``recipient``,
        for good, paid by the daemon wallet (``POST /v1/pointers/transfer``).
        Readers of the address are redirected to the recipient's pointer,
        which only its owner can move. Irreversible once stored. Pays; never
        retried.

        The result carries the close group's :class:`PointerFinality` once the
        write landed, or ``finality_error`` when that check failed (the
        transfer is stored either way).

        Raises:
            PointerFinalError: the pointer is already final.
            BadRequestError: ``recipient`` does not exist or leads back.
            CloseGroupShortfallError: too few of the close group answered or
                stored it. This can happen before paying (the transfer checks
                every peer first) or after, so check the pointer with
                :meth:`pointer_finality` before paying again.
        """
        resp = self._http.post("/v1/pointers/transfer", json={"owner": owner, "recipient": recipient})
        _check(resp)
        return _pointers.transfer_from_json(_json_object(resp))

    def pointer_get(self, address: str) -> PointerRecord:
        """Read the pointer at ``address`` (``GET /v1/pointers/{address}``).

        Raises:
            NotFoundError: no pointer exists there.
            CloseGroupShortfallError: too few peers answered; free to retry.
        """
        resp = self._http.get(f"/v1/pointers/{address}")
        _check(resp)
        return _pointers.record_from_json(_json_object(resp))

    def pointer_resolve(self, address: str) -> PointerTarget:
        """Follow a chain of pointers from ``address`` to the target at its
        end (``GET /v1/pointers/{address}/resolve``), through forwardings and
        transfers alike.

        Raises:
            NotFoundError: a pointer on the chain does not exist.
        """
        resp = self._http.get(f"/v1/pointers/{address}/resolve")
        _check(resp)
        return _pointers.target_from_json(_json_object(resp))

    def pointer_finality(self, address: str) -> PointerFinality:
        """Ask the whole close group where the pointer at ``address`` stands
        (``GET /v1/pointers/{address}/finality``). Check it before relying on
        a transfer: only :attr:`PointerFinality.is_final` means the transfer
        is beyond dispute."""
        resp = self._http.get(f"/v1/pointers/{address}/finality")
        _check(resp)
        return _pointers.finality_from_json(_json_object(resp))

    def pointer_controller(self, address: str) -> PointerController:
        """Follow the transfers of the pointer at ``address`` to the pointer
        whose owner now decides what it resolves to
        (``GET /v1/pointers/{address}/controller``)."""
        resp = self._http.get(f"/v1/pointers/{address}/controller")
        _check(resp)
        return _pointers.controller_from_json(_json_object(resp))

    def pointer_prepare(
        self,
        owner: str,
        op: PointerOp | str,
        *,
        target: str | None = None,
        kind: PointerKind | str | None = None,
        recipient: str | None = None,
        include_signed_quotes: bool = False,
    ) -> PointerPrepareResult:
        """Have the daemon sign ``op`` on the pointer at ``owner`` with its
        loaded key and quote it for an external signer
        (``POST /v1/pointers/prepare``). Needs no daemon wallet and pays
        nothing itself. Pay the result's ``payments`` with ``payForQuotes()``,
        then call :meth:`pointer_finalize`.

        Args:
            owner: The pointer's address; the daemon must hold its key.
            op: :attr:`PointerOp.CREATE` or :attr:`PointerOp.UPDATE` (pass
                ``target``, and ``kind`` to point at another pointer), or
                :attr:`PointerOp.TRANSFER` (pass ``recipient``).
            include_signed_quotes: also return each quote in full signed
                form (:attr:`PointerPrepareResult.signed_quotes`).

        Every check the daemon-wallet writes make before paying is made here,
        before anything is quoted. While the prepared write awaits payment,
        other writes to the pointer raise :class:`ConflictError` until it is
        finalized or expires (one hour).
        """
        body = _pointers.prepare_body(owner, op, target, kind, recipient, include_signed_quotes)
        resp = self._http.post("/v1/pointers/prepare", json=body)
        _check(resp)
        return _pointers.prepare_from_json(_json_object(resp))

    def pointer_finalize(self, upload_id: str, tx_hashes: dict[str, str]) -> PointerFinalizeResult:
        """Store a prepared pointer write once its external signer has paid
        (``POST /v1/pointers/finalize``). ``tx_hashes`` maps each
        ``quote_hash`` from :meth:`pointer_prepare`'s payments to the
        ``payForQuotes()`` transaction hash. Never retried.

        Raises:
            CloseGroupShortfallError: with ``retryable=True`` the write fell
                short after payment and the daemon kept the paid state: call
                this again with the same ``upload_id`` (``tx_hashes`` is then
                ignored) to store it against the same payment, bounding the
                loop. Without ``retryable`` nothing was kept.
            BadRequestError: the hashes do not match the payment; the session
                is kept, so it can be corrected.
            NotFoundError: ``upload_id`` expired or was already finalized.
        """
        resp = self._http.post("/v1/pointers/finalize", json={
            "upload_id": upload_id,
            "tx_hashes": tx_hashes,
        })
        _check(resp)
        return _pointers.finalize_from_json(_json_object(resp))


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

    @asynccontextmanager
    async def data_stream(self, data_map: str) -> AsyncIterator[AsyncIterator[bytes]]:
        """Stream private data from a caller-held DataMap (hex), one decrypt
        batch at a time. The streaming counterpart to :meth:`data_get`::

            async with client.data_stream(data_map) as chunks:
                async for chunk in chunks:
                    out.write(chunk)
        """
        async with self._http.stream("POST", "/v1/data/stream", json={"data_map": data_map}) as resp:
            await _acheck_streamed(resp)
            yield resp.aiter_bytes()

    @asynccontextmanager
    async def data_stream_public(self, address: str) -> AsyncIterator[AsyncIterator[bytes]]:
        """Stream public data by address — the streaming counterpart to
        :meth:`data_get_public` (see :meth:`data_stream`)."""
        async with self._http.stream("GET", f"/v1/data/public/{address}/stream") as resp:
            await _acheck_streamed(resp)
            yield resp.aiter_bytes()

    @asynccontextmanager
    async def data_stream_with_progress(self, data_map: str) -> AsyncIterator[AsyncIterator[DownloadFrame]]:
        """:meth:`data_stream` with interleaved fetch-progress frames. Opts into
        NDJSON framing and yields an async iterator of :class:`DownloadFrame`s
        (see the sync client's ``data_stream_with_progress``)."""
        headers = {"Accept": _NDJSON_CONTENT_TYPE}
        async with self._http.stream("POST", "/v1/data/stream", json={"data_map": data_map}, headers=headers) as resp:
            await _acheck_streamed(resp)

            async def frames() -> AsyncIterator[DownloadFrame]:
                async for line in resp.aiter_lines():
                    frame = _parse_ndjson_frame(line)
                    if frame is not None:
                        yield frame

            yield frames()

    @asynccontextmanager
    async def data_stream_public_with_progress(self, address: str) -> AsyncIterator[AsyncIterator[DownloadFrame]]:
        """:meth:`data_stream_public` with interleaved fetch-progress frames.
        See :meth:`data_stream_with_progress`."""
        headers = {"Accept": _NDJSON_CONTENT_TYPE}
        async with self._http.stream("GET", f"/v1/data/public/{address}/stream", headers=headers) as resp:
            await _acheck_streamed(resp)

            async def frames() -> AsyncIterator[DownloadFrame]:
                async for line in resp.aiter_lines():
                    frame = _parse_ndjson_frame(line)
                    if frame is not None:
                        yield frame

            yield frames()

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

    # --- Manifests ---
    #
    # The same methods, types and errors as RestClient's. Nothing is uploaded
    # or paid for, so they are safe to retry.

    async def build_manifest(
        self,
        entries: Sequence[ManifestEntryInput],
        *,
        name: str | None = None,
        torrent_info_hashes: Sequence[str] | None = None,
        embed_roots: bool = True,
    ) -> BuiltManifest:
        """See :meth:`RestClient.build_manifest`."""
        _manifests.check_entries(entries)
        hashes = _manifests.check_torrent_info_hashes(torrent_info_hashes)
        resp = await self._http.post(
            "/v1/manifests/build",
            json=_manifests.build_body(entries, name, hashes, embed_roots),
        )
        _check(resp)
        return _manifests.built_from_json(resp.json())

    async def decode_manifest(self, manifest: bytes, resolve: bool = False) -> DecodedManifest:
        """See :meth:`RestClient.decode_manifest`."""
        body = _manifests.decode_bytes_body(_manifests.manifest_bytes(manifest), resolve)
        resp = await self._http.post("/v1/manifests/decode", json=body)
        _check(resp)
        return _manifests.decoded_from_json(resp.json())

    async def decode_manifest_link(self, link: str, resolve: bool = False) -> DecodedManifest:
        """See :meth:`RestClient.decode_manifest_link`."""
        body = _manifests.decode_link_body(_manifests.check_link(link), resolve)
        resp = await self._http.post("/v1/manifests/decode", json=body)
        _check(resp)
        return _manifests.decoded_from_json(resp.json())

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
        """Finalize an upload after an external signer has submitted payment transactions.

        Raises:
            PartialUploadError: some chunks stored, others still unstored
                after the daemon's retries (HTTP 502 ``PARTIAL_UPLOAD`` /
                gRPC ``ABORTED``). The payment persists. ``retryable``: the
                daemon kept the paid attempt, so call this method again with
                the same arguments, bounding the loop. ``retention_known``
                and not ``retryable``: the daemon confirmed it kept nothing,
                so re-prepare the same content (already-stored chunks are
                skipped). Not ``retention_known``: the daemon may still hold
                the paid attempt, so stop, keep the ``upload_id`` and payment
                artefacts, and reconcile before re-preparing or paying
                again. See :class:`~antd.exceptions.PartialUploadError` and
                ``docs/external-signer-flow.md`` section 6.
        """
        resp = await self._http.post("/v1/upload/finalize", json={
            "upload_id": upload_id,
            "tx_hashes": tx_hashes,
        })
        _check(resp)
        return _parse_finalize_upload_result(resp.json())

    async def finalize_merkle_upload(
        self, upload_id: str, winner_pool_hash: str, store_data_map: bool = False,
    ) -> FinalizeUploadResult:
        """Finalize a merkle-batch upload after selecting a winning pool.

        Raises:
            PartialUploadError: some chunks stored, others still unstored
                after the daemon's retries (HTTP 502 ``PARTIAL_UPLOAD`` /
                gRPC ``ABORTED``). The payment persists. ``retryable``: the
                daemon kept the paid attempt, so call this method again with
                the same arguments, bounding the loop. ``retention_known``
                and not ``retryable``: the daemon confirmed it kept nothing,
                so re-prepare the same content (already-stored chunks are
                skipped). Not ``retention_known``: the daemon may still hold
                the paid attempt, so stop, keep the ``upload_id`` and payment
                artefacts, and reconcile before re-preparing or paying
                again. See :class:`~antd.exceptions.PartialUploadError` and
                ``docs/external-signer-flow.md`` section 6.
        """
        resp = await self._http.post("/v1/upload/finalize", json={
            "upload_id": upload_id,
            "winner_pool_hash": winner_pool_hash,
            "store_data_map": store_data_map,
        })
        _check(resp)
        return _parse_finalize_upload_result(resp.json())

    # --- Pointers ---
    #
    # Same methods, types and errors as RestClient (see there). Every write
    # pays and is never retried; reads are free to retry.

    async def pointer_keys(self) -> list[str]:
        """See :meth:`RestClient.pointer_keys`."""
        resp = await self._http.get("/v1/pointers/keys")
        _check(resp)
        return _pointers.keys_from_json(_json_object(resp))

    async def pointer_create(
        self, owner: str, target: str, kind: PointerKind | str = PointerKind.CHUNK,
    ) -> PointerWriteResult:
        """See :meth:`RestClient.pointer_create`. Pays; never retried."""
        resp = await self._http.post("/v1/pointers", json=_pointers.write_body(owner, target, kind))
        _check(resp)
        return _pointers.write_from_json(_json_object(resp))

    async def pointer_update(
        self, owner: str, target: str, kind: PointerKind | str = PointerKind.CHUNK,
    ) -> PointerWriteResult:
        """See :meth:`RestClient.pointer_update`. Pays; never retried."""
        resp = await self._http.post("/v1/pointers/update", json=_pointers.write_body(owner, target, kind))
        _check(resp)
        return _pointers.write_from_json(_json_object(resp))

    async def pointer_transfer(self, owner: str, recipient: str) -> PointerTransferResult:
        """See :meth:`RestClient.pointer_transfer`. Pays; never retried."""
        resp = await self._http.post("/v1/pointers/transfer", json={"owner": owner, "recipient": recipient})
        _check(resp)
        return _pointers.transfer_from_json(_json_object(resp))

    async def pointer_get(self, address: str) -> PointerRecord:
        """See :meth:`RestClient.pointer_get`."""
        resp = await self._http.get(f"/v1/pointers/{address}")
        _check(resp)
        return _pointers.record_from_json(_json_object(resp))

    async def pointer_resolve(self, address: str) -> PointerTarget:
        """See :meth:`RestClient.pointer_resolve`."""
        resp = await self._http.get(f"/v1/pointers/{address}/resolve")
        _check(resp)
        return _pointers.target_from_json(_json_object(resp))

    async def pointer_finality(self, address: str) -> PointerFinality:
        """See :meth:`RestClient.pointer_finality`."""
        resp = await self._http.get(f"/v1/pointers/{address}/finality")
        _check(resp)
        return _pointers.finality_from_json(_json_object(resp))

    async def pointer_controller(self, address: str) -> PointerController:
        """See :meth:`RestClient.pointer_controller`."""
        resp = await self._http.get(f"/v1/pointers/{address}/controller")
        _check(resp)
        return _pointers.controller_from_json(_json_object(resp))

    async def pointer_prepare(
        self,
        owner: str,
        op: PointerOp | str,
        *,
        target: str | None = None,
        kind: PointerKind | str | None = None,
        recipient: str | None = None,
        include_signed_quotes: bool = False,
    ) -> PointerPrepareResult:
        """See :meth:`RestClient.pointer_prepare`."""
        body = _pointers.prepare_body(owner, op, target, kind, recipient, include_signed_quotes)
        resp = await self._http.post("/v1/pointers/prepare", json=body)
        _check(resp)
        return _pointers.prepare_from_json(_json_object(resp))

    async def pointer_finalize(self, upload_id: str, tx_hashes: dict[str, str]) -> PointerFinalizeResult:
        """See :meth:`RestClient.pointer_finalize`. Never retried."""
        resp = await self._http.post("/v1/pointers/finalize", json={
            "upload_id": upload_id,
            "tx_hashes": tx_hashes,
        })
        _check(resp)
        return _pointers.finalize_from_json(_json_object(resp))
