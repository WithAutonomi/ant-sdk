/**
 * Example 03: Store and retrieve raw chunks.
 *
 * Chunks are the lowest-level storage primitive on Autonomi.
 */

import { createClient } from "../src/index.js";

const client = createClient();

// Store a raw chunk
const rawData = Buffer.from("Raw chunk content for direct storage");
const result = await client.chunkPut(rawData);
console.log(`Chunk stored at: ${result.address}`);
console.log(`Cost: ${result.cost} atto tokens`);

// Retrieve the chunk
const retrieved = await client.chunkGet(result.address);
console.log(`Retrieved ${retrieved.length} bytes`);

if (!retrieved.equals(rawData)) throw new Error("Chunk round-trip mismatch!");
console.log("Chunk round-trip OK!");
