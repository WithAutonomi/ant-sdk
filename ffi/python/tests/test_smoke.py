"""Offline smoke tests for the Python FFI bindings.

Mirror of ffi/csharp/AntFfi.Tests: no network required. Verifies the generated
bindings load (import + version) and a deterministic offline crypto op works
(EVM address derivation from a known private key). The devnet put/get round-trip
is exercised separately by examples/upload_download_demo.py where a devnet exists.

    python3 -m pytest tests/    # or: python3 tests/test_smoke.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import ant_ffi
from ant_ffi import Wallet

# Standard Anvil dev account #0 — deterministic key -> address, pure crypto,
# no RPC reachability needed.
_ANVIL_KEY = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
_ANVIL_ADDR = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"


def test_bindings_load_and_report_version():
    v = ant_ffi.ant_ffi_version()
    assert isinstance(v, str) and v, "ant_ffi_version() should return a version string"


def test_wallet_address_derivation_offline():
    w = Wallet.from_private_key(
        _ANVIL_KEY,
        "http://localhost:8545",  # not contacted for address derivation
        "0x5FbDB2315678afecb367f032d93F642f64180aa3",
        "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    )
    assert w.address().lower() == _ANVIL_ADDR


if __name__ == "__main__":
    test_bindings_load_and_report_version()
    test_wallet_address_derivation_offline()
    print(f"OK — ant_ffi {ant_ffi.ant_ffi_version()}: both offline smoke tests passed")
