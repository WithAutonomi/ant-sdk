import { describe, it, expect } from "vitest";
import { RestClient } from "./rest-client.js";
import { BadRequestError } from "./errors.js";
import type { DecodedManifest, ManifestEntryInput } from "./manifests.js";

// ---------------------------------------------------------------------------
// Live manifest round trip against a running antd with a devnet behind it.
//
// Skipped unless both are set:
//
//   ANTD_TEST_URL                    the daemon's REST base URL, e.g.
//                                    http://127.0.0.1:8082 (use 127.0.0.1,
//                                    not localhost: Node 18 resolves
//                                    localhost to ::1)
//   ANTD_TEST_MANIFEST_ADDRESSES     two comma-separated public data
//                                    addresses already on the network
//
// and then also needs:
//
//   ANTD_TEST_MANIFEST_SIZES         their exact sizes, comma-separated
//   ANTD_TEST_MANIFEST_DATA_MAP      a private upload's hex DataMap
//   ANTD_TEST_MANIFEST_DATA_MAP_SIZE its exact size
//   ANTD_TEST_MANIFEST_LINK          (optional) an ant://manifest/ link built
//                                    from those three; decoded when set
//
// Nothing is uploaded or paid for: building and decoding manifests is free,
// so the daemon needs no wallet.
//
//   ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_MANIFEST_ADDRESSES=<hex>,<hex> \
//     ANTD_TEST_MANIFEST_SIZES=<n>,<n> ANTD_TEST_MANIFEST_DATA_MAP=<hex> \
//     ANTD_TEST_MANIFEST_DATA_MAP_SIZE=<n> npx vitest run src/live-manifests.test.ts
// ---------------------------------------------------------------------------

const list = (v: string | undefined) =>
  (v ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s !== "");

const url = process.env.ANTD_TEST_URL;
const addresses = list(process.env.ANTD_TEST_MANIFEST_ADDRESSES);
const sizes = list(process.env.ANTD_TEST_MANIFEST_SIZES).map(Number);
const dataMap = process.env.ANTD_TEST_MANIFEST_DATA_MAP ?? "";
const dataMapSize = Number(process.env.ANTD_TEST_MANIFEST_DATA_MAP_SIZE ?? "");
const fixtureLink = process.env.ANTD_TEST_MANIFEST_LINK ?? "";
const enabled = url !== undefined && url !== "" && addresses.length === 2;

const PATHS = ["public/one.txt", "public/two.txt", "private/three.txt"];

/** Check a resolving decode of the three entries, whatever their order. */
function expectResolved(decoded: DecodedManifest) {
  expect(decoded.source).toBe("manifest");
  expect(decoded.entries).toHaveLength(3);
  for (const [i, address] of addresses.entries()) {
    const e = decoded.entries.find((x) => x.contentAddress === address);
    expect(e, `entry for ${address}`).toBeDefined();
    expect(e!.kind).toBe("public");
    expect(e!.dataMap).toBeNull();
    expect(e!.error).toBeNull();
    expect(e!.exactSize).toBe(sizes[i]);
  }
  const embedded = decoded.entries.filter((x) => x.kind === "embedded");
  expect(embedded).toHaveLength(1);
  expect(embedded[0].dataMap).toMatch(/^[0-9a-f]+$/);
  expect(embedded[0].exactSize).toBe(dataMapSize);
  expect(embedded[0].error).toBeNull();
}

describe.skipIf(!enabled)("live: manifest build and decode", () => {
  const client = new RestClient({ baseUrl: url, timeout: 120_000 });

  it("has the whole fixture set", () => {
    expect(sizes, "ANTD_TEST_MANIFEST_SIZES").toHaveLength(2);
    expect(sizes.every(Number.isSafeInteger)).toBe(true);
    expect(dataMap, "ANTD_TEST_MANIFEST_DATA_MAP").not.toBe("");
    expect(Number.isSafeInteger(dataMapSize), "ANTD_TEST_MANIFEST_DATA_MAP_SIZE").toBe(true);
  });

  it(
    "builds from two addresses and a DataMap, then decodes the bytes and the link",
    async () => {
      const entries: ManifestEntryInput[] = [
        { path: PATHS[0], address: addresses[0] },
        { path: PATHS[1], address: addresses[1] },
        { path: PATHS[2], dataMap },
      ];
      const built = await client.buildManifest(entries, { name: "antd-js-live" });

      // The `.ant` header, as raw bytes.
      expect(Buffer.isBuffer(built.manifest)).toBe(true);
      expect([...built.manifest.subarray(0, 4)]).toEqual([0xc1, 0x41, 0x4e, 0x54]);
      expect(built.link).toMatch(/^ant:\/\/manifest\//);

      // Sorted by effective name, which is the path.
      expect(built.entries.map((e) => e.effectiveName)).toEqual([...PATHS].sort());
      const byPath = new Map(built.entries.map((e) => [e.path, e]));
      for (const [i, address] of addresses.entries()) {
        const e = byPath.get(PATHS[i])!;
        expect(e.kind).toBe("public");
        expect(e.contentAddress).toBe(address);
        // No size was given and a build does not resolve: unset, not 0.
        expect(e.size).toBeNull();
        expect(e.exactSize).toBeNull();
        expect(e.dataMap).toBeNull();
      }
      const priv = byPath.get(PATHS[2])!;
      expect(priv.kind).toBe("embedded");
      expect(priv.size).toBeNull();
      // An embedded root DataMap carries its exact size.
      expect(priv.exactSize).toBe(dataMapSize);

      const fromBytes = await client.decodeManifest(built.manifest, true);
      expectResolved(fromBytes);
      expect(fromBytes.name).toBe("antd-js-live");
      const fromLink = await client.decodeManifestLink(built.link!, true);
      expect(fromLink).toEqual(fromBytes);

      // The embedded DataMap is in the hex form the download methods take.
      const embedded = fromBytes.entries.find((e) => e.kind === "embedded")!;
      const content = await client.dataGet(embedded.dataMap!);
      expect(content.length).toBe(dataMapSize);

      // Without resolve, the public entries' sizes stay unknown.
      const unresolved = await client.decodeManifest(built.manifest);
      expect(unresolved.entries.filter((e) => e.kind === "public").map((e) => e.exactSize)).toEqual([
        null,
        null,
      ]);
    },
    300_000,
  );

  it.skipIf(fixtureLink === "")(
    "decodes the fixture link, and rebuilding it gives the same link",
    async () => {
      const decoded = await client.decodeManifestLink(fixtureLink, true);
      expectResolved(decoded);

      const rebuilt = await client.buildManifest(
        decoded.entries.map((e) => ({
          path: e.path ?? undefined,
          size: e.size,
          ...(e.kind === "embedded" ? { dataMap: e.dataMap! } : { address: e.contentAddress }),
        })),
        { name: decoded.name ?? undefined },
      );
      expect(rebuilt.link).toBe(fixtureLink);
    },
    300_000,
  );

  it("rejects bad entries as BadRequestError", async () => {
    // Both sources: refused before anything is sent.
    const both = await client
      .buildManifest([{ path: "x.txt", dataMap, address: addresses[0] }])
      .catch((e: unknown) => e);
    expect(both).toBeInstanceOf(BadRequestError);
    expect((both as BadRequestError).statusCode).toBe(400);
    expect((both as Error).message).toBe(
      "1 invalid entries: entries[0]: give data_map or address, not both",
    );

    // The same mistake sent past the client check: the daemon's 400 must
    // read exactly the same (it adds only its "Bad request: " prefix).
    const raw = await fetch(`${url}/v1/manifests/build`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ entries: [{ path: "x.txt", data_map: dataMap, address: addresses[0] }] }),
    });
    expect(raw.status).toBe(400);
    const daemonMsg = ((await raw.json()) as { error: string }).error;
    expect(daemonMsg).toBe(`Bad request: ${(both as Error).message}`);

    // Two bad entries at once, and neither source.
    const two = await client
      .buildManifest([{ path: "a" }, { address: addresses[0] }, { dataMap, address: addresses[1] }])
      .catch((e: unknown) => e);
    expect((two as Error).message).toBe(
      "2 invalid entries: entries[0]: needs a data_map or an address; " +
        "entries[2]: give data_map or address, not both",
    );

    // Empty decode input.
    const empty = await client.decodeManifestLink("").catch((e: unknown) => e);
    expect(empty).toBeInstanceOf(BadRequestError);
    expect((empty as Error).message).toBe("needs a manifest (base64 .ant bytes) or a link");

    // A path that escapes its root: the daemon's 400, naming the entry.
    const escape = await client
      .buildManifest([
        { path: "ok.txt", address: addresses[0] },
        { path: "../x", address: addresses[1] },
      ])
      .catch((e: unknown) => e);
    expect(escape).toBeInstanceOf(BadRequestError);
    expect((escape as BadRequestError).statusCode).toBe(400);
    expect((escape as Error).message).toContain("entries[1]");
    expect((escape as Error).message).not.toContain("entries[0]");

    // Bytes that are not a manifest.
    const junk = await client.decodeManifest(Buffer.from("not a manifest")).catch((e: unknown) => e);
    expect(junk).toBeInstanceOf(BadRequestError);
  });
});
