package antd

// HealthStatus is the result of a health check.
type HealthStatus struct {
	OK      bool   `json:"ok"`
	Network string `json:"network"`
}

// PutResult is the result of a put/create operation.
type PutResult struct {
	Cost    string `json:"cost"`    // atto tokens as string
	Address string `json:"address"` // hex
}

// PointerTarget is a reference target for a pointer.
type PointerTarget struct {
	Kind    string `json:"kind"`    // "chunk", "graph_entry", "pointer", "scratchpad"
	Address string `json:"address"` // hex
}

// Pointer is a mutable reference record from the network.
type Pointer struct {
	Address string        `json:"address"`
	Owner   string        `json:"owner"`
	Counter int           `json:"counter"`
	Target  PointerTarget `json:"target"`
}

// Scratchpad is a versioned mutable record from the network.
type Scratchpad struct {
	Address      string `json:"address"`
	DataEncoding int    `json:"data_encoding"`
	Data         []byte `json:"data"`
	Counter      int    `json:"counter"`
}

// GraphDescendant is a descendant entry in a graph node.
type GraphDescendant struct {
	PublicKey string `json:"public_key"` // hex
	Content   string `json:"content"`    // hex, 32 bytes
}

// GraphEntry is a DAG node from the network.
type GraphEntry struct {
	Owner       string            `json:"owner"`
	Parents     []string          `json:"parents"`
	Content     string            `json:"content"`
	Descendants []GraphDescendant `json:"descendants"`
}

// Register is a 32-byte mutable value from the network.
type Register struct {
	Value string `json:"value"` // hex, 32 bytes
}

// Vault is an encrypted key-value record from the network.
type Vault struct {
	Data        []byte `json:"data"`
	ContentType int    `json:"content_type"`
}

// ArchiveEntry is a single entry in a file archive.
type ArchiveEntry struct {
	Path     string `json:"path"`
	Address  string `json:"address"`
	Created  int64  `json:"created"`
	Modified int64  `json:"modified"`
	Size     int64  `json:"size"`
}

// Archive is a collection of archive entries.
type Archive struct {
	Entries []ArchiveEntry `json:"entries"`
}
