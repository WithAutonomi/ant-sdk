//go:build windows

package antd

import (
	"os"
)

// processAlive checks whether a process with the given PID exists.
// On Windows, os.FindProcess opens a handle and fails if the process doesn't exist.
func processAlive(pid int) bool {
	proc, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	_ = proc.Release()
	return true
}
