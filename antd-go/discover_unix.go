//go:build !windows

package antd

import (
	"os"
	"syscall"
)

// processAlive checks whether a process with the given PID exists
// by sending signal 0 (a no-op that checks process existence).
func processAlive(pid int) bool {
	proc, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	err = proc.Signal(syscall.Signal(0))
	return err == nil
}
