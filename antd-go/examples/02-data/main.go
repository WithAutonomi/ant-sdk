// Example: Store and retrieve public and private data.
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

	// Store public data
	result, err := client.DataPutPublic(ctx, []byte("Hello, Autonomi!"))
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Stored public data at %s (cost: %s atto)\n", result.Address, result.Cost)

	// Retrieve it
	data, err := client.DataGetPublic(ctx, result.Address)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Retrieved: %s\n", data)

	// Store private data
	privResult, err := client.DataPutPrivate(ctx, []byte("Secret message"))
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Stored private data (data_map: %s, cost: %s atto)\n", privResult.Address, privResult.Cost)

	// Retrieve private data
	privData, err := client.DataGetPrivate(ctx, privResult.Address)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Retrieved private: %s\n", privData)
}
