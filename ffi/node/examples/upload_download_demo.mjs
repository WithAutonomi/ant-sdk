// Live devnet round-trip demo — the Node counterpart of ffi/python's
// examples/upload_download_demo.py. Proves the network path end-to-end:
//   - connect to a local devnet from a manifest
//   - paid public data upload + download, byte-identical round-trip
//   - a paid file upload with live progress callbacks
//
// Prereqs: a running devnet whose manifest path is given as argv[2]
// (defaults to ~/.ant-dev/devnet-manifest.json), e.g.:
//   ant-node/target/release/ant-devnet --preset small --enable-evm \
//     --manifest ~/.ant-dev/devnet-manifest.json
//
// Run: node examples/upload_download_demo.mjs [manifestPath]

import { homedir } from 'node:os'
import { join } from 'node:path'
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { randomBytes } from 'node:crypto'

import { Client, PaymentMode, antFfiVersion } from '../index.js'

const manifest = process.argv[2] ?? join(homedir(), '.ant-dev', 'devnet-manifest.json')

console.log(`ant-ffi ${antFfiVersion()} — connecting to devnet: ${manifest}`)
const client = await Client.connectFromDevnetManifest(manifest)
console.log('connected.\n')

// --- 1) public data round-trip ---
const payload = randomBytes(64 * 1024) // 64 KiB -> multiple chunks
console.log(`uploading ${payload.length} bytes (public, AUTO payment)…`)
const put = await client.dataPutPublic(payload, PaymentMode.Auto)
console.log(`  stored at ${put.address}`)
console.log(`  chunks=${put.chunksStored} paymentMode=${put.paymentModeUsed}`)

const got = await client.dataGetPublic(put.address)
const ok = Buffer.compare(payload, Buffer.from(got)) === 0
console.log(`  download ${got.length} bytes — round-trip ${ok ? 'BYTE-IDENTICAL ✓' : 'MISMATCH ✗'}\n`)
if (!ok) process.exit(1)

// --- 2) file upload with live progress ---
const dir = mkdtempSync(join(tmpdir(), 'antnode-'))
const filePath = join(dir, 'sample.bin')
writeFileSync(filePath, randomBytes(256 * 1024)) // 256 KiB
console.log(`uploading file ${filePath} (public) with progress…`)
const phases = new Set()
let ticks = 0
const fput = await client.fileUploadPublicWithProgress(filePath, PaymentMode.Auto, (p) => {
  ticks++
  phases.add(p.phase)
})
console.log(`  stored at ${fput.address}`)
console.log(`  progress callbacks fired: ${ticks} (phases seen: ${[...phases].join(', ')})`)
console.log(`  storageCostAtto=${fput.storageCostAtto} gasCostWei=${fput.gasCostWei}\n`)

// --- 3) download the file back and verify ---
const outPath = join(dir, 'sample.out')
await client.fileDownloadPublic(fput.address, outPath)
const fileOk =
  Buffer.compare(readFileSync(filePath), readFileSync(outPath)) === 0
console.log(`file round-trip ${fileOk ? 'BYTE-IDENTICAL ✓' : 'MISMATCH ✗'}`)
rmSync(dir, { recursive: true, force: true })

if (!fileOk || ticks === 0) process.exit(1)
console.log('\nAll round-trips passed. ✓')
