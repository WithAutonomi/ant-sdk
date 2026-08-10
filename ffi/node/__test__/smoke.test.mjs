// Offline smoke test — no network, no devnet. Mirrors ffi/python's test_smoke.py
// and ffi/csharp/AntFfi.Tests: import the built addon, check the version string,
// derive an EVM address from a known private key, read a network's config, and
// confirm the exported surface (classes, enums, free fns) is present and shaped.
//
// Requires the addon to be built first: `npm run build:debug` (or `build`).

import assert from 'node:assert/strict'
import { test } from 'node:test'

import * as ant from '../index.js'
import {
  antFfiVersion,
  networkInfo,
  Client,
  Wallet,
  PaymentMode,
  Visibility,
  ProgressPhase,
} from '../index.js'

test('version is x.y.z', () => {
  const v = antFfiVersion()
  assert.equal(typeof v, 'string')
  assert.equal(v.split('.').length, 3, `want semver x.y.z, got ${v}`)
})

test('wallet derives the known address for private key = 1 (offline)', () => {
  // Standard secp256k1 test vector: private key 0x…01 -> this address.
  // Building the wallet is offline; only balance_of_* would hit the RPC.
  const wallet = Wallet.fromPrivateKey(
    '0x0000000000000000000000000000000000000000000000000000000000000001',
    'http://localhost:8545',
    '0x0000000000000000000000000000000000000001',
    '0x0000000000000000000000000000000000000002',
  )
  assert.equal(
    wallet.address().toLowerCase(),
    '0x7e5f4552091a69125d5dfcb7b8c2659029395bdf',
  )
})

test('networkInfo returns Arbitrum One config', () => {
  const info = networkInfo('arbitrum-one')
  assert.equal(info.chainId, 42161)
  assert.match(info.tokenAddress, /^0x[0-9a-fA-F]{40}$/)
  assert.match(info.vaultAddress, /^0x[0-9a-fA-F]{40}$/)
  assert.ok(info.rpcUrl.startsWith('http'))
})

test('networkInfo rejects an unknown network', () => {
  assert.throws(() => networkInfo('nope-net'))
})

test('enums are exported with expected members', () => {
  assert.ok('Auto' in PaymentMode && 'Merkle' in PaymentMode && 'Single' in PaymentMode)
  assert.ok('Public' in Visibility && 'Private' in Visibility)
  for (const p of ['Encrypting', 'Quoting', 'Storing', 'Resolving', 'Downloading']) {
    assert.ok(p in ProgressPhase, `ProgressPhase.${p} missing`)
  }
})

test('Client exposes the expected async surface', () => {
  // Static constructors + a sampling of instance methods exist as functions.
  for (const ctor of [
    'connectLocal',
    'connect',
    'connectDefault',
    'connectDefaultWithWallet',
    'connectDefaultForExternalSigner',
    'connectWithWallet',
    'connectFromDevnetManifest',
    'connectFromDevnetManifestExternalSigner',
    'connectForExternalSigner',
  ]) {
    assert.equal(typeof Client[ctor], 'function', `Client.${ctor} missing`)
  }
  for (const m of [
    'chunkPut',
    'dataPutPublic',
    'dataGetPublic',
    'fileUploadPublicWithProgress',
    'prepareFileUpload',
    'paymentTransactions',
    'finalizeUpload',
    'finalizeUploadMerkle',
    'cancelUpload',
    'downloadPublicToFile',
  ]) {
    assert.equal(typeof Client.prototype[m], 'function', `Client.prototype.${m} missing`)
  }
})

test('external-signer free functions are exported and reject on a dead RPC', async () => {
  assert.equal(typeof ant.waitForReceipt, 'function')
  assert.equal(typeof ant.merkleWinnerPoolHash, 'function')
  // Unroutable RPC -> the underlying reqwest call fails fast; we just assert it
  // rejects rather than resolves (no network assumptions about the message).
  await assert.rejects(
    ant.waitForReceipt('http://127.0.0.1:1', '0x' + '00'.repeat(32), 1),
  )
})
