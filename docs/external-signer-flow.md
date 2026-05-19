# External-Signer Upload Flow

Reference for SDK authors implementing `07_external_signer` examples. Covers the two-phase upload flow where the user's wallet key never touches the antd daemon — the daemon prepares a payment intent, the SDK signs and submits the EVM transaction(s) externally, and the daemon finalizes once the on-chain payment is settled.

This is the surface added by [PR #90](https://github.com/WithAutonomi/ant-sdk/pull/90) (squash `a3cf4e40`, merged 2026-05-18) and re-exported by every SDK as `prepare_upload_public` / `finalize_upload` / `prepare_chunk_upload` / `finalize_chunk_upload`.

## When to use this flow

Anytime the wallet key cannot live in the antd daemon: mobile apps, browser wallets, hardware wallets, agents under a managed keystore, anything with a custody boundary. The internal-wallet path (`file_upload_public(path)`) is shorter but requires the daemon to hold the private key.

## Architecture in one diagram

```
  ┌────────────┐                                          ┌─────────────────┐
  │  SDK app   │                                          │  antd daemon    │
  │ (15 langs) │                                          │                 │
  └─────┬──────┘                                          └────────┬────────┘
        │                                                          │
        │   POST /v1/files/prepare_upload_public { path }          │
        │ ────────────────────────────────────────────────────────▶│
        │                                                          │
        │   PrepareUploadResult {                                  │
        │     upload_id, payments[],                               │
        │     payment_vault_address, payment_token_address,        │
        │     rpc_url, total_amount, payment_type="wave_batch" }   │
        │ ◀────────────────────────────────────────────────────────│
        │                                                          │
        │           ┌─────────────────────────────────┐            │
        │           │     EVM chain (anvil/Arbitrum)  │            │
        │           └────────────────┬────────────────┘            │
        │                            │                             │
        │   antToken.approve(vault, MAX)                           │
        │ ─────────────────────────▶ │                             │
        │                            │                             │
        │   paymentVault.payForQuotes(payments)                    │
        │ ─────────────────────────▶ │  ──▶ tx_hash                │
        │                            │                             │
        │   POST /v1/files/finalize_upload                         │
        │      { upload_id, tx_hashes: { <quote_hash>: <tx>, … } } │
        │ ────────────────────────────────────────────────────────▶│
        │                                                          │
        │   FinalizeUploadResult { data_map_address, … }           │
        │ ◀────────────────────────────────────────────────────────│
        │                                                          │
```

## What the daemon hands the SDK

`prepare_upload_public(path)` returns everything the SDK needs to construct the on-chain transaction. SDKs **do not** need to hardcode the contract address, RPC URL, or token address — all flow over the wire at runtime.

Reference shape (from `antd-py/src/antd/models.py:79`, equivalent in every SDK):

```python
class PrepareUploadResult:
    upload_id: str                  # opaque, hand back to finalize_upload
    payments: list[PaymentInfo]     # [(quote_hash, rewards_address, amount), …]
    total_amount: str               # atto-tokens, decimal string
    payment_vault_address: str      # IPaymentVault contract (hex)
    payment_token_address: str      # antToken ERC-20 contract (hex)
    rpc_url: str                    # EVM RPC endpoint
    payment_type: str               # "wave_batch" | "merkle_batch"
    depth: int                      # merkle only
    pool_commitments: list[…]       # merkle only
    merkle_payment_timestamp: int   # merkle only

class PaymentInfo:
    quote_hash: str                 # 32-byte hex, the bytes32 quoteHash in the contract
    rewards_address: str            # 20-byte hex, the address rewardsAddress
    amount: str                     # atto-tokens, decimal string -> uint256
```

For small files (<4 KiB) and any single-chunk publish, `payment_type` will always be `"wave_batch"`. Merkle batching kicks in only for large uploads and is out of scope here (see [Merkle path](#merkle-path-out-of-scope) at the end).

## The contract: `IPaymentVault`

Solidity interface, bundled in this repo at [`docs/abi/IPaymentVault.json`](abi/IPaymentVault.json). Source: `evmlib 0.8.1` `abi/IPaymentVault.json`, re-exported via `ant_protocol::evm::contract::payment_vault`. The ABI is **byte-identical between evmlib 0.8.0 and 0.8.1** (SHA-256 `8c73043056387530bbe721171c950d22af27b2d02fd76309a2d19cea879f8110`), so bundling a single copy is safe.

Functions an SDK needs:

| Selector | Signature | Notes |
| --- | --- | --- |
| `0x77a23fd7` | `payForQuotes((address rewardsAddress, uint256 amount, bytes32 quoteHash)[])` | wave_batch payment, nonpayable |
| `0x095ea7b3` | `approve(address spender, uint256 value)` on antToken | one-time ERC-20 approve |
| `0x4ec42e8e` | `antToken() view returns (address)` | redundant if daemon hands you `payment_token_address` |
| `0x474740b1` | `batchLimit() view returns (uint256)` | max payments per `payForQuotes` call |
| `0x58b630e2` | `payForMerkleTree(uint8 depth, PoolCommitment[] pools, uint64 timestamp) returns (bytes32, uint256)` | merkle_batch, out of scope here |

The `DataPayment` struct passed to `payForQuotes` is:

```solidity
struct DataPayment {
    address rewardsAddress;   // who gets paid
    uint256 amount;           // how much (atto-tokens)
    bytes32 quoteHash;        // ties this payment to a specific quote from the network
}
```

Confirmed by the `From<(QuoteHash, Address, Amount)>` impl in `evmlib/src/contract/payment_vault/interface.rs:16` — note the field order `(rewardsAddress, amount, quoteHash)` not `(quoteHash, rewardsAddress, amount)`.

## Wave-batch flow (the only path V2-312 needs)

Five steps, two on-chain transactions:

### 1. Prepare

```http
POST /v1/files/prepare_upload_public
Content-Type: application/json

{ "path": "/abs/path/to/small_file.bin" }
```

Returns `PrepareUploadResult` (see above). For a file under 4 KiB you'll typically get **one payment** in `payments`, but design for `len(payments) >= 1` since wave batching can pack up to 64 chunks per call.

### 2. ERC-20 approve

Allow the payment vault to pull `total_amount` (or `2**256-1` for unlimited, which is what `evmlib/src/wallet.rs:188` does) from your wallet's antToken balance. Standard ERC-20 `approve(address,uint256)`:

```
selector:  0x095ea7b3
calldata:  0x095ea7b3
           + 0000000000000000000000005FbDB2315678afecb367f032d93F642f64180aa3  ← payment_vault_address (left-pad to 32)
           + ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff  ← uint256.MAX (or total_amount)
```

To: `payment_token_address`. Value: 0. Sign + send via the user's external signer. Wait for receipt (no event-filtering needed; the receipt is enough).

This is **one-time per wallet × vault pair** — subsequent uploads reuse the allowance. Examples can either always approve MAX (idempotent and cheap) or check `allowance()` first; MAX is simplest.

### 3. payForQuotes

Construct calldata: selector + ABI-encoded `DataPayment[]`. Every web3 library can do this from the bundled ABI — just call `paymentVault.payForQuotes(payments)` with `payments` as an array of `(rewardsAddress, amount, quoteHash)` tuples.

```
selector:  0x77a23fd7
calldata:  0x77a23fd7
           + 0000…0020   ← offset to dynamic array (32 bytes from start of args)
           + 0000…000N   ← array length N
           + <DataPayment_0>    ← 96 bytes per struct, packed (3 × 32B fields)
           + <DataPayment_1>
           + …
```

Each `DataPayment` is 96 bytes flat (no inner offsets — all fields are static-size):

```
0..32   address rewardsAddress    (left-padded to 32)
32..64  uint256 amount            (big-endian)
64..96  bytes32 quoteHash         (raw)
```

To: `payment_vault_address`. Value: 0. Sign + send. Wait for receipt. Single tx_hash covers **every** quote in `payments`.

### 4. Build `tx_hashes` mapping

```
tx_hashes = { p.quote_hash: payForQuotes_tx_hash for p in payments }
```

Every entry maps to the **same** tx hash because every quote was paid in the same `payForQuotes` call. The map shape is keyed-by-quote so the daemon can tie each chunk's payment proof to a receipt without the SDK having to think about whether quotes were batched or not.

Confirmed by `evmlib::wallet::pay_for_quotes` (`src/wallet.rs:145`) returning `BTreeMap<QuoteHash, TxHash>` with repeated values.

### 5. Finalize

```http
POST /v1/files/finalize_upload
Content-Type: application/json

{
  "upload_id": "<from step 1>",
  "tx_hashes": { "<quote_hash_0>": "<tx_hash>", "<quote_hash_1>": "<tx_hash>", … }
}
```

Returns `FinalizeUploadResult { data_map_address, data_map, chunks_stored, address }`. The `data_map_address` is what other clients use to retrieve the file via `file_download_public(data_map_address)`.

## Single-chunk publish

Same shape, different daemon endpoints:

| Step | File upload | Single-chunk publish |
| --- | --- | --- |
| Prepare | `POST /v1/files/prepare_upload_public { path }` | `POST /v1/chunks/prepare_upload { data }` |
| `already_stored` short-circuit | n/a | `PrepareChunkResult.already_stored=True` → skip on-chain, return early |
| Approve + payForQuotes | identical | identical |
| Finalize | `POST /v1/files/finalize_upload` | `POST /v1/chunks/finalize_upload` |
| Result | `data_map_address` | `address` (the chunk's network address) |

`prepare_chunk_upload` has the `already_stored` short-circuit because the network may already have the chunk (single chunks are deterministically addressed by content). When `already_stored=True`, `upload_id` and `payments` are empty — the SDK should just return the chunk address without any on-chain activity.

## Events (optional)

The vault emits `DataPaymentMade(address rewardsAddress, uint256 amount, bytes32 quoteHash)` per payment — one log entry per entry in the array passed to `payForQuotes`. Topic0: `0xf998960b1c6f0e0e89b7bbe6b6fbf3e03e6f08eee5b8430877d8adb8e149d580`.

Examples don't need to filter these; waiting for the transaction receipt to be mined is sufficient. If you want to verify on-chain visibility post-merge, log filters work the standard way.

(Merkle path emits `MerklePaymentMade(bytes32 poolHash, uint8 depth, uint256, uint64 timestamp)`, topic0 `0x89f0ad3859fec321e325bcc553fe234bcad374789a86f7ba932067f3f05affec`.)

## Errors

Custom contract errors thrown by `IPaymentVault`:

| Selector | Signature | When |
| --- | --- | --- |
| `0xb418582c` | `AntTokenNull()` | vault initialised without antToken — should never fire on a healthy devnet |
| `0x359fd044` | `BatchLimitExceeded()` | `payments.length > batchLimit()` — increase batching or split into multiple txs |
| `0x9d8c19ed` | `PaymentAlreadyExists(bytes32 quoteHash)` | reusing a quote_hash — the prepare step gave you a fresh one, so this means you held the result too long or replayed it |
| `0x5274afe7` | `SafeERC20FailedOperation(address)` | antToken `transferFrom` failed — usually means `approve` wasn't called or was insufficient |
| `0x2c96be06` | `DepthTooLarge(uint8 supplied, uint8 maxAllowed)` | merkle path only |
| `0x8ffc236a` | `WrongPoolCount(uint256 supplied, uint256 expected)` | merkle path only |
| `0x7db491eb` | `InvalidInputLength()` | merkle path only |

Against `ant dev start --enable-evm` with a small file and a fresh prepare, none of these should fire.

## Anvil deterministic signer

`ant dev start --enable-evm` spins up `anvil` with the standard deterministic accounts. Examples should use **account #0**:

```
address:     0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
private key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

This account is pre-funded with ETH (gas) and with antToken (per devnet genesis). Don't use it for anything outside the dev environment — the private key is in every anvil-using project on earth.

## Worked python snippet

A runnable round-trip, mirrored as [`external-signer-flow.py`](external-signer-flow.py) in this directory so it can be invoked directly against a live devnet:

```bash
ant dev start --enable-evm                   # one terminal
python docs/external-signer-flow.py          # the other
```

```python
import os, tempfile, requests
from web3 import Web3
from eth_account import Account

ANVIL_KEY  = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ANTD       = os.environ.get("ANTD", "http://127.0.0.1:8000")
ABI_PATH   = os.path.join(os.path.dirname(__file__), "abi", "IPaymentVault.json")
ERC20_ABI  = [{"name":"approve","type":"function","stateMutability":"nonpayable",
               "inputs":[{"name":"spender","type":"address"},{"name":"value","type":"uint256"}],
               "outputs":[{"type":"bool"}]}]
MAX_UINT256 = (1 << 256) - 1

def main():
    # ---- 1. ask the daemon for a payment intent --------------------------
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
        f.write(b"hello external signer\n" * 16)        # ~352 bytes, single wave
        src = f.name
    try:
        prep = requests.post(f"{ANTD}/v1/files/prepare_upload_public",
                             json={"path": src}).json()
        assert prep["payment_type"] == "wave_batch", prep

        w3 = Web3(Web3.HTTPProvider(prep["rpc_url"]))
        acct = Account.from_key(ANVIL_KEY)
        vault_addr = Web3.to_checksum_address(prep["payment_vault_address"])
        token_addr = Web3.to_checksum_address(prep["payment_token_address"])

        # ---- 2. approve the vault to spend our antToken -----------------
        token = w3.eth.contract(address=token_addr, abi=ERC20_ABI)
        tx = token.functions.approve(vault_addr, MAX_UINT256).build_transaction({
            "from": acct.address,
            "nonce": w3.eth.get_transaction_count(acct.address),
            "chainId": w3.eth.chain_id,
        })
        rcpt = w3.eth.wait_for_transaction_receipt(
            w3.eth.send_raw_transaction(acct.sign_transaction(tx).raw_transaction))
        assert rcpt.status == 1, ("approve reverted", rcpt)

        # ---- 3. payForQuotes ---------------------------------------------
        import json
        with open(ABI_PATH) as fh:
            vault = w3.eth.contract(address=vault_addr, abi=json.load(fh))
        payments = [(Web3.to_checksum_address(p["rewards_address"]),
                     int(p["amount"]),
                     bytes.fromhex(p["quote_hash"].removeprefix("0x")))
                    for p in prep["payments"]]
        tx = vault.functions.payForQuotes(payments).build_transaction({
            "from": acct.address,
            "nonce": w3.eth.get_transaction_count(acct.address),
            "chainId": w3.eth.chain_id,
        })
        rcpt = w3.eth.wait_for_transaction_receipt(
            w3.eth.send_raw_transaction(acct.sign_transaction(tx).raw_transaction))
        assert rcpt.status == 1, ("payForQuotes reverted", rcpt)
        pay_tx = rcpt.transactionHash.hex()

        # ---- 4. hand tx hashes back to the daemon -----------------------
        tx_hashes = {p["quote_hash"]: pay_tx for p in prep["payments"]}
        fin = requests.post(f"{ANTD}/v1/files/finalize_upload",
                            json={"upload_id": prep["upload_id"],
                                  "tx_hashes": tx_hashes}).json()
        addr = fin["data_map_address"]

        # ---- 5. download to verify ---------------------------------------
        with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as out:
            dst = out.name
        rsp = requests.post(f"{ANTD}/v1/files/download_public",
                            json={"address": addr, "path": dst})
        assert rsp.status_code == 200, rsp.text
        with open(src, "rb") as a, open(dst, "rb") as b:
            assert a.read() == b.read(), "round-trip mismatch"
        print(f"OK  uploaded + downloaded {os.path.getsize(src)} bytes via external signer")
        print(f"    data_map_address = {addr}")
        print(f"    payForQuotes tx  = {pay_tx}")
    finally:
        os.unlink(src)

if __name__ == "__main__":
    main()
```

The single tx hash is reused as the value for every quote_hash key — this is intentional and matches what `evmlib::wallet::pay_for_quotes` returns in the internal-wallet path.

## Merkle path (out of scope)

Triggered automatically when an upload is large enough that wave-batching N chunks at 64-per-wave would cost more in gas than one Merkle-rooted batch. The daemon picks this; SDKs see `payment_type == "merkle_batch"` and a different shape on the response (`depth`, `pool_commitments`, `merkle_payment_timestamp`).

The flow is:
1. Daemon hands SDK a Merkle tree of payment pools.
2. SDK calls `paymentVault.payForMerkleTree(depth, pools, timestamp)` (selector `0x58b630e2`).
3. SDK extracts the `winner_pool_hash` from the return value of that call (or by decoding the log).
4. SDK calls `finalize_upload_merkle(upload_id, winner_pool_hash)` — different endpoint.

Out of scope for the V2-312 examples (small files only). When merkle examples are added (separate ticket), this section becomes the spec.

## References

- Daemon surface: PR [#90](https://github.com/WithAutonomi/ant-sdk/pull/90), squash `a3cf4e40`
- Contract bindings: [`evmlib 0.8.1`](https://crates.io/crates/evmlib/0.8.1) `src/contract/payment_vault/`
- Re-export layer: [`ant-protocol 2.1.0`](https://crates.io/crates/ant-protocol/2.1.0) `src/lib.rs:93` (`pub mod evm`)
- Internal-wallet reference: `evmlib/src/wallet.rs::pay_for_quotes` — the canonical sequencing
- Anvil deterministic accounts: <https://book.getfoundry.sh/anvil/>
- Linear: [V2-311](https://linear.app/autonominetwork/issue/V2-311) (this doc), [V2-312](https://linear.app/autonominetwork/issue/V2-312) (15-SDK fan-out), [V2-295](https://linear.app/autonominetwork/issue/V2-295) (umbrella)
