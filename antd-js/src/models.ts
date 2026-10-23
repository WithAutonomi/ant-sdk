/**
 * Health check result from the antd daemon.
 *
 * The diagnostic fields (version, evmNetwork, uptimeSeconds, buildCommit,
 * paymentTokenAddress, paymentVaultAddress) were added in antd 0.4.0. They
 * default to "" / 0 so the type can still be constructed from the response of
 * an older daemon that doesn't report them.
 */
export interface HealthStatus {
  ok: boolean;
  network: string; // "default", "local", "alpha"
  version: string; // antd crate version, e.g. "0.4.0"
  evmNetwork: string; // "arbitrum-one", "arbitrum-sepolia", "local", "custom"
  uptimeSeconds: number; // seconds since the daemon process started
  buildCommit: string; // short git SHA, "" if unknown
  paymentTokenAddress: string; // "" if unconfigured
  paymentVaultAddress: string; // "" if unconfigured
}

/**
 * Payment-batching strategy for uploads.
 *
 * - `PaymentMode.Auto`   — server picks (merkle for 64+ chunks, single otherwise).
 * - `PaymentMode.Merkle` — force merkle-batch (saves gas, min 2 chunks).
 * - `PaymentMode.Single` — force per-chunk payments (works for any chunk count).
 *
 * The string values are the exact wire-format the daemon accepts, so a bare
 * string literal (`"auto"` etc.) also satisfies the `PaymentMode` type.
 */
export const PaymentMode = {
  Auto: "auto",
  Merkle: "merkle",
  Single: "single",
} as const;
export type PaymentMode = (typeof PaymentMode)[keyof typeof PaymentMode];

/** Result of a `chunkPut` operation. The DataMap concept doesn't apply at chunk level. */
export interface PutResult {
  cost: string; // atto tokens as string
  address: string; // hex
}

/**
 * Result of a private data put. The DataMap is returned to the caller; it
 * is NOT stored on-network.
 */
export interface DataPutResult {
  dataMap: string; // hex caller-held DataMap
  chunksStored: number;
  paymentModeUsed: string;
  /** The plaintext's SHA-256 (hex, lowercase); `null` on antd older than 0.17.0. */
  sha256: string | null;
}

/**
 * Result of a public data put. The DataMap is stored on-network as an extra
 * chunk; `address` is the shareable retrieval handle.
 */
export interface DataPutPublicResult {
  address: string; // hex on-network DataMap address
  chunksStored: number;
  paymentModeUsed: string;
  /** The plaintext's SHA-256 (hex, lowercase); `null` on antd older than 0.17.0. */
  sha256: string | null;
}

/**
 * Result of a private file upload. The DataMap is returned to the caller;
 * it is NOT stored on-network.
 */
export interface FilePutResult {
  dataMap: string; // hex caller-held DataMap
  storageCostAtto: string; // "0" if all chunks already existed
  gasCostWei: string; // decimal string
  chunksStored: number;
  paymentModeUsed: string;
  /** The plaintext's SHA-256 (hex, lowercase); `null` on antd older than 0.17.0. */
  sha256: string | null;
}

/**
 * Result of a public file upload. The DataMap is stored on-network as an
 * extra chunk; `address` is the shareable retrieval handle.
 */
export interface FilePutPublicResult {
  address: string; // hex on-network DataMap address
  storageCostAtto: string;
  gasCostWei: string;
  chunksStored: number;
  paymentModeUsed: string;
  /** The plaintext's SHA-256 (hex, lowercase); `null` on antd older than 0.17.0. */
  sha256: string | null;
}

/** Wallet address response. */
export interface WalletAddress {
  address: string; // 0x-prefixed hex
}

/** Wallet balance response. */
export interface WalletBalance {
  balance: string; // atto tokens as string
  gasBalance: string; // atto tokens as string
}

/** A single payment required for an upload. */
export interface PaymentInfo {
  quoteHash: string; // hex
  rewardsAddress: string; // hex
  amount: string; // atto tokens
}

/** A candidate node entry within a merkle pool commitment. */
export interface CandidateNodeEntry {
  rewardsAddress: string;
  amount: string;
}

/** A pool commitment containing candidate nodes for merkle batch payments. */
export interface PoolCommitmentEntry {
  poolHash: string;
  candidates: CandidateNodeEntry[];
}

/** Result of preparing an upload for external signing. */
export interface PrepareUploadResult {
  uploadId: string; // hex identifier
  payments: PaymentInfo[];
  totalAmount: string;
  paymentVaultAddress: string; // payment vault contract address
  paymentTokenAddress: string; // token contract address
  rpcUrl: string; // EVM RPC URL
  paymentType: string; // "wave_batch" or "merkle"
  depth?: number; // merkle tree depth (merkle only)
  poolCommitments?: PoolCommitmentEntry[]; // pool commitments (merkle only)
  merklePaymentTimestamp?: number; // payment timestamp (merkle only)
  // Already-stored preflight (added in antd 0.10.0). 0 on older daemons. The
  // external signer pays for (totalChunks - alreadyStoredCount) chunks.
  totalChunks: number; // total chunks incl. already-stored
  alreadyStoredCount: number; // chunks skipped (already on-network)
}

/** Result of finalizing an externally-signed upload. */
export interface FinalizeUploadResult {
  address: string; // hex address of stored data (legacy: set when store_data_map=true was passed; "" otherwise)
  chunksStored: number;
  dataMap: string; // hex-encoded serialized DataMap (always returned, "" on older daemons)
  dataMapAddress: string; // set when prepare was called with visibility="public" (paid in same external-signer batch); "" otherwise
  /** The plaintext's SHA-256 (hex, lowercase); `null` on antd older than 0.17.0. */
  sha256: string | null;
}

/**
 * Result of preparing a single-chunk external-signer publish via
 * `POST /v1/chunks/prepare`.
 *
 * When `alreadyStored` is true the chunk is already on-network — only
 * `address` and `alreadyStored` are populated and no finalize call is needed.
 * Otherwise the wave-batch payment fields describe what the external signer
 * must submit before calling `finalizeChunkUpload`.
 */
export interface PrepareChunkResult {
  /** Content-addressed BLAKE3 of the chunk bytes (hex, 64 chars). Always set. */
  address: string;
  /** True if the chunk is already stored on the network and no payment is needed. */
  alreadyStored: boolean;
  /** Opaque identifier to pass back to `finalizeChunkUpload`. "" when alreadyStored. */
  uploadId: string;
  /** Always "wave_batch" for single-chunk publishes; "" when alreadyStored. */
  paymentType: string;
  /** Per-quote payment entries for `payForQuotes()`. Empty when alreadyStored. */
  payments: PaymentInfo[];
  /** Total amount to pay (atto tokens, decimal string). "" when alreadyStored. */
  totalAmount: string;
  /** Payment vault contract address (hex with 0x prefix). "" when alreadyStored. */
  paymentVaultAddress: string;
  /** Payment token contract address (hex with 0x prefix). "" when alreadyStored. */
  paymentTokenAddress: string;
  /** EVM RPC URL for submitting transactions. "" when alreadyStored. */
  rpcUrl: string;
}

/**
 * A per-chunk fetch-progress update interleaved into a `*WithProgress`
 * download stream.
 *
 * The byte denominator (total payload size) arrives separately as the leading
 * NDJSON `meta` frame and is the basis for a byte-level bar; these counts are
 * CHUNKS — `fetched` of `total` chunks resolved/fetched so far — and are the
 * numerator that actually advances determinately as decrypt batches land.
 */
export interface DownloadProgress {
  /** Fetch phase: `"resolving_map"`, `"resolved"`, or `"fetching"`. */
  phase: string;
  /** Chunks fetched so far. */
  fetched: number;
  /** Total chunks to fetch, or 0 if not yet known. */
  total: number;
}

/**
 * One frame of a `dataStreamWithProgress` / `dataStreamPublicWithProgress`
 * download. Exactly one of `meta` / `data` / `progress` is set — `meta` carries
 * the total download size in *bytes* (the progress *denominator*), `data`
 * carries a plaintext chunk batch, `progress` carries a {@link DownloadProgress}
 * update.
 *
 * The `meta` frame is surfaced from the leading REST NDJSON `meta` line and is
 * emitted at most once, before any data, when the daemon reports it (older
 * daemons omit it). Pair it with the byte count of the `data` frames to render
 * a byte-accurate progress bar. Use {@link isMetaFrame} / {@link isProgressFrame}
 * to discriminate.
 */
export type DownloadFrame =
  | { meta: number; data?: undefined; progress?: undefined }
  | { meta?: undefined; data: Uint8Array; progress?: undefined }
  | { meta?: undefined; data?: undefined; progress: DownloadProgress };

/** Type guard: true when the frame is a `meta` byte-total frame. */
export function isMetaFrame(
  frame: DownloadFrame,
): frame is { meta: number; data?: undefined; progress?: undefined } {
  return frame.meta !== undefined;
}

/** Type guard: true when the frame is a {@link DownloadProgress} update. */
export function isProgressFrame(
  frame: DownloadFrame,
): frame is { meta?: undefined; data?: undefined; progress: DownloadProgress } {
  return frame.progress !== undefined;
}

/**
 * Pre-upload cost breakdown returned by `dataCost` / `fileCost`.
 *
 * The server samples up to 5 chunk addresses and extrapolates the storage
 * cost. Gas is an advisory heuristic, not a live gas-oracle query.
 */
export interface UploadCostEstimate {
  cost: string; // storage cost in atto tokens
  fileSize: number; // original file size in bytes (uint64)
  chunkCount: number; // number of data chunks (uint32)
  estimatedGasCostWei: string; // advisory gas heuristic in wei
  paymentMode: string; // "auto" | "merkle" | "single"
}

// ---- Pointers (antd >= 0.16.0) ----
//
// A pointer is a small, owner-signed, mutable reference. Its address is
// derived from its owner's key and never changes; what it points at (a chunk,
// such as a public file's data map, or another pointer) can be changed by the
// owner, and the owner can hand it over to another pointer for good. antd
// signs with owner keys it loaded at startup (`--pointer-keys`), so a write
// names the pointer by its address (`owner`), never by a key.
//
// Every write pays, about the price of one chunk, and every attempt pays
// again: do not retry a create, update, transfer or finalize automatically.
//
// Addresses, state ids and targets are 64 hex characters. The daemon accepts
// a `0x` prefix on input but always returns bare hex, so normalise before
// comparing.

/**
 * What a pointer points at.
 *
 * - `PointerKind.Chunk`   — a chunk, such as a public file's data map. The
 *   default when a kind is omitted.
 * - `PointerKind.Pointer` — another pointer: a forwarding the owner can still
 *   change. Use `pointerTransfer` to hand a pointer over for good.
 *
 * The string values are the wire format, so `"chunk"` / `"pointer"` also
 * satisfy the type.
 */
export const PointerKind = {
  Chunk: "chunk",
  Pointer: "pointer",
} as const;
export type PointerKind = (typeof PointerKind)[keyof typeof PointerKind];

/**
 * The counter of a pointer's final state, after a transfer or a freeze
 * (2^64 - 1): nothing can replace it. Counters are `bigint` because this value
 * is past what a JS `number` holds exactly.
 */
export const POINTER_FINAL_COUNTER: bigint = 18446744073709551615n;

/**
 * The write `pointerPrepare` signs for an external signer to pay.
 *
 * - `create`: point a new pointer at `target`. Refused if it already exists.
 * - `update`: point the pointer at `target`, creating it if it does not exist.
 * - `transfer`: hand the pointer over for good to the pointer at `recipient`,
 *   which must already exist. Irreversible once stored.
 *
 * `kind` defaults to {@link PointerKind.Chunk} when omitted.
 */
export type PointerOp =
  | { op: "create"; target: string; kind?: PointerKind }
  | { op: "update"; target: string; kind?: PointerKind }
  | { op: "transfer"; recipient: string };

/** The state a pointer write stored. */
export interface PointerWriteResult {
  address: string; // hex
  stateId: string; // hex; the identifier the state was paid against
  /** The state's counter. A final state sits at {@link POINTER_FINAL_COUNTER}. */
  counter: bigint;
}

/** A pointer's current state, as the network serves it. */
export interface PointerRecord {
  address: string; // hex
  /**
   * The owner's ML-DSA-65 public key (hex, 1,952 bytes). The address is
   * derived from it, so it is the proof of who owns the pointer.
   */
  owner: string;
  counter: bigint;
  /**
   * `"chunk"`, `"pointer"`, or `"unknown"` for a kind the daemon does not
   * know; `kindTag` carries the raw value either way.
   */
  kind: string;
  kindTag: number;
  target: string; // hex
  stateId: string; // hex
  /** The state is at the final counter (handed over or frozen): nothing can replace it. */
  isFinal: boolean;
  /** The pointer this one was handed over to, or `null`. */
  transferredTo: string | null;
}

/** Where a chain of pointers ends (`pointerResolve`). */
export interface PointerTarget {
  /** `"chunk"`, or `"unknown"` for a target kind the daemon does not know. */
  kind: string;
  kindTag: number;
  target: string; // hex
}

/**
 * Where a pointer stands with respect to finality, as its whole close group
 * reports it:
 *
 * - `"open"`: no peer that answered holds a final state; the owner can still
 *   move the pointer.
 * - `"settling"`: one final state, not yet held by a majority.
 * - `"unconfirmed"`: one final state held by a majority, but not every peer
 *   answered, so a rival could still exist. Ask again.
 * - `"final"`: one final state, held by a majority, every peer answered, no
 *   rival. Only this status means a transfer is beyond dispute.
 * - `"forked"`: the owner signed two or more different final states.
 * - `"unknown"`: a status this SDK does not know (a newer daemon);
 *   {@link PointerFinality.rawStatus} carries the daemon's string.
 */
export type PointerFinalityStatus =
  | "open"
  | "settling"
  | "unconfirmed"
  | "final"
  | "forked"
  | "unknown";

/** One final state, as a finality check reports it. */
export interface PointerFinalState {
  stateId: string;
  kind: string;
  kindTag: number;
  target: string;
  /** Close-group peers holding it. */
  holders: number;
  transferredTo: string | null;
}

/**
 * The whole close group's view of a pointer's finality (`pointerFinality`).
 * Check it before relying on a transfer: only `status === "final"` means the
 * transfer is beyond dispute.
 */
export interface PointerFinality {
  address: string;
  /** Peers in the close group. */
  group: number;
  /** Peers that answered. */
  answered: number;
  status: PointerFinalityStatus;
  /** The daemon's status string as sent; differs from `status` only when that is `"unknown"`. */
  rawStatus: string;
  /** `"open"` only: the counter a read would return, if any state is corroborated; else `null`. */
  counter: bigint | null;
  /** `"settling"`, `"unconfirmed"` and `"final"`: the one final state seen; else `null`. */
  state: PointerFinalState | null;
  /** `"forked"` only: every final state seen, most-held first; else empty. */
  states: PointerFinalState[];
  /** `"forked"` only: the state a majority holds, which reads return; else `null`. */
  majority: PointerFinalState | null;
  /** The pointer this one was handed over to, once that is beyond dispute (`"final"`); else `null`. */
  transferredTo: string | null;
}

/** Whose pointer decides what an address resolves to, after following every transfer. */
export interface PointerController {
  pointer: string;
  /** Every pointer the address was handed over to, in order. */
  transfers: string[];
  /** `pointer` is final without being handed over: nobody can move it. */
  frozen: boolean;
}

/**
 * What a transfer stored, and where the close group says it stands.
 * `finality` is `null` when that check failed (`finalityError` says why); the
 * transfer itself is stored and final either way. Ask again with
 * `pointerFinality`.
 */
export interface PointerTransferResult {
  address: string;
  stateId: string;
  finality: PointerFinality | null;
  finalityError: string | null;
}

/**
 * One `payments[]` quote in full signed form, returned when a prepare asks
 * for `includeSignedQuotes`. Both payloads are opaque to the SDK.
 */
export interface SignedQuoteEntry {
  quoteHash: string; // hex, matches the payments[] entry
  quote: string; // base64(msgpack signed PaymentQuote)
  /** base64(msgpack StorageCommitment), for commitment-bound quotes; else `null`. */
  commitmentSidecar: string | null;
}

/**
 * A pointer write signed by the daemon and quoted for an external signer
 * (`pointerPrepare`): the same wave-batch shape `prepareChunkUpload` returns.
 * Pay `payments` with `payForQuotes()`, then call `pointerFinalize`. While it
 * awaits payment, other writes to the pointer throw `ConflictError`.
 */
export interface PointerPrepareResult {
  uploadId: string;
  /** `"create"`, `"update"` or `"transfer"`. */
  op: string;
  address: string;
  stateId: string;
  counter: bigint;
  /** Always `"wave_batch"`: a pointer state is paid with one quote. */
  paymentType: string;
  payments: PaymentInfo[];
  totalAmount: string; // atto tokens, decimal string
  paymentVaultAddress: string;
  paymentTokenAddress: string;
  rpcUrl: string;
  /** Populated when the prepare asked for `includeSignedQuotes`; else empty. */
  signedQuotes: SignedQuoteEntry[];
}

/** The state a pointer finalize stored. `finality` is set for a transfer, else `null`. */
export interface PointerFinalizeResult {
  address: string;
  stateId: string;
  counter: bigint;
  finality: PointerFinality | null;
}
