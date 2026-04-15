// Example: Upload and download files.
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

	// Estimate cost first
	cost, err := client.FileCost(ctx, "/path/to/file.txt", true)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Estimated cost: %s atto\n", cost)

	// Upload
	result, err := client.FileUploadPublic(ctx, "/path/to/file.txt")
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Uploaded to %s (storage: %s atto, gas: %s wei, chunks: %d, mode: %s)\n",
		result.Address, result.StorageCostAtto, result.GasCostWei, result.ChunksStored, result.PaymentModeUsed)

	// Download
	err = client.FileDownloadPublic(ctx, result.Address, "/path/to/output.txt")
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println("Downloaded successfully")
}
