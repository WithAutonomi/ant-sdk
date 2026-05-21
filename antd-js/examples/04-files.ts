/**
 * Example 04: Upload and download files publicly.
 *
 * Creates a temp file, uploads it, then downloads to a new location.
 */

import { writeFileSync, readFileSync, unlinkSync, mkdtempSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createClient } from "../src/index.js";

const client = createClient();

// Create a temporary file to upload
const dir = mkdtempSync(join(tmpdir(), "antd-"));
const srcPath = join(dir, "test.txt");
writeFileSync(srcPath, "Hello from a file on Autonomi!");

try {
  // Estimate cost
  const est = await client.fileCost(srcPath);
  console.log(
    `Estimate: ${est.fileSize} bytes in ${est.chunkCount} chunks, ` +
      `storage ${est.cost} atto, gas ${est.estimatedGasCostWei} wei, ` +
      `mode ${est.paymentMode}`
  );

  // Upload file publicly
  const result = await client.filePutPublic(srcPath);
  console.log(`File uploaded to: ${result.address}`);
  console.log(`Storage cost: ${result.storageCostAtto} atto, gas: ${result.gasCostWei} wei`);
  console.log(`Chunks stored: ${result.chunksStored}, payment mode: ${result.paymentModeUsed}`);

  // Download to new location
  const destPath = srcPath + ".downloaded";
  await client.fileGetPublic(result.address, destPath);
  console.log(`Downloaded to: ${destPath}`);

  const content = readFileSync(destPath, "utf-8");
  console.log(`Content: ${content}`);
  unlinkSync(destPath);
} finally {
  unlinkSync(srcPath);
}

console.log("File upload/download OK!");
