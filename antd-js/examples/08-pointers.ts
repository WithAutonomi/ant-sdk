/**
 * Example 08: Pointers — a mutable reference to public data.
 *
 * Stores two small pieces of public data, creates a pointer at the first,
 * updates it to the second, reads it back, and prints where the close group
 * says it stands.
 *
 * Prerequisites:
 *   - antd >= 0.16.0 on a local testnet with a wallet, started with
 *     `--pointer-keys <file-or-dir>` (key files from `ant pointer keygen`).
 *   - ANTD_POINTER_OWNER: the address of a pointer the daemon holds the key
 *     for (`client.pointerKeys()` lists them). The first run creates it; later
 *     runs update it.
 *   - ANTD_BASE_URL (optional): the daemon URL, default http://localhost:8082.
 *     Prefer 127.0.0.1 to localhost on Node 18, which resolves localhost to ::1.
 *
 * Every pointer write pays, about the price of one chunk, and every attempt
 * pays again, so nothing here retries a write.
 *
 *   ANTD_POINTER_OWNER=<hex> npx tsx examples/08-pointers.ts
 */

import { createClient, NotFoundError } from "../src/index.js";

const owner = process.env.ANTD_POINTER_OWNER;
if (!owner) {
  console.log("ERROR: set ANTD_POINTER_OWNER to a pointer address the daemon holds a key for");
  process.exit(1);
}

const client = createClient({ baseUrl: process.env.ANTD_BASE_URL || undefined });

// Two small pieces of public data for the pointer to point at.
const first = await client.dataPutPublic(Buffer.from("Pointer target, version 1"));
const second = await client.dataPutPublic(Buffer.from("Pointer target, version 2"));
console.log(`Stored first target at:  ${first.address}`);
console.log(`Stored second target at: ${second.address}`);

// Create the pointer at the first target. If an earlier run created it,
// pointerUpdate below moves it on anyway (and would create it if missing).
let exists = true;
try {
  await client.pointerGet(owner);
} catch (err) {
  if (!(err instanceof NotFoundError)) throw err;
  exists = false;
}
if (exists) {
  console.log(`Pointer ${owner} already exists; skipping create`);
} else {
  const created = await client.pointerCreate(owner, first.address);
  console.log(`Created pointer ${created.address} (counter ${created.counter})`);
}

// Point it at the second target. The address stays the same.
const updated = await client.pointerUpdate(owner, second.address);
console.log(`Updated pointer ${updated.address} (counter ${updated.counter})`);

// Read it back: the stored record, and where the chain ends.
const record = await client.pointerGet(owner);
console.log(
  `Pointer record: counter ${record.counter}, ${record.kind} target ${record.target}, ` +
    `final ${record.isFinal}`,
);
const resolved = await client.pointerResolve(owner);
const data = await client.dataGetPublic(resolved.target);
console.log(`Resolves to ${resolved.target}: "${data.toString()}"`);
if (resolved.target !== second.address) throw new Error("Pointer did not resolve to the second target!");

// Ask the whole close group where the pointer stands.
const finality = await client.pointerFinality(owner);
console.log(
  `Finality: ${finality.status} (${finality.answered}/${finality.group} answered, ` +
    `counter ${finality.counter ?? "none"})`,
);

console.log("Pointer round-trip OK!");
