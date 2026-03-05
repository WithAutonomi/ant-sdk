#!/usr/bin/env bash
set -uo pipefail

AUTONOMI_DIR="${AUTONOMI_DIR:-$HOME/Projects/autonomi}"
PID_FILE="${TMPDIR:-/tmp}/antd-local-pids"

# ── Colors ──
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=== Tearing down local environment ===${NC}"
echo ""

# 1. Kill antd
echo -e "${YELLOW}[1/3] Stopping antd...${NC}"
pkill -f 'target/(debug|release)/antd' 2>/dev/null || true
echo -e "${GREEN}       Done${NC}"

# 2. Kill local network via antctl
echo -e "${YELLOW}[2/3] Stopping local network...${NC}"
(cd "$AUTONOMI_DIR" && cargo run --release --bin antctl -- local kill 2>&1) > /dev/null || true
echo -e "${GREEN}       Done${NC}"

# 3. Kill EVM testnet
echo -e "${YELLOW}[3/3] Stopping EVM testnet...${NC}"
pkill -f 'target/(debug|release)/evm-testnet' 2>/dev/null || true
echo -e "${GREEN}       Done${NC}"

# Clean up saved PIDs
if [[ -f "$PID_FILE" ]]; then
    read -r EVM_PID NET_PID ANTD_PID < "$PID_FILE" 2>/dev/null || true
    for pid in ${EVM_PID:-} ${NET_PID:-} ${ANTD_PID:-}; do
        kill "$pid" 2>/dev/null || true
    done
    rm -f "$PID_FILE"
fi

echo ""
echo -e "${CYAN}=== Environment torn down ===${NC}"
echo ""
