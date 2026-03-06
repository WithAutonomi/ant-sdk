/**
 * Example 06: Create, read, and update versioned scratchpads.
 *
 * Scratchpads are versioned mutable storage with a content type field.
 * They are owned by a keypair and have a monotonic counter.
 */

import { randomBytes } from "node:crypto";
import { createClient } from "../src/index.js";

const client = createClient();

// Generate a random secret key
const secretKey = randomBytes(32).toString("hex");

// Create a scratchpad with initial data
const initialData = Buffer.from("scratchpad v1 data");
const contentType = 1; // application-defined encoding
const result = await client.scratchpadCreate(secretKey, contentType, initialData);
console.log(`Scratchpad created at: ${result.address}`);
console.log(`Cost: ${result.cost} atto tokens`);

// Read the scratchpad
let pad = await client.scratchpadGet(result.address);
console.log(`Data encoding: ${pad.dataEncoding}`);
console.log(`Counter: ${pad.counter}`);
console.log(`Data length: ${pad.data.length} bytes`);

// Check existence
const exists = await client.scratchpadExists(result.address);
console.log(`Scratchpad exists: ${exists}`);

// Update scratchpad with new data
const updatedData = Buffer.from("scratchpad v2 data");
await client.scratchpadUpdate(secretKey, contentType, updatedData);
console.log("Scratchpad updated");

// Read again to verify
pad = await client.scratchpadGet(result.address);
console.log(`Counter after update: ${pad.counter}`);

console.log("Scratchpad CRUD OK!");
