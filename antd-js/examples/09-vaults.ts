/**
 * Example 09: Vault store and retrieve.
 *
 * Vaults provide private encrypted storage keyed by a secret key.
 * Data is encrypted client-side before being stored on the network.
 */

import { randomBytes } from "node:crypto";
import { createClient } from "../src/index.js";

const client = createClient();

// Generate a random secret key for the vault
const secretKey = randomBytes(32).toString("hex");

// Store data in the vault
const payload = Buffer.from("Secret vault data that is encrypted");
const contentType = 42; // application-defined type
const cost = await client.vaultPut(secretKey, payload, contentType);
console.log(`Vault store cost: ${cost} atto tokens`);

// Retrieve from vault
const vault = await client.vaultGet(secretKey);
console.log(`Content type: ${vault.contentType}`);
console.log(`Data: ${vault.data.toString()}`);

if (!vault.data.equals(payload)) throw new Error("Vault round-trip mismatch!");
if (vault.contentType !== contentType) throw new Error("Content type mismatch!");

console.log("Vault round-trip OK!");
