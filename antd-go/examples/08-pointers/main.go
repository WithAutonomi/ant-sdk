// Example: Create, update and read a pointer.
//
// A pointer is a small, owner-signed, mutable reference. Its address is
// derived from its owner's key and never changes; what it points at can be
// updated by the owner. The daemon signs with owner keys it loaded at startup
// (antd --pointer-keys), so writes name the pointer by its address.
//
// Environment:
//
//	ANTD_POINTER_OWNER  address of a pointer the daemon holds a key for
//	                    (see PointerKeys); required. The first run creates
//	                    the pointer; later runs update it.
//	ANTD_BASE_URL       daemon REST URL (default antd.DefaultBaseURL)
//
// Every write pays, about the price of one chunk, and every attempt pays
// again, so pointer writes are never retried automatically.
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"

	antd "github.com/WithAutonomi/ant-sdk/antd-go"
)

func main() {
	owner := os.Getenv("ANTD_POINTER_OWNER")
	if owner == "" {
		log.Fatal("set ANTD_POINTER_OWNER to the address of a pointer the daemon holds a key for")
	}
	baseURL := os.Getenv("ANTD_BASE_URL")
	if baseURL == "" {
		baseURL = antd.DefaultBaseURL
	}

	client := antd.NewClient(baseURL)
	ctx := context.Background()

	fmt.Println("Note: each pointer write below pays about the price of one chunk: the create (an update if the pointer already exists) and the update.")

	// Store two pieces of public data for the pointer to point at
	first, err := client.DataPutPublic(ctx, []byte("Pointer target, version 1"), antd.PaymentModeAuto)
	if err != nil {
		log.Fatalf("data put (first): %v", err)
	}
	fmt.Printf("Stored first target at %s\n", first.Address)

	second, err := client.DataPutPublic(ctx, []byte("Pointer target, version 2"), antd.PaymentModeAuto)
	if err != nil {
		log.Fatalf("data put (second): %v", err)
	}
	fmt.Printf("Stored second target at %s\n", second.Address)

	// Create the pointer at the first target (paid). A pointer that already
	// exists, say from an earlier run, is refused before paying; point it at
	// the first target with an update instead (also paid).
	created, err := client.PointerCreate(ctx, owner, first.Address, antd.PointerTargetChunk)
	var exists *antd.AlreadyExistsError
	switch {
	case errors.As(err, &exists):
		created, err = client.PointerUpdate(ctx, owner, first.Address, antd.PointerTargetChunk)
		if err != nil {
			log.Fatalf("pointer update (existing): %v", err)
		}
		fmt.Printf("Pointer %s already exists; updated it to the first target instead (counter: %d)\n", created.Address, created.Counter)
	case err != nil:
		log.Fatalf("pointer create: %v", err)
	default:
		fmt.Printf("Created pointer %s (counter: %d)\n", created.Address, created.Counter)
	}

	// Update it to the second target (paid)
	updated, err := client.PointerUpdate(ctx, owner, second.Address, antd.PointerTargetChunk)
	if err != nil {
		log.Fatalf("pointer update: %v", err)
	}
	fmt.Printf("Updated pointer (counter: %d)\n", updated.Counter)

	// Read the pointer back
	record, err := client.PointerGet(ctx, created.Address)
	if err != nil {
		log.Fatalf("pointer get: %v", err)
	}
	fmt.Printf("Pointer: counter %d, %s target %s, final: %v\n", record.Counter, record.Kind, record.Target, record.Final)

	// Follow it to its target and fetch the data there
	target, err := client.PointerResolve(ctx, created.Address)
	if err != nil {
		log.Fatalf("pointer resolve: %v", err)
	}
	fmt.Printf("Resolves to %s %s\n", target.Kind, target.Target)

	if target.Target != second.Address {
		log.Fatalf("pointer resolves to %s, want the second target %s", target.Target, second.Address)
	}
	data, err := client.DataGetPublic(ctx, target.Target)
	if err != nil {
		log.Fatalf("data get: %v", err)
	}
	fmt.Printf("Retrieved: %s\n", data)

	// Ask the pointer's close group where it stands
	finality, err := client.PointerFinality(ctx, created.Address)
	if err != nil {
		log.Fatalf("pointer finality: %v", err)
	}
	fmt.Printf("Finality: %s (%d/%d peers answered)\n", finality.Status, finality.Answered, finality.Group)

	fmt.Println("Pointer round-trip OK!")
}
