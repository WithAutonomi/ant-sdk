import { describe, it, expect } from "vitest";
import { createHash } from "node:crypto";
import { RestClient } from "./rest-client.js";
import { BadRequestError } from "./errors.js";

// ---------------------------------------------------------------------------
// Live sha256 checks against antd 0.17.0 or later with a devnet behind it.
//
// Skipped unless both are set:
//
//   ANTD_TEST_URL      the daemon's REST base URL (use 127.0.0.1, not
//                      localhost: Node 18 resolves localhost to ::1)
//   ANTD_TEST_SHA_LINK an ant://manifest/ link with entries public.txt,
//                      private.txt (both with a sha256) and nohash.txt (none)
//
// and then needs:
//
//   ANTD_TEST_SHA_PUBLIC_ADDRESS     a public data upload's address
//   ANTD_TEST_SHA_PUBLIC_SHA256      its plaintext SHA-256 (hex)
//   ANTD_TEST_SHA_DATA_MAP_SHA256    a private upload's plaintext SHA-256
//
// The manifest checks are free. The last test makes ONE paid public data
// upload, so the daemon needs a funded wallet.
//
//   ANTD_TEST_URL=http://127.0.0.1:18084 ANTD_TEST_SHA_LINK=<link> ... \
//     npx vitest run src/live-sha256.test.ts
// ---------------------------------------------------------------------------

const url = process.env.ANTD_TEST_URL;
const link = process.env.ANTD_TEST_SHA_LINK ?? "";
const publicAddress = process.env.ANTD_TEST_SHA_PUBLIC_ADDRESS ?? "";
const publicSha = process.env.ANTD_TEST_SHA_PUBLIC_SHA256 ?? "";
const dataMapSha = process.env.ANTD_TEST_SHA_DATA_MAP_SHA256 ?? "";
const enabled = url !== undefined && url !== "" && link !== "";

describe.skipIf(!enabled)("live: sha256", () => {
  const client = new RestClient({ baseUrl: url, timeout: 120_000 });

  it("has the whole fixture set", () => {
    expect(publicAddress, "ANTD_TEST_SHA_PUBLIC_ADDRESS").not.toBe("");
    expect(publicSha, "ANTD_TEST_SHA_PUBLIC_SHA256").not.toBe("");
    expect(dataMapSha, "ANTD_TEST_SHA_DATA_MAP_SHA256").not.toBe("");
  });

  it("decodes the fixture link with sha256 on two entries and none on the third", async () => {
    const decoded = await client.decodeManifestLink(link, false);
    const byPath = new Map(decoded.entries.map((e) => [e.path, e]));
    expect(byPath.get("public.txt")!.sha256).toBe(publicSha);
    expect(byPath.get("private.txt")!.sha256).toBe(dataMapSha);
    expect(byPath.get("nohash.txt")!.sha256).toBeNull();
  });

  it("builds an entry that carries the sha256 it was given", async () => {
    const built = await client.buildManifest([
      { path: "a.txt", address: publicAddress, sha256: publicSha },
    ]);
    expect(built.entries).toHaveLength(1);
    expect(built.entries[0].sha256).toBe(publicSha);
  });

  it("refuses a malformed sha256 as BadRequestError with the daemon's message", async () => {
    const err = await client
      .buildManifest([{ path: "a.txt", address: publicAddress, sha256: "zz" }])
      .catch((e: unknown) => e);
    expect(err).toBeInstanceOf(BadRequestError);
    expect((err as BadRequestError).statusCode).toBe(400);
    expect((err as Error).message).toContain("entries[0]");
    expect((err as Error).message).toContain("sha256");
  });

  it(
    "returns the plaintext's SHA-256 from a public data upload (one paid call)",
    async () => {
      const payload = Buffer.from(`sha-fanout js ${Math.floor(Date.now() / 1000)}`, "utf8");
      const local = createHash("sha256").update(payload).digest("hex");
      const result = await client.dataPutPublic(payload);
      expect(result.sha256).toBe(local);
    },
    300_000,
  );
});
