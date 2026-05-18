// Example: Upload and download files.
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"

	antd "github.com/WithAutonomi/ant-sdk/antd-go"
)

func main() {
	client := antd.NewClient(antd.DefaultBaseURL)
	ctx := context.Background()

	tmpDir, err := os.MkdirTemp("", "antd-files-example-*")
	if err != nil {
		log.Fatalf("mkdir temp: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	srcPath := filepath.Join(tmpDir, "hello.txt")
	content := []byte("Hello from a file on Autonomi!")
	if err := os.WriteFile(srcPath, content, 0o600); err != nil {
		log.Fatalf("write source: %v", err)
	}

	est, err := client.FileCost(ctx, srcPath, true)
	if err != nil {
		log.Fatalf("file cost: %v", err)
	}
	fmt.Printf("Estimate: %d bytes in %d chunks, storage %s atto, gas %s wei, mode %s\n",
		est.FileSize, est.ChunkCount, est.Cost, est.EstimatedGasCostWei, est.PaymentMode)

	result, err := client.FileUploadPublic(ctx, srcPath)
	if err != nil {
		log.Fatalf("file upload: %v", err)
	}
	fmt.Printf("Uploaded to %s (storage: %s atto, gas: %s wei, chunks: %d, mode: %s)\n",
		result.Address, result.StorageCostAtto, result.GasCostWei, result.ChunksStored, result.PaymentModeUsed)

	dstPath := srcPath + ".downloaded"
	if err := client.FileDownloadPublic(ctx, result.Address, dstPath); err != nil {
		log.Fatalf("file download: %v", err)
	}
	fmt.Printf("Downloaded to: %s\n", dstPath)

	got, err := os.ReadFile(dstPath)
	if err != nil {
		log.Fatalf("read downloaded: %v", err)
	}
	if string(got) != string(content) {
		log.Fatalf("round-trip mismatch: wrote %q, read %q", content, got)
	}
	fmt.Printf("Content: %s\n", got)
	fmt.Println("File upload/download OK!")
}
