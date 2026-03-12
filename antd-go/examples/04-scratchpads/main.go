// Example: Versioned mutable state with scratchpads.
package main

import (
	"context"
	"fmt"
	"log"

	antd "github.com/maidsafe/ant-sdk/antd-go"
)

func main() {
	client := antd.NewClient(antd.DefaultBaseURL)
	ctx := context.Background()

	secretKey := "your-64-char-hex-secret-key-here-padding-to-fill-length-000000"

	// Create scratchpad
	result, err := client.ScratchpadCreate(ctx, secretKey, 1, []byte("state v1"))
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Scratchpad at %s\n", result.Address)

	// Update it
	err = client.ScratchpadUpdate(ctx, secretKey, 1, []byte("state v2"))
	if err != nil {
		log.Fatal(err)
	}

	// Read current state
	pad, err := client.ScratchpadGet(ctx, result.Address)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Data: %s (version: %d)\n", pad.Data, pad.Counter)
}
