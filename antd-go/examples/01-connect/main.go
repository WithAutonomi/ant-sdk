// Example: Connect to antd and check health.
package main

import (
	"context"
	"fmt"
	"log"

	antd "github.com/WithAutonomi/ant-sdk/antd-go"
)

func main() {
	client := antd.NewClient(antd.DefaultBaseURL)
	health, err := client.Health(context.Background())
	if err != nil {
		log.Fatalf("health check failed: %v", err)
	}
	fmt.Printf("Daemon OK: %v, Network: %s\n", health.OK, health.Network)
}
