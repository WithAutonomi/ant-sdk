// Example: Create and update mutable pointers.
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

	// Store v1 of data
	v1, err := client.DataPutPublic(ctx, []byte("config v1"))
	if err != nil {
		log.Fatal(err)
	}

	// Create pointer to v1
	target := antd.PointerTarget{Kind: "chunk", Address: v1.Address}
	ptr, err := client.PointerCreate(ctx, secretKey, target)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Pointer created at %s\n", ptr.Address)

	// Store v2 and update pointer
	v2, err := client.DataPutPublic(ctx, []byte("config v2"))
	if err != nil {
		log.Fatal(err)
	}

	err = client.PointerUpdate(ctx, secretKey, antd.PointerTarget{Kind: "chunk", Address: v2.Address})
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println("Pointer updated to v2")

	// Read current pointer target
	current, err := client.PointerGet(ctx, ptr.Address)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Current target: %s (counter: %d)\n", current.Target.Address, current.Counter)
}
