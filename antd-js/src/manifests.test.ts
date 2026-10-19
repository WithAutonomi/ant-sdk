import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { RestClient } from "./rest-client.js";
import { BadRequestError, InternalError, NetworkError, NotFoundError } from "./errors.js";

// ---------------------------------------------------------------------------
// Manifest API over a mocked REST daemon.
// ---------------------------------------------------------------------------

/** The five-byte `.ant` header; "wUFOVAE=" is its base64. */
const HEADER = Buffer.from([0xc1, 0x41, 0x4e, 0x54, 0x01]);
const HEADER_B64 = "wUFOVAE=";
/** Bytes whose standard base64 uses both "+" and "/" (URL-safe would not). */
const PLUS_SLASH = Buffer.from([0xfb, 0xff, 0xbf]);
const PLUS_SLASH_B64 = "+/+/";
const ADDR = "11".repeat(32);
const CA = "cc".repeat(32);
const DM = "9301abcd";
const LINK = "ant://manifest/wUFOVAE";

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    statusText: status === 200 ? "OK" : "Error",
    headers: { "Content-Type": "application/json" },
  });
}

type Captured = { method: string; path: string; body: Record<string, unknown> | undefined };

/**
 * Stub fetch with a single canned response and record every request, so a
 * test can check the method, path and JSON body the client sent (and whether
 * it sent anything at all).
 */
function stubFetch(status: number, body: unknown): Captured[] {
  const calls: Captured[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
      calls.push({
        method: (init?.method ?? "GET").toUpperCase(),
        path: url.pathname,
        body: typeof init?.body === "string" ? JSON.parse(init.body) : undefined,
      });
      return Promise.resolve(jsonResponse(status, body));
    }),
  );
  return calls;
}

/** Await a promise expected to reject and return the rejection. */
async function rejection(p: Promise<unknown>): Promise<unknown> {
  return p.then(
    () => {
      throw new Error("expected a rejection");
    },
    (e: unknown) => e,
  );
}

const builtJson = {
  manifest: HEADER_B64,
  link: LINK,
  entries: [
    {
      effective_name: "a.txt",
      path: "a.txt",
      size: 10,
      kind: "embedded",
      content_address: CA,
      exact_size: 10,
    },
    { effective_name: ADDR, kind: "public", content_address: ADDR },
  ],
};

const decodedJson = {
  source: "manifest",
  name: "album",
  torrent_info_hash_v2: "bb".repeat(32),
  entries: [
    {
      effective_name: "a.txt",
      path: "a.txt",
      kind: "embedded",
      content_address: CA,
      data_map: DM,
      exact_size: 3,
    },
    {
      effective_name: "b",
      path: "b",
      kind: "public",
      content_address: ADDR,
      error: "Record not found: gone",
    },
  ],
};

describe("RestClient manifests", () => {
  let client: RestClient;

  beforeEach(() => {
    client = new RestClient({ baseUrl: "http://localhost:8082" });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  describe("buildManifest()", () => {
    it("POSTs the entries and options in wire form", async () => {
      const calls = stubFetch(200, builtJson);
      await client.buildManifest(
        [{ path: "a.txt", size: 10, dataMap: DM }, { address: ADDR }],
        { name: "album", torrentInfoHashes: ["aa".repeat(20)], embedRoots: false },
      );
      expect(calls).toEqual([
        {
          method: "POST",
          path: "/v1/manifests/build",
          body: {
            entries: [{ path: "a.txt", size: 10, data_map: DM }, { address: ADDR }],
            embed_roots: false,
            name: "album",
            torrent_info_hashes: ["aa".repeat(20)],
          },
        },
      ]);
    });

    it("returns the base64 manifest as raw bytes, plus the link and entries", async () => {
      stubFetch(200, builtJson);
      const built = await client.buildManifest([{ path: "a.txt", size: 10, dataMap: DM }, { address: ADDR }]);
      expect(Buffer.isBuffer(built.manifest)).toBe(true);
      expect(built.manifest.equals(HEADER)).toBe(true);
      expect(built.link).toBe(LINK);
      expect(built.entries).toEqual([
        {
          effectiveName: "a.txt",
          path: "a.txt",
          size: 10,
          kind: "embedded",
          contentAddress: CA,
          dataMap: null,
          exactSize: 10,
          error: null,
        },
        {
          effectiveName: ADDR,
          path: null,
          size: null,
          kind: "public",
          contentAddress: ADDR,
          dataMap: null,
          exactSize: null,
          error: null,
        },
      ]);
    });

    it("decodes the standard base64 alphabet (+ and /)", async () => {
      stubFetch(200, { ...builtJson, manifest: PLUS_SLASH_B64 });
      const built = await client.buildManifest([{ address: ADDR }]);
      expect(built.manifest.equals(PLUS_SLASH)).toBe(true);
    });

    it("reads an unset size and exact size as null, and 0 as 0", async () => {
      stubFetch(200, {
        manifest: HEADER_B64,
        entries: [
          { effective_name: "z", path: "z", size: 0, kind: "embedded", content_address: CA, exact_size: 0 },
          { effective_name: "u", path: "u", kind: "embedded", content_address: CA },
          { effective_name: "n", path: "n", size: null, kind: "public", content_address: ADDR, exact_size: null },
        ],
      });
      const { entries, link } = await client.buildManifest([{ address: ADDR }]);
      expect(link).toBeNull();
      expect(entries.map((e) => [e.size, e.exactSize])).toEqual([
        [0, 0],
        [null, null],
        [null, null],
      ]);
    });

    it("defaults embed_roots to true and omits unset options", async () => {
      const calls = stubFetch(200, { manifest: "", entries: [] });
      await client.buildManifest([{ address: ADDR }]);
      await client.buildManifest([{ address: ADDR }], {});
      await client.buildManifest([{ address: ADDR }], { name: "", torrentInfoHashes: [], embedRoots: undefined });
      for (const c of calls) {
        expect(c.body).toEqual({ entries: [{ address: ADDR }], embed_roots: true });
      }
      expect(calls).toHaveLength(3);
    });

    it("omits an unset path and size but sends a size of 0", async () => {
      const calls = stubFetch(200, { manifest: "", entries: [] });
      await client.buildManifest([
        { path: "", size: null, dataMap: DM },
        { size: undefined, address: ADDR },
        { path: "empty.txt", size: 0, address: ADDR },
      ]);
      expect(calls[0].body?.entries).toEqual([
        { data_map: DM },
        { address: ADDR },
        { path: "empty.txt", size: 0, address: ADDR },
      ]);
    });

    it("treats an empty dataMap or address as not set", async () => {
      const calls = stubFetch(200, { manifest: "", entries: [] });
      await client.buildManifest([
        { dataMap: "", address: ADDR },
        { dataMap: DM, address: "" },
      ]);
      expect(calls[0].body?.entries).toEqual([{ address: ADDR }, { data_map: DM }]);
    });

    it.each([
      ["neither", {}, "needs a data_map or an address"],
      ["both", { dataMap: DM, address: ADDR }, "give data_map or address, not both"],
      ["two empty strings", { dataMap: "", address: "" }, "needs a data_map or an address"],
    ])("rejects an entry with %s before sending, in the daemon's words", async (_l, bad, why) => {
      const calls = stubFetch(200, builtJson);
      const err = await rejection(client.buildManifest([{ address: ADDR }, bad]));
      expect(err).toBeInstanceOf(BadRequestError);
      expect((err as BadRequestError).statusCode).toBe(400);
      expect((err as Error).message).toBe(`1 invalid entries: entries[1]: ${why}`);
      expect(calls).toHaveLength(0);
    });

    it("reports every bad entry together, 0-based, joined with a semicolon", async () => {
      const calls = stubFetch(200, builtJson);
      const err = await rejection(
        client.buildManifest([{ dataMap: DM, address: ADDR }, { address: ADDR }, {}]),
      );
      expect(err).toBeInstanceOf(BadRequestError);
      expect((err as BadRequestError).statusCode).toBe(400);
      expect((err as Error).message).toBe(
        "2 invalid entries: entries[0]: give data_map or address, not both; " +
          "entries[2]: needs a data_map or an address",
      );
      expect(calls).toHaveLength(0);
    });

    it("lists at most 20 bad entries, then says how many more", async () => {
      stubFetch(200, builtJson);
      const err = await rejection(client.buildManifest(Array.from({ length: 23 }, () => ({}))));
      const listed = Array.from({ length: 20 }, (_, i) => `entries[${i}]: needs a data_map or an address`);
      expect((err as Error).message).toBe(`23 invalid entries: ${listed.join("; ")}; and 3 more`);
    });

    it.each([[-1], [1.5], [Number.NaN], [2 ** 53]])(
      "rejects a size of %s before sending, as entries[i]",
      async (size) => {
        const calls = stubFetch(200, builtJson);
        const err = await rejection(client.buildManifest([{ address: ADDR }, { size, address: ADDR }]));
        expect(err).toBeInstanceOf(BadRequestError);
        expect((err as BadRequestError).statusCode).toBe(400);
        expect((err as Error).message).toBe(
          `1 invalid entries: entries[1]: size ${String(size)} is not a non-negative integer`,
        );
        expect(calls).toHaveLength(0);
      },
    );

    it("maps the daemon's 400 to BadRequestError and keeps its message", async () => {
      const msg = 'Bad request: 1 invalid entries: entries[0]: invalid path "../x": path escapes its root';
      stubFetch(400, { error: msg, code: "BAD_REQUEST" });
      const err = await rejection(client.buildManifest([{ path: "../x", address: ADDR }]));
      expect(err).toBeInstanceOf(BadRequestError);
      expect((err as BadRequestError).statusCode).toBe(400);
      expect((err as Error).message).toBe(msg);
    });

    it("keeps the kind of a network failure while resolving a shrunk DataMap", async () => {
      stubFetch(404, { error: "Not found: entries[0]: wrapper record", code: "NOT_FOUND" });
      expect(await rejection(client.buildManifest([{ dataMap: DM }]))).toBeInstanceOf(NotFoundError);
      stubFetch(502, { error: "Network error: entries[0]: timed out", code: "NETWORK_ERROR" });
      expect(await rejection(client.buildManifest([{ dataMap: DM }]))).toBeInstanceOf(NetworkError);
    });

    it.each([
      ["missing", undefined],
      ["not base64", "not base64!"],
      ["unpadded", "wUFOVAE"],
      ["URL-safe", "-_-_"],
    ])("throws InternalError for a %s manifest", async (_label, manifest) => {
      stubFetch(200, { ...builtJson, manifest });
      expect(await rejection(client.buildManifest([{ address: ADDR }]))).toBeInstanceOf(InternalError);
    });

    it.each([[-1], [1.5], ["10"]])("throws InternalError for a malformed size %j", async (size) => {
      stubFetch(200, {
        manifest: HEADER_B64,
        entries: [{ effective_name: "a", path: "a", size, kind: "public", content_address: ADDR }],
      });
      expect(await rejection(client.buildManifest([{ address: ADDR }]))).toBeInstanceOf(InternalError);
    });
  });

  describe("decodeManifest()", () => {
    it("sends the bytes as base64 with resolve, and parses the manifest", async () => {
      const calls = stubFetch(200, decodedJson);
      const decoded = await client.decodeManifest(HEADER, true);
      expect(calls).toEqual([
        {
          method: "POST",
          path: "/v1/manifests/decode",
          body: { manifest: HEADER_B64, resolve: true },
        },
      ]);
      expect(decoded).toEqual({
        source: "manifest",
        name: "album",
        torrentInfoHashV1: null,
        torrentInfoHashV2: "bb".repeat(32),
        entries: [
          {
            effectiveName: "a.txt",
            path: "a.txt",
            size: null,
            kind: "embedded",
            contentAddress: CA,
            dataMap: DM,
            exactSize: 3,
            error: null,
          },
          {
            // One entry's resolve failure is in its error, not a failed call.
            effectiveName: "b",
            path: "b",
            size: null,
            kind: "public",
            contentAddress: ADDR,
            dataMap: null,
            exactSize: null,
            error: "Record not found: gone",
          },
        ],
      });
    });

    it("defaults resolve to false", async () => {
      const calls = stubFetch(200, decodedJson);
      await client.decodeManifest(HEADER);
      expect(calls[0].body).toEqual({ manifest: HEADER_B64, resolve: false });
    });

    it("round-trips built bytes into the decode request unchanged", async () => {
      const calls = stubFetch(200, { ...builtJson, manifest: PLUS_SLASH_B64 });
      const built = await client.buildManifest([{ address: ADDR }]);
      await client.decodeManifest(built.manifest);
      expect(calls[1].body?.manifest).toBe(PLUS_SLASH_B64);
    });

    it("accepts a plain Uint8Array, encoding only the view's bytes", async () => {
      const calls = stubFetch(200, decodedJson);
      const backing = new Uint8Array([0xff, ...HEADER, 0xff]);
      await client.decodeManifest(backing.subarray(1, 1 + HEADER.length));
      expect(calls[0].body?.manifest).toBe(HEADER_B64);
    });

    it("rejects empty bytes before sending", async () => {
      const calls = stubFetch(200, decodedJson);
      const err = await rejection(client.decodeManifest(new Uint8Array(0)));
      expect(err).toBeInstanceOf(BadRequestError);
      expect((err as BadRequestError).statusCode).toBe(400);
      expect((err as Error).message).toBe("needs a manifest (base64 .ant bytes) or a link");
      expect(calls).toHaveLength(0);
    });

    it("maps the daemon's 400 to BadRequestError and keeps its message", async () => {
      const msg = "Bad request: not a manifest: missing or invalid header";
      stubFetch(400, { error: msg, code: "BAD_REQUEST" });
      const err = await rejection(client.decodeManifest(Buffer.from("nope")));
      expect(err).toBeInstanceOf(BadRequestError);
      expect((err as Error).message).toBe(msg);
    });
  });

  describe("decodeManifestLink()", () => {
    it("sends the link, not manifest bytes", async () => {
      const calls = stubFetch(200, decodedJson);
      await client.decodeManifestLink(LINK, true);
      expect(calls).toEqual([
        { method: "POST", path: "/v1/manifests/decode", body: { link: LINK, resolve: true } },
      ]);
      await client.decodeManifestLink(LINK);
      expect(calls[1].body).toEqual({ link: LINK, resolve: false });
    });

    it("reports a file link as one public entry with no path", async () => {
      stubFetch(200, {
        source: "file_link",
        entries: [{ effective_name: ADDR, kind: "public", content_address: ADDR }],
      });
      const decoded = await client.decodeManifestLink(ADDR);
      expect(decoded.source).toBe("file_link");
      expect(decoded.name).toBeNull();
      expect(decoded.torrentInfoHashV1).toBeNull();
      expect(decoded.torrentInfoHashV2).toBeNull();
      expect(decoded.entries).toHaveLength(1);
      expect(decoded.entries[0]).toMatchObject({
        effectiveName: ADDR,
        path: null,
        kind: "public",
        contentAddress: ADDR,
        size: null,
        exactSize: null,
      });
    });

    it("rejects an empty link before sending", async () => {
      const calls = stubFetch(200, decodedJson);
      const err = await rejection(client.decodeManifestLink(""));
      expect(err).toBeInstanceOf(BadRequestError);
      expect((err as BadRequestError).statusCode).toBe(400);
      expect((err as Error).message).toBe("needs a manifest (base64 .ant bytes) or a link");
      expect(calls).toHaveLength(0);
    });

    // The daemon's sizes are u64. The body is written as raw text because
    // JSON.stringify would already round 2^53 + 1 before the client saw it.
    function stubRawEntry(sizeFields: string): void {
      const text =
        `{"source":"manifest","entries":[{"effective_name":"a","kind":"public",` +
        `"content_address":"${ADDR}"${sizeFields}}]}`;
      vi.stubGlobal(
        "fetch",
        vi.fn(() =>
          Promise.resolve(new Response(text, { status: 200, headers: { "Content-Type": "application/json" } })),
        ),
      );
    }

    it("refuses a size past 2^53 - 1 instead of rounding it", async () => {
      for (const field of ["size", "exact_size"]) {
        stubRawEntry(`,"${field}":9007199254740993`);
        const err = await rejection(client.decodeManifestLink(LINK));
        expect(err).toBeInstanceOf(InternalError);
        expect((err as Error).message).toContain(`manifest ${field} is above 9007199254740991`);
      }
    });

    it("keeps 0, the largest safe size, and absent or null sizes exactly", async () => {
      const read = async (sizeFields: string) => {
        stubRawEntry(sizeFields);
        const [e] = (await client.decodeManifestLink(LINK)).entries;
        return [e.size, e.exactSize];
      };
      expect(await read(`,"size":0,"exact_size":0`)).toEqual([0, 0]);
      expect(await read(`,"size":9007199254740991,"exact_size":9007199254740991`)).toEqual([
        9007199254740991, 9007199254740991,
      ]);
      expect(await read(``)).toEqual([null, null]);
      expect(await read(`,"size":null,"exact_size":null`)).toEqual([null, null]);
    });
  });
});
