/**
 * Example 06: Private (encrypted) data round-trip.
 *
 * Private data is encrypted before storage. The returned DataMap is
 * required to retrieve and decrypt the data and is NOT stored on-network.
 */

import { createClient } from "../src/index.js";

const client = createClient();

// Store private data
const secretMessage = Buffer.from("This message is encrypted on the network");
const result = await client.dataPut(secretMessage);
console.log(`Data map: ${result.dataMap}`);
console.log(`Chunks stored: ${result.chunksStored}, payment mode: ${result.paymentModeUsed}`);

// Retrieve and decrypt using the caller-held DataMap
const retrieved = await client.dataGet(result.dataMap);
console.log(`Decrypted: ${retrieved.toString()}`);

if (!retrieved.equals(secretMessage)) throw new Error("Private data round-trip mismatch!");
console.log("Private data round-trip OK!");
