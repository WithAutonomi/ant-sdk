/**
 * Example 09: Manifests — one `.ant` file and `ant://` link for several files.
 *
 * Stores two small pieces of public data, builds a manifest that names them
 * `notes/one.txt` and `notes/two.txt` under the root `example`, prints its
 * link and entries, then decodes the link and asks the network for each
 * entry's exact size.
 *
 * Prerequisites:
 *   - the antd release after 0.15.0, on a local testnet with a wallet.
 *   - ANTD_BASE_URL (optional): the daemon URL, default http://localhost:8082.
 *     Prefer 127.0.0.1 to localhost on Node 18, which resolves localhost to ::1.
 *
 * The two uploads pay. Building and decoding the manifest upload nothing and
 * pay nothing.
 *
 *   ANTD_BASE_URL=http://127.0.0.1:8082 npx tsx examples/09-manifests.ts
 */

import { createClient } from "../src/index.js";

const client = createClient({ baseUrl: process.env.ANTD_BASE_URL || "http://localhost:8082" });

// Two small pieces of public data for the manifest to describe.
const one = await client.dataPutPublic(Buffer.from("The first note in the manifest."));
const two = await client.dataPutPublic(Buffer.from("The second note, a little longer than the first."));
console.log(`Stored notes/one.txt at: ${one.address}`);
console.log(`Stored notes/two.txt at: ${two.address}`);

// Build the manifest. Nothing is uploaded: the `.ant` bytes come back to us.
const built = await client.buildManifest(
  [
    { path: "notes/one.txt", address: one.address },
    { path: "notes/two.txt", address: two.address },
  ],
  { name: "example" },
);
console.log(`Manifest: ${built.manifest.length} bytes`);
console.log(`Link: ${built.link ?? "(too long for a link; share the .ant bytes)"}`);
for (const entry of built.entries) {
  console.log(`  ${entry.effectiveName} -> ${entry.contentAddress}`);
}

// Decode the link and resolve each entry's DataMap for its exact size.
const decoded = built.link
  ? await client.decodeManifestLink(built.link, true)
  : await client.decodeManifest(built.manifest, true);
console.log(`Decoded "${decoded.name ?? ""}" (${decoded.source}), ${decoded.entries.length} entries:`);
for (const entry of decoded.entries) {
  const size = entry.exactSize === null ? `unknown (${entry.error ?? "not resolved"})` : `${entry.exactSize} bytes`;
  console.log(`  ${entry.effectiveName}: ${size}`);
}

if (decoded.entries.some((e) => e.exactSize === null)) throw new Error("An entry did not resolve!");
console.log("Manifest round-trip OK!");
