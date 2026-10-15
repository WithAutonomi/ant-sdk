import { BadRequestError, InternalError } from "./errors.js";

// ---- Manifests (the antd release after 0.15.0) ----
//
// An ADR-0006 manifest (a `.ant` file, or an `ant://manifest/` link) describes
// a set of files. Each entry has an optional path and size, and either an
// embedded DataMap (the manifest is then the key to that file) or a public
// file's DataMap address. The daemon builds and decodes manifests through
// ant-core, so callers never re-implement the format.
//
// Nothing is uploaded or paid for. Building with `embedRoots` and decoding
// with `resolve` read from the network, so they can time out, and they are
// safe to retry.
//
// On the REST wire the `.ant` bytes travel as base64 (`manifest` in the build
// response and the decode request). This SDK always takes and returns raw
// bytes; callers never see base64.

/**
 * One file for `buildManifest`. Set exactly one of `dataMap` or `address`;
 * an empty string counts as not set.
 */
export interface ManifestEntryInput {
  /**
   * The relative path the entry extracts under, subject to the portable path
   * rules. Omitted: it extracts under its content address.
   */
  path?: string;
  /**
   * The plaintext size to record, as given (the creator's claim). Omitted or
   * `null`: none is recorded, and readers take the exact size from an
   * embedded root DataMap. `0` is a size, not "unset".
   */
  size?: number | null;
  /** A hex DataMap, as the upload methods return it. The entry embeds it. */
  dataMap?: string;
  /** A public file's DataMap address (hex, 32 bytes). */
  address?: string;
}

/** The optional parts of a `buildManifest` call. */
export interface BuildManifestOptions {
  /** A suggested root directory name (one portable path component). */
  name?: string;
  /**
   * BitTorrent info hashes of the same files: hex, 40 characters for v1
   * and/or 64 for v2.
   */
  torrentInfoHashes?: string[];
  /**
   * Resolve each shrunk DataMap's root (fetching its wrapper records) and
   * embed the root when it is at most 64 KiB, so recipients skip that fetch
   * (ADR-0006's policy). Default `true`; `false` embeds shrunk DataMaps
   * exactly as given.
   */
  embedRoots?: boolean;
}

/** What a manifest says about one entry. Unset values are `null`. */
export interface ManifestEntryInfo {
  /** `path`, or the content address in hex when there is none. */
  effectiveName: string;
  path: string | null;
  /** The size recorded in the manifest (the creator's claim), or `null`. */
  size: number | null;
  /** `"embedded"` or `"public"`. */
  kind: string;
  /**
   * The file's public DataMap address (hex), whether or not it was ever made
   * public; the same for private and public uploads of one file.
   */
  contentAddress: string;
  /**
   * The embedded DataMap in the hex form the download methods accept.
   * Decode only: `null` for public entries and on every built entry.
   */
  dataMap: string | null;
  /**
   * The exact plaintext size, from an embedded root DataMap or after a
   * resolving decode; `null` when not known.
   */
  exactSize: number | null;
  /** Why a resolving decode failed for this entry; `null` otherwise. */
  error: string | null;
}

/** The result of `buildManifest`. */
export interface BuiltManifest {
  /** The `.ant` bytes. */
  manifest: Buffer;
  /**
   * The `ant://manifest/` link, or `null` when it does not fit the
   * recommended 1,500 bytes.
   */
  link: string | null;
  /** In encoded order (sorted by effective name). */
  entries: ManifestEntryInfo[];
}

/** The result of `decodeManifest` and `decodeManifestLink`. */
export interface DecodedManifest {
  /**
   * `"manifest"`, or `"file_link"` for a file link or bare address (reported
   * as one public entry with no path).
   */
  source: string;
  name: string | null;
  torrentInfoHashV1: string | null;
  torrentInfoHashV2: string | null;
  entries: ManifestEntryInfo[];
}

// ---- Wire forms ----

const BASE64 = /^[A-Za-z0-9+/]*={0,2}$/;

function isSet(value: unknown): value is string {
  return typeof value === "string" && value !== "";
}

/** A string the daemon always sends; anything else reads as `""`. */
function requiredString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

/** An optional string: absent, `null` or `""` reads as `null`. */
function optionalString(value: unknown): string | null {
  return isSet(value) ? value : null;
}

/**
 * An optional size. REST omits an unset size, so absent (or `null`) reads as
 * `null`, never 0. A value that is not a non-negative integer throws
 * {@link InternalError}.
 */
function optionalSize(field: string, value: unknown): number | null {
  if (value === undefined || value === null) return null;
  if (typeof value === "number" && Number.isInteger(value) && value >= 0) return value;
  throw new InternalError(`antd: manifest ${field} ${JSON.stringify(value)} is not a size`);
}

/**
 * Check entries the way the daemon will, before anything is sent: exactly
 * one of `dataMap` or `address`, and a size that is a non-negative integer.
 * Throws {@link BadRequestError} naming `entries[i]`, as the daemon's 400
 * does.
 */
function checkManifestEntries(entries: ManifestEntryInput[]): void {
  entries.forEach((e, i) => {
    if (isSet(e.dataMap) === isSet(e.address)) {
      throw new BadRequestError(
        `antd: manifest entries[${i}]: set exactly one of dataMap or address`,
      );
    }
    if (e.size !== undefined && e.size !== null && !(Number.isSafeInteger(e.size) && e.size >= 0)) {
      throw new BadRequestError(
        `antd: manifest entries[${i}]: size ${String(e.size)} is not a non-negative integer`,
      );
    }
  });
}

/** The `POST /v1/manifests/build` body. Throws before sending on a bad entry. */
export function manifestBuildBody(
  entries: ManifestEntryInput[],
  options: BuildManifestOptions = {},
): Record<string, unknown> {
  checkManifestEntries(entries);
  const wire = entries.map((e) => {
    const m: Record<string, unknown> = {};
    if (isSet(e.path)) m.path = e.path;
    if (e.size !== undefined && e.size !== null) m.size = e.size;
    if (isSet(e.dataMap)) m.data_map = e.dataMap;
    else m.address = e.address;
    return m;
  });
  const body: Record<string, unknown> = {
    entries: wire,
    // The daemon's default is true too; send it so the choice is explicit.
    embed_roots: options.embedRoots ?? true,
  };
  if (isSet(options.name)) body.name = options.name;
  if (options.torrentInfoHashes !== undefined && options.torrentInfoHashes.length > 0) {
    body.torrent_info_hashes = options.torrentInfoHashes;
  }
  return body;
}

/** The `POST /v1/manifests/decode` body for `.ant` bytes, base64 on the wire. */
export function manifestDecodeBody(
  manifest: Uint8Array | Buffer,
  resolve: boolean,
): Record<string, unknown> {
  if (manifest.byteLength === 0) {
    throw new BadRequestError("antd: decodeManifest: manifest is empty");
  }
  // A view, not a copy: a manifest can be 64 MiB.
  const buf = Buffer.isBuffer(manifest)
    ? manifest
    : Buffer.from(manifest.buffer, manifest.byteOffset, manifest.byteLength);
  return { manifest: buf.toString("base64"), resolve };
}

/** The `POST /v1/manifests/decode` body for a link or bare address. */
export function manifestLinkDecodeBody(link: string, resolve: boolean): Record<string, unknown> {
  if (!isSet(link)) {
    throw new BadRequestError("antd: decodeManifestLink: link is empty");
  }
  return { link, resolve };
}

function entryFromJson(j: Record<string, unknown>): ManifestEntryInfo {
  return {
    effectiveName: requiredString(j.effective_name),
    path: optionalString(j.path),
    size: optionalSize("size", j.size),
    kind: requiredString(j.kind),
    contentAddress: requiredString(j.content_address),
    dataMap: optionalString(j.data_map),
    exactSize: optionalSize("exact_size", j.exact_size),
    error: optionalString(j.error),
  };
}

function entriesFromJson(value: unknown): ManifestEntryInfo[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((e): e is Record<string, unknown> => e !== null && typeof e === "object")
    .map(entryFromJson);
}

/**
 * Convert a build response. The `.ant` bytes arrive as standard base64; one
 * that is not valid base64 throws {@link InternalError} rather than decoding
 * leniently into the wrong bytes.
 */
export function builtManifestFromJson(j: Record<string, unknown>): BuiltManifest {
  const b64 = j.manifest;
  if (typeof b64 !== "string" || b64.length % 4 !== 0 || !BASE64.test(b64)) {
    throw new InternalError("antd: buildManifest: manifest is not valid base64");
  }
  return {
    manifest: Buffer.from(b64, "base64"),
    link: optionalString(j.link),
    entries: entriesFromJson(j.entries),
  };
}

/** Convert a decode response. */
export function decodedManifestFromJson(j: Record<string, unknown>): DecodedManifest {
  return {
    source: requiredString(j.source),
    name: optionalString(j.name),
    torrentInfoHashV1: optionalString(j.torrent_info_hash_v1),
    torrentInfoHashV2: optionalString(j.torrent_info_hash_v2),
    entries: entriesFromJson(j.entries),
  };
}
