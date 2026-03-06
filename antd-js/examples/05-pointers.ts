/**
 * Example 05: Create, read, and update mutable pointers.
 *
 * Pointers are mutable references that point to other network objects.
 * They are owned by a keypair and can be updated by the owner.
 */

import { randomBytes } from "node:crypto";
import { createClient, type PointerTarget } from "../src/index.js";

const client = createClient();

// Generate a random secret key (in production, use a proper key)
const secretKey = randomBytes(32).toString("hex");

// Store some data to point to
const dataV1 = await client.dataPutPublic(Buffer.from("version 1"));
const dataV2 = await client.dataPutPublic(Buffer.from("version 2"));

// Create a pointer to v1
const targetV1: PointerTarget = { kind: "chunk", address: dataV1.address };
const ptr = await client.pointerCreate(secretKey, targetV1);
console.log(`Pointer created at: ${ptr.address}`);

// Read the pointer
let pointer = await client.pointerGet(ptr.address);
console.log(`Points to: ${pointer.target.kind} @ ${pointer.target.address}`);
console.log(`Counter: ${pointer.counter}`);

// Check existence
const exists = await client.pointerExists(ptr.address);
console.log(`Pointer exists: ${exists}`);

// Update pointer to point to v2
const targetV2: PointerTarget = { kind: "chunk", address: dataV2.address };
await client.pointerUpdate(secretKey, targetV2);
console.log("Pointer updated to v2");

// Read again to verify
pointer = await client.pointerGet(ptr.address);
console.log(`Now points to: ${pointer.target.address}`);

console.log("Pointer CRUD OK!");
