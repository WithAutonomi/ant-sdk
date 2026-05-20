// Example: Store and retrieve public and private data.
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

	// Store public data
	result, err := client.DataPutPublic(ctx, []byte("Hello, Autonomi!"), antd.PaymentModeAuto)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Stored public data at %s (chunks: %d, mode: %s)\n", result.Address, result.ChunksStored, result.PaymentModeUsed)

	// Retrieve it
	data, err := client.DataGetPublic(ctx, result.Address)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Retrieved: %s\n", data)

	// Store private data
	privResult, err := client.DataPut(ctx, []byte("Secret message"), antd.PaymentModeAuto)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Stored private data (data_map: %s, chunks: %d, mode: %s)\n", privResult.DataMap, privResult.ChunksStored, privResult.PaymentModeUsed)

	// Retrieve private data
	privData, err := client.DataGet(ctx, privResult.DataMap)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Retrieved private: %s\n", privData)
}
