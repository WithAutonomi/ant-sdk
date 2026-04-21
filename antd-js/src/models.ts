/** Health check result from the antd daemon. */
export interface HealthStatus {
  ok: boolean;
  network: string; // "default", "local", "alpha"
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
  address: string; // hex address of stored data
  chunksStored: number;
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
