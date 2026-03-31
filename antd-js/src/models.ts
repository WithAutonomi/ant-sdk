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

/** An entry in a file archive. */
export interface ArchiveEntry {
  path: string;
  address: string;
  created: number;
  modified: number;
  size: number;
}

/** A collection of archive entries. */
export interface Archive {
  entries: ArchiveEntry[];
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

/** Result of preparing an upload for external signing. */
export interface PrepareUploadResult {
  uploadId: string; // hex identifier
  payments: PaymentInfo[];
  totalAmount: string;
  dataPaymentsAddress: string; // contract address
  paymentTokenAddress: string; // token contract address
  rpcUrl: string; // EVM RPC URL
}

/** Result of finalizing an externally-signed upload. */
export interface FinalizeUploadResult {
  address: string; // hex address of stored data
  chunksStored: number;
}
