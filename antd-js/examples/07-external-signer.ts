/**
 * Example 07: External-signer flow — public file + single-chunk publish.
 *
 * PR #90 added `prepareUploadPublic` / `finalizeUpload` and
 * `prepareChunkUpload` / `finalizeChunkUpload` so the wallet key never has
 * to live in the antd daemon. This example uses anvil deterministic
 * account #0 as the external signer and exercises both round-trips.
 *
 * See `docs/external-signer-flow.md` for the full reference; the contract
 * ABI loaded below is committed at `docs/abi/IPaymentVault.json`.
 *
 * Requires `ethers` (added as a devDependency of antd-js).
 */

import { readFileSync, unlinkSync, mkdtempSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

import {
  Contract,
  JsonRpcProvider,
  Wallet,
  NonceManager,
  MaxUint256,
  getAddress,
} from "ethers";

import { createClient } from "../src/index.js";

// Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
// (storage payment) by `ant dev start --enable-evm` devnet genesis. Never
// use this key anywhere except a throw-away local devnet.
const ANVIL_KEY =
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

// Minimal ERC-20 ABI for approve(). antToken is a standard ERC-20.
const ERC20_ABI = [
  "function approve(address spender, uint256 value) returns (bool)",
];

// Repo-bundled IPaymentVault ABI (see docs/external-signer-flow.md).
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const ABI_PATH = resolve(__dirname, "..", "..", "docs", "abi", "IPaymentVault.json");
const VAULT_ABI = JSON.parse(readFileSync(ABI_PATH, "utf-8"));

type Payment = { quoteHash: string; rewardsAddress: string; amount: string };
type Prep = {
  uploadId: string;
  payments: Payment[];
  rpcUrl: string;
  paymentVaultAddress: string;
  paymentTokenAddress: string;
};

/**
 * Run approve + payForQuotes on-chain for a daemon prepare response and
 * return the `quoteHash -> txHash` map the daemon's finalize_* methods
 * expect. Every entry maps to the same `payForQuotes` tx because every
 * quote in the wave is paid in one batched call.
 */
async function externalSignerPay(
  prep: Prep,
  wallet: NonceManager,
): Promise<Record<string, string>> {
  // No on-chain work needed when every quoted chunk is already on-network
  // (the daemon's prepare step elides zero-amount payments). Finalize accepts
  // an empty tx_hashes map in this case.
  if (prep.payments.length === 0) {
    return {};
  }

  const vaultAddr = getAddress(prep.paymentVaultAddress);
  const tokenAddr = getAddress(prep.paymentTokenAddress);

  // approve(vault, MAX) — idempotent and cheap; example uses MAX so
  // subsequent flows in this run skip a fresh approval.
  //
  // NonceManager handles nonce tracking locally so we don't race against
  // provider.getTransactionCount lag across back-to-back txs.
  const token = new Contract(tokenAddr, ERC20_ABI, wallet);
  const approveTx = await token.approve(vaultAddr, MaxUint256);
  const approveRcpt = await approveTx.wait();
  if (!approveRcpt || approveRcpt.status !== 1) {
    throw new Error(`approve reverted: ${JSON.stringify(approveRcpt)}`);
  }

  // payForQuotes — one tx covering every quote in this wave.
  const vault = new Contract(vaultAddr, VAULT_ABI, wallet);
  const payments = prep.payments.map((p) => ({
    rewardsAddress: getAddress(p.rewardsAddress),
    amount: BigInt(p.amount),
    quoteHash: p.quoteHash.startsWith("0x") ? p.quoteHash : `0x${p.quoteHash}`,
  }));
  const payTx = await vault.payForQuotes(payments);
  const payRcpt = await payTx.wait();
  if (!payRcpt || payRcpt.status !== 1) {
    throw new Error(`payForQuotes reverted: ${JSON.stringify(payRcpt)}`);
  }

  // Every quote in this wave was paid in the same call.
  const txHashes: Record<string, string> = {};
  for (const p of prep.payments) {
    txHashes[p.quoteHash] = payRcpt.hash;
  }
  return txHashes;
}

const client = createClient();

// --- 1. file upload via external signer -----------------------------------
const dir = mkdtempSync(join(tmpdir(), "antd-extsig-"));
const srcPath = join(dir, "07_external_signer.bin");
writeFileSync(srcPath, "hello external signer from js (file)\n".repeat(16)); // ~600 bytes
try {
  const filePrep = await client.prepareUploadPublic(srcPath);
  console.log(
    `File prepare: uploadId=${filePrep.uploadId.slice(0, 16)}..., ` +
      `paymentType=${filePrep.paymentType}, ` +
      `payments=${filePrep.payments.length}, totalAmount=${filePrep.totalAmount}`,
  );

  // Build the ethers provider+wallet from the daemon-provided rpc_url.
  // NonceManager handles nonce tracking locally so back-to-back txs don't
  // race against provider.getTransactionCount lag.
  const provider = new JsonRpcProvider(filePrep.rpcUrl);
  const wallet = new NonceManager(new Wallet(ANVIL_KEY, provider));

  const fileTxHashes = await externalSignerPay(filePrep, wallet);
  const fileFin = await client.finalizeUpload(filePrep.uploadId, fileTxHashes);
  console.log(
    `File finalize: dataMapAddress=${fileFin.dataMapAddress}, ` +
      `chunksStored=${fileFin.chunksStored}`,
  );

  const dstPath = srcPath + ".downloaded";
  await client.fileDownloadPublic(fileFin.dataMapAddress, dstPath);
  const original = readFileSync(srcPath);
  const downloaded = readFileSync(dstPath);
  if (!original.equals(downloaded)) {
    throw new Error("file round-trip mismatch");
  }
  unlinkSync(dstPath);
  console.log("File round-trip OK!");

  // --- 2. single-chunk publish via external signer ----------------------
  const chunkData = Buffer.from("hello external signer from js (chunk)\n".repeat(8));
  const chunkPrep = await client.prepareChunkUpload(chunkData);
  if (chunkPrep.alreadyStored) {
    console.log(`Chunk prepare: alreadyStored, address=${chunkPrep.address}`);
  } else {
    console.log(
      `Chunk prepare: uploadId=${chunkPrep.uploadId.slice(0, 16)}..., ` +
        `address=${chunkPrep.address}, payments=${chunkPrep.payments.length}, ` +
        `totalAmount=${chunkPrep.totalAmount}`,
    );
    const chunkPrepAsPrep: Prep = {
      uploadId: chunkPrep.uploadId,
      payments: chunkPrep.payments,
      rpcUrl: chunkPrep.rpcUrl,
      paymentVaultAddress: chunkPrep.paymentVaultAddress,
      paymentTokenAddress: chunkPrep.paymentTokenAddress,
    };
    const chunkTxHashes = await externalSignerPay(chunkPrepAsPrep, wallet);
    const addr = await client.finalizeChunkUpload(chunkPrep.uploadId, chunkTxHashes);
    if (addr !== chunkPrep.address) {
      throw new Error(`chunk address mismatch: ${addr} != ${chunkPrep.address}`);
    }
    console.log(`Chunk finalize: address=${addr}`);
  }

  const got = await client.chunkGet(chunkPrep.address);
  if (!Buffer.from(got).equals(chunkData)) {
    throw new Error("chunk round-trip mismatch");
  }
  console.log("Chunk round-trip OK!");
} finally {
  unlinkSync(srcPath);
}

console.log("\n07-external-signer OK!");
