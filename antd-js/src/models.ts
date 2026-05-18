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

/** Result of a put/create operation. */
export interface PutResult {
  cost: string; // atto tokens as string
  address: string; // hex
}

/** Result of a public file or directory upload. */
export interface FileUploadResult {
  address: string; // hex network address
  storageCostAtto: string; // storage cost in atto, "0" if all chunks already existed
  gasCostWei: string; // gas cost in wei as decimal string
  chunksStored: number; // number of chunks stored on the network (uint64)
  paymentModeUsed: string; // "auto", "merkle", or "single"
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
 * Pre-upload cost breakdown returned by `estimateDataCost` / `estimateFileCost`.
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
