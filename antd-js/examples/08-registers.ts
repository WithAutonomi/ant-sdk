/**
 * Example 08: Register create, read, and update.
 *
 * Registers store a single 32-byte hex value, owned by a keypair.
 * Updates are paid operations.
 */

import { randomBytes } from "node:crypto";
import { createClient } from "../src/index.js";

const client = createClient();

// Generate a random secret key
const secretKey = randomBytes(32).toString("hex");

// Create a register with an initial value
const initialValue = "00".repeat(32); // 32 zero bytes
const result = await client.registerCreate(secretKey, initialValue);
console.log(`Register created at: ${result.address}`);
console.log(`Cost: ${result.cost} atto tokens`);

// Read the register
let reg = await client.registerGet(result.address);
console.log(`Current value: ${reg.value}`);

// Update the register
const newValue = randomBytes(32).toString("hex");
const updateResult = await client.registerUpdate(secretKey, newValue);
console.log(`Update cost: ${updateResult.cost} atto tokens`);

// Read again to verify
reg = await client.registerGet(result.address);
console.log(`Updated value: ${reg.value}`);

console.log("Register CRUD OK!");
