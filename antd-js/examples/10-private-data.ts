/**
 * Example 10: Private (encrypted) data round-trip.
 *
 * Private data is encrypted before storage. The returned data map
 * is required to retrieve and decrypt the data.
 */

import { createClient } from "../src/index.js";

const client = createClient();

// Store private data
const secretMessage = Buffer.from("This message is encrypted on the network");
const result = await client.dataPutPrivate(secretMessage);
const dataMap = result.address; // for private data, address holds the data map
console.log(`Data map: ${dataMap}`);
console.log(`Cost: ${result.cost} atto tokens`);

// Retrieve and decrypt
const retrieved = await client.dataGetPrivate(dataMap);
console.log(`Decrypted: ${retrieved.toString()}`);

if (!retrieved.equals(secretMessage)) throw new Error("Private data round-trip mismatch!");
console.log("Private data round-trip OK!");
