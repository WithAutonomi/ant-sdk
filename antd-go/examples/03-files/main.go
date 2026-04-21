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

	// Estimate cost first — rich breakdown so the user sees size/chunks/gas
	// before paying. Legacy callers can still use client.FileCost if they
	// only need the storage cost string.
	est, err := client.EstimateFileCost(ctx, "/path/to/file.txt", true)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Estimate: %d bytes in %d chunks, storage %s atto, gas %s wei, mode %s\n",
		est.FileSize, est.ChunkCount, est.Cost, est.EstimatedGasCostWei, est.PaymentMode)

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
