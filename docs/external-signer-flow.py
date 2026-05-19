#!/usr/bin/env python3
"""Worked end-to-end external-signer round-trip against `ant dev start --enable-evm`.

Mirrors the snippet embedded in docs/external-signer-flow.md. Reference for the
15-SDK fan-out (V2-312); runnable as a smoke test for V2-311.

Usage:
    ant dev start --enable-evm          # one terminal
    python docs/external-signer-flow.py # another

Environment:
    ANTD    daemon base URL (default: http://127.0.0.1:8000)
"""

import json
import os
import sys
import tempfile

import requests
from eth_account import Account
from web3 import Web3

ANVIL_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ANTD = os.environ.get("ANTD", "http://127.0.0.1:8000")
ABI_PATH = os.path.join(os.path.dirname(__file__), "abi", "IPaymentVault.json")
ERC20_ABI = [
    {
        "name": "approve",
        "type": "function",
        "stateMutability": "nonpayable",
        "inputs": [
            {"name": "spender", "type": "address"},
            {"name": "value", "type": "uint256"},
        ],
        "outputs": [{"type": "bool"}],
    }
]
MAX_UINT256 = (1 << 256) - 1


def main() -> int:
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
        f.write(b"hello external signer\n" * 16)  # ~352 bytes, single wave
        src = f.name
    try:
        # ---- 1. ask the daemon for a payment intent ---------------------
        prep = requests.post(
            f"{ANTD}/v1/files/prepare_upload_public", json={"path": src}
        ).json()
        if prep.get("payment_type") != "wave_batch":
            print(f"unexpected payment_type: {prep!r}", file=sys.stderr)
            return 1

        w3 = Web3(Web3.HTTPProvider(prep["rpc_url"]))
        acct = Account.from_key(ANVIL_KEY)
        vault_addr = Web3.to_checksum_address(prep["payment_vault_address"])
        token_addr = Web3.to_checksum_address(prep["payment_token_address"])

        # ---- 2. approve the vault to spend our antToken -----------------
        token = w3.eth.contract(address=token_addr, abi=ERC20_ABI)
        tx = token.functions.approve(vault_addr, MAX_UINT256).build_transaction(
            {
                "from": acct.address,
                "nonce": w3.eth.get_transaction_count(acct.address),
                "chainId": w3.eth.chain_id,
            }
        )
        signed = acct.sign_transaction(tx)
        rcpt = w3.eth.wait_for_transaction_receipt(
            w3.eth.send_raw_transaction(signed.raw_transaction)
        )
        if rcpt.status != 1:
            print(f"approve reverted: {rcpt!r}", file=sys.stderr)
            return 1

        # ---- 3. payForQuotes --------------------------------------------
        with open(ABI_PATH) as fh:
            vault = w3.eth.contract(address=vault_addr, abi=json.load(fh))
        payments = [
            (
                Web3.to_checksum_address(p["rewards_address"]),
                int(p["amount"]),
                bytes.fromhex(p["quote_hash"].removeprefix("0x")),
            )
            for p in prep["payments"]
        ]
        tx = vault.functions.payForQuotes(payments).build_transaction(
            {
                "from": acct.address,
                "nonce": w3.eth.get_transaction_count(acct.address),
                "chainId": w3.eth.chain_id,
            }
        )
        signed = acct.sign_transaction(tx)
        rcpt = w3.eth.wait_for_transaction_receipt(
            w3.eth.send_raw_transaction(signed.raw_transaction)
        )
        if rcpt.status != 1:
            print(f"payForQuotes reverted: {rcpt!r}", file=sys.stderr)
            return 1
        pay_tx = rcpt.transactionHash.hex()

        # ---- 4. hand tx hashes back to the daemon -----------------------
        # Every quote was paid in the same payForQuotes call, so every entry
        # in tx_hashes maps to the same tx hash.
        tx_hashes = {p["quote_hash"]: pay_tx for p in prep["payments"]}
        fin = requests.post(
            f"{ANTD}/v1/files/finalize_upload",
            json={"upload_id": prep["upload_id"], "tx_hashes": tx_hashes},
        ).json()
        addr = fin["data_map_address"]

        # ---- 5. download to verify --------------------------------------
        with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as out:
            dst = out.name
        rsp = requests.post(
            f"{ANTD}/v1/files/download_public",
            json={"address": addr, "path": dst},
        )
        if rsp.status_code != 200:
            print(f"download_public failed: {rsp.status_code} {rsp.text}", file=sys.stderr)
            return 1
        with open(src, "rb") as a, open(dst, "rb") as b:
            if a.read() != b.read():
                print("round-trip mismatch", file=sys.stderr)
                return 1
        print(f"OK  uploaded + downloaded {os.path.getsize(src)} bytes via external signer")
        print(f"    data_map_address = {addr}")
        print(f"    payForQuotes tx  = {pay_tx}")
        return 0
    finally:
        try:
            os.unlink(src)
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
