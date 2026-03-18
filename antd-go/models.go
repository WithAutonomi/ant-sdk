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
