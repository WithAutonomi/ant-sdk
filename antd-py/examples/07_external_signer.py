"""Example 07: External-signer flow — public file + single-chunk publish.

PR #90 added `prepare_upload_public` / `finalize_upload` and
`prepare_chunk_upload` / `finalize_chunk_upload` so the wallet key never has
to live in the antd daemon. This example uses anvil deterministic account #0
as the external signer and exercises both round-trips end-to-end.

See `docs/external-signer-flow.md` for the full reference; the contract ABI
loaded below is committed at `docs/abi/IPaymentVault.json`.

Requires `web3` and `eth-account` (pip install web3 eth-account).
"""

import json
import os
import tempfile
from pathlib import Path

from antd import AntdClient
from eth_account import Account
from web3 import Web3

# Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
# (storage payment) by `ant dev start --enable-evm` devnet genesis. The
# private key is in every anvil-using project on earth — never use it
# anywhere except a throw-away local devnet.
ANVIL_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
MAX_UINT256 = (1 << 256) - 1

# Minimal ERC-20 ABI for approve(). antToken is a standard ERC-20.
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
    },
]

# Repo-bundled IPaymentVault ABI (see docs/external-signer-flow.md).
ABI_PATH = Path(__file__).resolve().parents[2] / "docs" / "abi" / "IPaymentVault.json"
VAULT_ABI = json.loads(ABI_PATH.read_text())


def external_signer_pay(prep, acct):
    """Run approve + payForQuotes on-chain for a daemon prepare response.

    Returns the `quote_hash -> tx_hash` map the daemon's finalize_* methods
    expect. Every entry maps to the same `payForQuotes` tx because every
    quote in the wave is paid in one batched call.

    No on-chain work needed when every quoted chunk is already on-network
    (the daemon's prepare step elides zero-amount payments). Finalize
    accepts an empty tx_hashes map in this case.
    """
    if not prep.payments:
        return {}

    w3 = Web3(Web3.HTTPProvider(prep.rpc_url))
    vault_addr = Web3.to_checksum_address(prep.payment_vault_address)
    token_addr = Web3.to_checksum_address(prep.payment_token_address)

    # approve(vault, MAX) -- idempotent and cheap; example uses MAX so
    # subsequent flows in this run skip a fresh approval.
    token = w3.eth.contract(address=token_addr, abi=ERC20_ABI)
    tx = token.functions.approve(vault_addr, MAX_UINT256).build_transaction(
        {
            "from": acct.address,
            "nonce": w3.eth.get_transaction_count(acct.address),
            "chainId": w3.eth.chain_id,
        }
    )
    rcpt = w3.eth.wait_for_transaction_receipt(
        w3.eth.send_raw_transaction(acct.sign_transaction(tx).raw_transaction)
    )
    assert rcpt.status == 1, ("approve reverted", rcpt)

    # payForQuotes -- one tx covering every quote in this wave.
    vault = w3.eth.contract(address=vault_addr, abi=VAULT_ABI)
    payments = [
        (
            Web3.to_checksum_address(p.rewards_address),
            int(p.amount),
            bytes.fromhex(p.quote_hash.removeprefix("0x")),
        )
        for p in prep.payments
    ]
    tx = vault.functions.payForQuotes(payments).build_transaction(
        {
            "from": acct.address,
            "nonce": w3.eth.get_transaction_count(acct.address),
            "chainId": w3.eth.chain_id,
        }
    )
    rcpt = w3.eth.wait_for_transaction_receipt(
        w3.eth.send_raw_transaction(acct.sign_transaction(tx).raw_transaction)
    )
    assert rcpt.status == 1, ("payForQuotes reverted", rcpt)
    pay_tx = rcpt.transactionHash.hex()

    return {p.quote_hash: pay_tx for p in prep.payments}


client = AntdClient()
acct = Account.from_key(ANVIL_KEY)

# --- 1. file upload via external signer -----------------------------------
with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
    f.write(b"hello external signer (file)\n" * 16)  # ~480 bytes, single wave
    src = f.name
try:
    prep = client.prepare_upload_public(src)
    print(
        f"File prepare: upload_id={prep.upload_id[:16]}..., "
        f"payment_type={prep.payment_type}, "
        f"payments={len(prep.payments)}, total_amount={prep.total_amount}"
    )

    tx_hashes = external_signer_pay(prep, acct)
    fin = client.finalize_upload(prep.upload_id, tx_hashes)
    print(
        f"File finalize: data_map_address={fin.data_map_address}, "
        f"chunks_stored={fin.chunks_stored}"
    )

    dst = src + ".downloaded"
    client.file_get_public(fin.data_map_address, dst)
    with open(src, "rb") as a, open(dst, "rb") as b:
        assert a.read() == b.read(), "file round-trip mismatch"
    os.unlink(dst)
    print("File round-trip OK!")
finally:
    os.unlink(src)


# --- 2. single-chunk publish via external signer --------------------------
chunk_data = b"hello external signer (chunk)\n" * 8  # ~240 bytes
prep = client.prepare_chunk_upload(chunk_data)
if prep.already_stored:
    # Network already has this exact chunk -- no payment, no finalize step.
    print(f"Chunk prepare: already_stored, address={prep.address}")
else:
    print(
        f"Chunk prepare: upload_id={prep.upload_id[:16]}..., "
        f"address={prep.address}, payments={len(prep.payments)}, "
        f"total_amount={prep.total_amount}"
    )
    tx_hashes = external_signer_pay(prep, acct)
    addr = client.finalize_chunk_upload(prep.upload_id, tx_hashes)
    assert addr == prep.address, ("chunk address mismatch", addr, prep.address)
    print(f"Chunk finalize: address={addr}")

got = client.chunk_get(prep.address)
assert got == chunk_data, "chunk round-trip mismatch"
print("Chunk round-trip OK!")

print("\n07_external_signer OK!")
