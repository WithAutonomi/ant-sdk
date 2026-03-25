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

/** A descendant entry in a graph node. */
export interface GraphDescendant {
  publicKey: string; // hex
  content: string; // hex, 32 bytes
}

/** A graph entry from the network. */
export interface GraphEntry {
  owner: string;
  parents: string[];
  content: string;
  descendants: GraphDescendant[];
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
