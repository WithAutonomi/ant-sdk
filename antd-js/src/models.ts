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
