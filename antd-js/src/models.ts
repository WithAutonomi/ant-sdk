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
}

/**
 * Result of a public data put. The DataMap is stored on-network as an extra
 * chunk; `address` is the shareable retrieval handle.
 */
export interface DataPutPublicResult {
  address: string; // hex on-network DataMap address
  chunksStored: number;
  paymentModeUsed: string;
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
