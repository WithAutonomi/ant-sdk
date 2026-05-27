// Example: Store and retrieve raw chunks.
//
// Chunks are the lowest-level storage primitive on Autonomi.
package main

import (
	"context"
	"fmt"
	"log"

	antd "github.com/WithAutonomi/ant-sdk/antd-go"
)

func main() {
	client := antd.NewClient(antd.DefaultBaseURL)
	ctx := context.Background()

	// Store a raw chunk
	rawData := []byte("Raw chunk content for direct storage")
	result, err := client.ChunkPut(ctx, rawData)
	if err != nil {
		log.Fatalf("chunk put: %v", err)
	}
	fmt.Printf("Chunk stored at: %s\n", result.Address)
	fmt.Printf("Cost: %s atto tokens\n", result.Cost)

	// Retrieve the chunk
	retrieved, err := client.ChunkGet(ctx, result.Address)
	if err != nil {
		log.Fatalf("chunk get: %v", err)
	}
	fmt.Printf("Retrieved %d bytes\n", len(retrieved))

	if string(retrieved) != string(rawData) {
		log.Fatalf("chunk round-trip mismatch: wrote %q, read %q", rawData, retrieved)
	}
	fmt.Println("Chunk round-trip OK!")
}
