# External-signer paid uploads (mobile: iOS & Android)

How to pay for an upload with the **user's own wallet** — a WalletConnect /
external signer whose private key never enters the process — using the
`ant-swift` / `ant-android` mobile SDK.

> **This is the mobile (in-process FFI) flow.** If you are building against the
> **antd daemon over REST/gRPC**, see
> [`external-signer-flow.md`](./external-signer-flow.md) instead — that document
> describes HTTP endpoints (`POST /v1/upload/prepare`, …) and does **not** apply
> to the mobile SDK. On mobile, all ABI encoding, receipt polling, and the
> merkle-winner lookup are done **for you** by the SDK — you never hand-roll
> calldata.

The complete, runnable reference for everything below is
[`ant-mobile-ios`](https://github.com/WithAutonomi/ant-mobile-ios) /
[`ant-mobile-android`](https://github.com/WithAutonomi/ant-mobile-android)
(WalletConnect wiring, confirm sheet, both payment paths, live progress). The
Swift and Kotlin APIs are identical in shape — method and field names are the
same camelCase on both platforms.

---

## When to use it

Use the external signer whenever the wallet key cannot live in the process:
mobile apps, hardware/browser wallets, anything with a custody boundary. If your
app *does* hold the key, `connectWithWallet(...)` + `fileUploadPublic(path)` is
the shorter path and none of this applies.

## The shape of the flow

```
prepareFileUpload(path, visibility)         ── Phase 1: encrypt + quote (SDK)
        │  → PreparedUploadInfo { uploadId, paymentType, alreadyStored, … }
        ▼
paymentTransactions(uploadId)               ── Phase 1.5: SDK builds the txs
        │  → [TxRequest]  (approve, then pay — calldata already ABI-encoded)
        ▼
for each TxRequest:  sign & send  ─→  waitForReceipt(rpcUrl, txHash, timeout)
        │            (external wallet)        (SDK polls the receipt)
        ▼
finalizeUpload(uploadId, txHashes)          ── Phase 2: store chunks (SDK)
   or   finalizeUploadMerkle(uploadId, winnerPoolHash)
        │  → ExternalUploadResult { address, dataMap, chunksStored, … }
        ▼
      done
```

You drive the loop; the SDK owns every piece that touches the ABI or the chain.

## Step 1 — connect (no key on device)

`connectForExternalSigner` collects quotes and prices (which need the network)
but signs nothing itself:

```swift
// Swift
let client = try await Client.connectForExternalSigner(
    peers: bootstrapPeers,                 // e.g. from your network config
    rpcUrl: net.rpcUrl,
    paymentTokenAddress: net.tokenAddress,
    paymentVaultAddress: net.vaultAddress
)
```

Don't hardcode the chain addresses — ask the SDK:

```swift
let net = try networkInfo(name: "arbitrum-one")   // or "arbitrum-sepolia-test"
// net.chainId, net.tokenAddress, net.vaultAddress, net.rpcUrl
```

For a **LAN/Sepolia devnet**, use
`connectFromDevnetManifestExternalSigner(manifestPath)` instead — it reads the
peers, RPC, token and vault from the devnet manifest.

## Step 2 — prepare (encrypt + quote)

```swift
let info = try await client.prepareFileUpload(
    path: path,
    visibility: "public"        // or "private"
)
// info.uploadId          — opaque handle, pass to finalize
// info.paymentType       — "wave_batch" | "merkle"  (routes finalize)
// info.alreadyStored     — nothing to pay if true
// info.totalAmount       — wave: total atto-ANT owed ("0" for merkle)
// info.dataMapAddress    — public retrieval address (nil for private)
```

Use `prepareFileUploadWithProgress(path:visibility:listener:)` if you want the
`"encrypting"` / `"quoting"` phases surfaced for a large file.

**Already stored?** If `info.alreadyStored` is `true` there's nothing to pay —
skip straight to finalize (still routed by `paymentType`):

```swift
if info.alreadyStored {
    let r = info.paymentType == "merkle"
        ? try await client.finalizeUploadMerkle(uploadId: info.uploadId,
                                                winnerPoolHash: anyValidHash)
        : try await client.finalizeUpload(uploadId: info.uploadId, txHashes: [:])
    return
}
```

## Step 3 — build the transactions

The SDK returns the exact ordered transactions to sign — an ERC-20 `approve`
followed by the vault payment call(s), already ABI-encoded (wave batching and
the merkle approve upper-bound handled internally):

```swift
let txs = try await client.paymentTransactions(uploadId: info.uploadId)
// each TxRequest: { to, data, kind: "approve"|"pay", quoteHashes: [String] }
```

## Step 4 — sign each, wait for its receipt, collect the map

Sign every `TxRequest` **in order** with the user's wallet, waiting for each
receipt before the next. Build the `quoteHash → txHash` map from the wave `pay`
tx; capture the pay tx + vault for merkle.

```swift
var txHashes: [String: String] = [:]   // wave finalize map
var merklePayTx: String?
var merkleVault: String?

for tx in txs {
    let hash = try await signer(tx.to, tx.data, net.chainId)      // your wallet
    let receipt = try await waitForReceipt(rpcUrl: net.rpcUrl,
                                           txHash: hash, timeoutSecs: 60)
    guard receipt.success else { throw MyError.reverted }

    if tx.kind == "pay" {
        for qh in tx.quoteHashes { txHashes[qh] = hash }         // wave
        if info.paymentType == "merkle" { merklePayTx = hash; merkleVault = tx.to }
    }
}
```

## Step 5 — finalize (store the chunks), routed by payment shape

**Wave batch** — hand back the `quoteHash → txHash` map:

```swift
let r = try await client.finalizeUploadWithProgress(
    uploadId: info.uploadId, txHashes: txHashes, listener: progress)
```

**Merkle** — the winning pool is chosen on-chain; let the SDK read it from the
`payForMerkleTree` receipt's `MerklePaymentMade` event, then finalize:

```swift
let winner = try await merkleWinnerPoolHash(
    rpcUrl: net.rpcUrl, vaultAddress: merkleVault!, txHash: merklePayTx!)
let r = try await client.finalizeUploadMerkleWithProgress(
    uploadId: info.uploadId, winnerPoolHash: winner, listener: progress)
```

`ExternalUploadResult` gives you `address` (public, shareable), `dataMap` (hex,
for private retrieval), `chunksStored`, `storageCostAtto`, `gasCostWei`.

> **Wave vs merkle.** `paymentMode: "auto"` (the default) picks the shape for
> you: single-chunk / small uploads settle as **wave** (`payForQuotes`); large
> multi-chunk uploads use **merkle** (`payForMerkleTree`). Your code must handle
> both — route finalize on `info.paymentType`. Calling the wrong finalize is
> rejected **without** consuming the prepared upload, so it's a safe programming
> error, not a lost payment.

---

## Kotlin

Same methods, same order — `import uniffi.ant_ffi.*` and note that
`waitForReceipt` / `merkleWinnerPoolHash` / `networkInfo` are **free functions**,
only `paymentTransactions` / `prepare*` / `finalize*` are `Client` methods:

```kotlin
val client = Client.connectForExternalSigner(
    peers, net.rpcUrl, net.tokenAddress, net.vaultAddress)

val info = client.prepareFileUpload(path, "public")
if (info.alreadyStored) { /* finalize with empty map / any winner hash */ }

val txs = client.paymentTransactions(info.uploadId)

val txHashes = HashMap<String, String>()
var merklePayTx: String? = null; var merkleVault: String? = null
for (tx in txs) {
    val hash = signer(tx.to, tx.data, net.chainId)               // your wallet
    val receipt = waitForReceipt(net.rpcUrl, hash, 60u)
    require(receipt.success)
    if (tx.kind == "pay") {
        tx.quoteHashes.forEach { txHashes[it] = hash }
        if (info.paymentType == "merkle") { merklePayTx = hash; merkleVault = tx.to }
    }
}

val result = if (info.paymentType == "merkle") {
    val winner = merkleWinnerPoolHash(net.rpcUrl, merkleVault!!, merklePayTx!!)
    client.finalizeUploadMerkleWithProgress(info.uploadId, winner, progress)
} else {
    client.finalizeUploadWithProgress(info.uploadId, txHashes, progress)
}
```

---

## ⚠️ Retry / failure contract (read before shipping)

- **Bad input** to finalize (a malformed `quoteHash`/`txHash`) is validated
  *before* any state changes — it errors with the upload left intact, so you can
  fix the map and call finalize again.
- **A storage/network failure *after* payment is currently NOT retryable.**
  ant-core consumes the prepared upload and the paid proofs by value, so a
  post-payment finalize failure strands the payment: a fresh `prepare*` collects
  new quotes with different quote hashes that won't match the already-paid tx
  map. **Do not tell the user the payment can simply be reused.** Surface it as a
  paid-but-not-stored state and escalate. Tracked in
  [ant-client#140](https://github.com/WithAutonomi/ant-client/issues/140) /
  ant-sdk#201.

## Errors

Client calls throw `ClientError` — switch on it: `NotFound` (address not on the
network), `NetworkError` (transient, safe to retry), `PaymentError`,
`WalletNotConfigured` (you called `paymentTransactions` on a non-external-signer
client), `InvalidInput`. Each carries a `reason` string.
