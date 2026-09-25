"""Example 07: External-signer flow — public file + single-chunk publish.

PR #90 added `prepare_upload_public` / `finalize_upload` and
`prepare_chunk_upload` / `finalize_chunk_upload` so the wallet key never has
to live in the antd daemon. This example uses anvil deterministic account #0
as the external signer and exercises both round-trips end-to-end.

See `docs/external-signer-flow.md` for the full reference; the contract ABI
loaded below is committed at `docs/abi/IPaymentVault.json`. Section 6 of that
doc covers the partial-store case that `finalize_with_retry` and `next_step`
below handle.

Requires `web3` and `eth-account` (pip install web3 eth-account).
"""

import json
import os
import tempfile
import time
from pathlib import Path

from antd import AntdClient, PartialUploadError
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


def finalize_with_retry(client, upload_id, tx_hashes, max_attempts=5):
    """Finalize, resuming a partial store against the same payment.

    A finalize can fail *after* the wallet has paid: some chunks store,
    others miss quorum after the daemon's own retries. That raises
    `PartialUploadError`; the on-chain payment persists and the stored
    chunks stay on the network. Its flags give three cases, and only the
    first is retried here:

    - `retryable` (antd >= 0.14.0): the daemon kept the paid attempt under
      the same `upload_id`, so the same call with the same arguments stores
      the remainder against the same payment -- no re-prepare, no second
      signature, no double payment. The loop is bounded: at most
      `max_attempts` calls, and a `chunks_failed` that stops shrinking
      counts as stuck.
    - `retention_known` and not `retryable`: the daemon confirmed it kept
      nothing. The caller re-prepares the same content, which skips
      already-stored chunks and pays only for the remainder.
    - not `retention_known`: retention is unknown, and the daemon may still
      hold the paid attempt. The caller stops, keeps `upload_id` and
      `tx_hashes`, and reconciles before re-preparing or paying again.
      Never pay again on this signal alone. Daemons before 0.14.0 land here.

    Whenever it stops (not retryable, retention unknown, attempts exhausted
    or stalled) it re-raises the original `PartialUploadError` unchanged, so
    the caller branches on the same typed fields (see `next_step`). It never
    re-prepares or pays by itself.

    See `docs/external-signer-flow.md` section 6.
    """
    last_failed = None
    for attempt in range(1, max_attempts + 1):
        try:
            return client.finalize_upload(upload_id, tx_hashes)  # every chunk stored
        except PartialUploadError as e:
            if not e.retryable:
                raise  # nothing to resume here: known-empty or unknown retention
            stuck = last_failed is not None and e.chunks_failed >= last_failed
            if attempt == max_attempts or stuck:
                raise  # the paid attempt is still retained under upload_id
            last_failed = e.chunks_failed
            print(
                f"finalize stored {e.chunks_stored}/{e.total_chunks} chunks, "
                f"{e.chunks_failed} still unstored -- retrying against the same "
                f"payment (attempt {attempt + 1}/{max_attempts})"
            )
            time.sleep(2 * attempt)


def next_step(e, upload_id):
    """Say what to do once `finalize_with_retry` has given up with `e`."""
    progress = (
        f"{e.chunks_stored}/{e.total_chunks} chunks stored, "
        f"{e.chunks_failed} still unstored"
    )
    if e.retryable:
        return (
            f"{progress}. The paid attempt is still retained under upload_id "
            f"{upload_id}: retry the same finalize later, before the daemon's "
            "pending-upload TTL expires."
        )
    if e.retention_known:
        return (
            f"{progress}. The daemon kept nothing: re-prepare the same content "
            "(already-stored chunks are skipped, so only the remainder is paid for)."
        )
    return (
        f"{progress}. Retention is unknown: the daemon may still hold the paid "
        f"attempt. Stop, keep upload_id {upload_id} and the tx hashes, and "
        "reconcile before re-preparing or paying again."
    )


def main():
    client = AntdClient()
    acct = Account.from_key(ANVIL_KEY)

    # --- 1. file upload via external signer -------------------------------
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
        try:
            fin = finalize_with_retry(client, prep.upload_id, tx_hashes)
        except PartialUploadError as e:
            print(next_step(e, prep.upload_id))
            raise
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

    # --- 2. single-chunk publish via external signer ----------------------
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


if __name__ == "__main__":
    main()
