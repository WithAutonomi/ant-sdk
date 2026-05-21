/**
 * Example 02: Store and retrieve public data, with cost estimation.
 *
 * Prerequisite: antd daemon running on local testnet.
 */

import { createClient } from "../src/index.js";

const client = createClient();

// Estimate cost before storing
const payload = Buffer.from("Hello, Autonomi network!");
const est = await client.dataCost(payload);
console.log(
  `Estimate: ${est.fileSize} bytes in ${est.chunkCount} chunks, ` +
    `storage ${est.cost} atto, gas ${est.estimatedGasCostWei} wei, ` +
    `mode ${est.paymentMode}`
);

// Store public data
const result = await client.dataPutPublic(payload);
console.log(`Stored at address: ${result.address}`);
console.log(`Chunks stored: ${result.chunksStored}, payment mode: ${result.paymentModeUsed}`);

// Retrieve it back
const data = await client.dataGetPublic(result.address);
console.log(`Retrieved: ${data.toString()}`);

if (!data.equals(payload)) throw new Error("Round-trip mismatch!");
console.log("Public data round-trip OK!");
