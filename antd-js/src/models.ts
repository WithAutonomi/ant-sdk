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

/** Target reference for a pointer. */
export interface PointerTarget {
  kind: "chunk" | "graph_entry" | "pointer" | "scratchpad";
  address: string; // hex
}

/** A pointer record from the network. */
export interface Pointer {
  address: string;
  owner: string;
  counter: number;
  target: PointerTarget;
}

/** A scratchpad record from the network. */
export interface Scratchpad {
  address: string;
  dataEncoding: number;
  data: Buffer;
  counter: number;
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

/** A register value from the network. */
export interface Register {
  value: string; // hex, 32 bytes
}

/** A vault record from the network. */
export interface Vault {
  data: Buffer;
  contentType: number;
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
