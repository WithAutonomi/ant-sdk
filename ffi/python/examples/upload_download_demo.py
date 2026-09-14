#!/usr/bin/env python3
"""Devnet upload/download round-trip demo for the Python FFI bindings.

Mirrors the Swift/Kotlin demo's devnet path: connect from the devnet manifest,
upload a file with the manifest wallet paying inside ant-core (single-shot),
download it back to disk with live progress, and verify it is byte-identical.

Run against a local devnet started with `ant dev start` (or `ant-devnet`
writing its manifest to ~/.ant-dev/devnet-manifest.json).

    python3 examples/upload_download_demo.py
"""

from __future__ import annotations

import asyncio
import hashlib
import os
import sys
import tempfile
from pathlib import Path

# Make the sibling package importable when run straight from the repo.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import ant_ffi
from ant_ffi import Client, PaymentMode, ProgressListener, ProgressUpdate

MANIFEST = Path.home() / ".ant-dev" / "devnet-manifest.json"


class PrintProgress(ProgressListener):
    """Callback interface impl — invoked from a Rust/tokio worker thread."""

    def __init__(self, what: str) -> None:
        self._what = what
        self._last = ""

    def on_progress(self, update: ProgressUpdate) -> None:
        # phase is an enum; total==0 means indeterminate.
        phase = getattr(update.phase, "name", str(update.phase))
        if update.total:
            line = f"  [{self._what}] {phase}: {update.done}/{update.total}"
        else:
            line = f"  [{self._what}] {phase}: {update.done}"
        if line != self._last:
            print(line)
            self._last = line


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


async def main() -> int:
    print(f"ant_ffi version: {ant_ffi.ant_ffi_version()}")
    if not MANIFEST.exists():
        print(f"ERROR: no devnet manifest at {MANIFEST}", file=sys.stderr)
        print("Start a devnet first (ant dev start / ant-devnet).", file=sys.stderr)
        return 2

    print(f"Connecting from devnet manifest: {MANIFEST}")
    client = await Client.connect_from_devnet_manifest(str(MANIFEST))
    print("Connected.")

    workdir = Path(tempfile.mkdtemp(prefix="ant-ffi-demo-"))
    src = workdir / "hello.txt"
    payload = b"Hello from the Autonomi Python FFI bindings!\n" * 4096  # ~180 KB
    src.write_bytes(payload)
    src_hash = _sha256(src)
    print(f"\nUploading {src} ({src.stat().st_size} bytes, sha256 {src_hash[:16]}...)")

    up = await client.file_upload_public(str(src), PaymentMode.AUTO)
    print("Upload complete:")
    print(f"  address:       {up.address}")
    print(f"  chunks_stored: {up.chunks_stored}")
    print(f"  storage_cost:  {up.storage_cost_atto} atto")
    print(f"  gas_cost:      {up.gas_cost_wei} wei")
    print(f"  payment_mode:  {getattr(up.payment_mode_used, 'name', up.payment_mode_used)}")

    dest = workdir / "hello.downloaded.txt"
    print(f"\nDownloading {up.address} -> {dest}")
    written = await client.download_public_to_file(
        up.address, str(dest), PrintProgress("download")
    )
    print(f"Downloaded {written} bytes.")

    dst_hash = _sha256(dest)
    ok = dst_hash == src_hash and written == src.stat().st_size
    print("\nRound-trip verification:")
    print(f"  source sha256:     {src_hash}")
    print(f"  downloaded sha256: {dst_hash}")
    print(f"  RESULT: {'PASS — byte-identical' if ok else 'FAIL — mismatch'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
