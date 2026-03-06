/**
 * Example 04: Upload and download files and directories.
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
  const cost = await client.fileCost(srcPath);
  console.log(`File upload cost estimate: ${cost} atto tokens`);

  // Upload file
  const result = await client.fileUploadPublic(srcPath);
  console.log(`File uploaded to: ${result.address}`);
  console.log(`Actual cost: ${result.cost} atto tokens`);

  // Download to new location
  const destPath = srcPath + ".downloaded";
  await client.fileDownloadPublic(result.address, destPath);
  console.log(`Downloaded to: ${destPath}`);

  const content = readFileSync(destPath, "utf-8");
  console.log(`Content: ${content}`);
  unlinkSync(destPath);
} finally {
  unlinkSync(srcPath);
}

console.log("File upload/download OK!");
