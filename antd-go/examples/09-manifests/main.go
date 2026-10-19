// Example: Build a manifest of two files and read it back from its link.
//
// A manifest (ADR-0006) is a `.ant` file, or an `ant://manifest/` link when
// it is small enough, that lists a set of files: each with a path, an
// optional size, and either an embedded DataMap or a public DataMap address.
// The daemon builds and decodes manifests from DataMaps and addresses already
// in hand, so building and decoding upload nothing and pay nothing.
//
// Environment:
//
//	ANTD_BASE_URL  daemon REST URL (default antd.DefaultBaseURL)
//
// Only the two data uploads pay.
package main

import (
	"context"
	"fmt"
	"log"
	"os"

	antd "github.com/WithAutonomi/ant-sdk/antd-go"
)

func main() {
	baseURL := os.Getenv("ANTD_BASE_URL")
	if baseURL == "" {
		baseURL = antd.DefaultBaseURL
	}

	client := antd.NewClient(baseURL)
	ctx := context.Background()

	fmt.Println("Note: the two data uploads below pay; building and decoding the manifest pays nothing.")

	// Store two small pieces of public data for the manifest to list (paid)
	one, err := client.DataPutPublic(ctx, []byte("Manifest example, note one"), antd.PaymentModeAuto)
	if err != nil {
		log.Fatalf("data put (one): %v", err)
	}
	fmt.Printf("Stored notes/one.txt at %s\n", one.Address)

	two, err := client.DataPutPublic(ctx, []byte("Manifest example, note two: a little longer"), antd.PaymentModeAuto)
	if err != nil {
		log.Fatalf("data put (two): %v", err)
	}
	fmt.Printf("Stored notes/two.txt at %s\n", two.Address)

	// Build a manifest that names them (free)
	built, err := client.BuildManifest(ctx, []antd.ManifestEntryInput{
		{Path: "notes/one.txt", Address: one.Address},
		{Path: "notes/two.txt", Address: two.Address},
	}, &antd.BuildManifestOptions{Name: "example"})
	if err != nil {
		log.Fatalf("build manifest: %v", err)
	}
	fmt.Printf("Built a %d-byte manifest\n", len(built.Manifest))
	if built.Link == "" {
		log.Fatal("the manifest did not fit in a link")
	}
	fmt.Printf("Link: %s\n", built.Link)
	for _, e := range built.Entries {
		fmt.Printf("  %s (%s) -> %s\n", e.EffectiveName, e.Kind, e.ContentAddress)
	}

	// Decode the link, resolving each entry's DataMap for its exact size (free)
	decoded, err := client.DecodeManifestLink(ctx, built.Link, true)
	if err != nil {
		log.Fatalf("decode manifest link: %v", err)
	}
	fmt.Printf("Decoded %s %q with %d entries\n", decoded.Source, decoded.Name, len(decoded.Entries))
	for _, e := range decoded.Entries {
		// One entry's resolve failure is reported on the entry, not as a
		// failed call.
		if e.Error != "" {
			log.Fatalf("resolve %s: %s", e.EffectiveName, e.Error)
		}
		if e.ExactSize == nil {
			fmt.Printf("  %s: exact size unknown\n", e.EffectiveName)
			continue
		}
		fmt.Printf("  %s: %d bytes\n", e.EffectiveName, *e.ExactSize)
	}

	fmt.Println("Manifest round-trip OK!")
}
