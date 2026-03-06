/**
 * Example 07: Graph entry (DAG node) operations.
 *
 * Graph entries form a directed acyclic graph (DAG) on the network.
 * Each entry has an owner, content, parent links, and descendant links.
 */

import { randomBytes } from "node:crypto";
import { createClient } from "../src/index.js";

const client = createClient();

// Generate a random secret key
const secretKey = randomBytes(32).toString("hex");

// Create a root graph entry (no parents)
const content = randomBytes(32).toString("hex"); // 32 bytes of content
const result = await client.graphEntryPut(secretKey, [], content, []);
console.log(`Graph entry created at: ${result.address}`);
console.log(`Cost: ${result.cost} atto tokens`);

// Read the graph entry
const entry = await client.graphEntryGet(result.address);
console.log(`Owner: ${entry.owner}`);
console.log(`Content: ${entry.content}`);
console.log(`Parents: ${JSON.stringify(entry.parents)}`);
console.log(`Descendants: ${entry.descendants.length}`);

// Check existence
const exists = await client.graphEntryExists(result.address);
console.log(`Graph entry exists: ${exists}`);

// Estimate cost for another entry
const cost = await client.graphEntryCost(secretKey);
console.log(`Cost estimate for new entry: ${cost} atto tokens`);

console.log("Graph entry operations OK!");
