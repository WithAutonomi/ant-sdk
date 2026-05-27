// Example: Private (encrypted) data round-trip.
//
// Private data is encrypted before storage. The returned data map
// is required to retrieve and decrypt the data.
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

	// Store private data
	secretMessage := []byte("This message is encrypted on the network")
	result, err := client.DataPut(ctx, secretMessage, antd.PaymentModeAuto)
	if err != nil {
		log.Fatalf("data put: %v", err)
	}
	fmt.Printf("Data map: %s\n", result.DataMap)
	fmt.Printf("Chunks stored: %d, payment mode: %s\n", result.ChunksStored, result.PaymentModeUsed)

	// Retrieve and decrypt
	retrieved, err := client.DataGet(ctx, result.DataMap)
	if err != nil {
		log.Fatalf("data get: %v", err)
	}
	fmt.Printf("Decrypted: %s\n", retrieved)

	if string(retrieved) != string(secretMessage) {
		log.Fatalf("private data round-trip mismatch: wrote %q, read %q", secretMessage, retrieved)
	}
	fmt.Println("Private data round-trip OK!")
}
