#!/usr/bin/env bash
set -uo pipefail

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
echo -e "${YELLOW}[1/2] Stopping antd...${NC}"
pkill -f 'target/(debug|release)/antd' 2>/dev/null || true
echo -e "${GREEN}       Done${NC}"

# 2. Kill ant devnet
echo -e "${YELLOW}[2/2] Stopping ant devnet...${NC}"
pkill -f 'target/(debug|release)/ant-devnet' 2>/dev/null || true
echo -e "${GREEN}       Done${NC}"

# Clean up saved PIDs
if [[ -f "$PID_FILE" ]]; then
    read -r DEVNET_PID ANTD_PID < "$PID_FILE" 2>/dev/null || true
    for pid in ${DEVNET_PID:-} ${ANTD_PID:-}; do
        kill "$pid" 2>/dev/null || true
    done
    rm -f "$PID_FILE"
fi

# Clean up manifest
rm -f "${TMPDIR:-/tmp}/devnet-manifest.json"

echo ""
echo -e "${CYAN}=== Environment torn down ===${NC}"
echo ""
