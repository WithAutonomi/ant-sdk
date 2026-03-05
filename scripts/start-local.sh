#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──
# Override these with environment variables or edit below.
AUTONOMI_DIR="${AUTONOMI_DIR:-$HOME/Projects/autonomi}"
ANTD_DIR="${ANTD_DIR:-$(cd "$(dirname "$0")" && pwd)/antd}"
LOG_DIR="${TMPDIR:-/tmp}"
LOG_FILE="$LOG_DIR/evm-testnet.log"

# Bootstrap cache path (Linux vs macOS)
if [[ "$(uname)" == "Darwin" ]]; then
    CACHE_FILE="$HOME/Library/Application Support/autonomi/bootstrap_cache/version_1/bootstrap_cache_local_1_1.0.json"
else
    CACHE_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/autonomi/bootstrap_cache/version_1/bootstrap_cache_local_1_1.0.json"
fi

# ── Colors ──
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;90m'
WHITE='\033[1;37m'
NC='\033[0m'

# Clean up old log
rm -f "$LOG_FILE"

echo ""
echo -e "${CYAN}=== antd Local Test Environment ===${NC}"
echo ""

# 1. Start EVM testnet
echo -e "${YELLOW}[1/4] Starting EVM testnet...${NC}"
(cd "$AUTONOMI_DIR" && cargo run --bin evm-testnet 2>&1 | tee "$LOG_FILE") &
EVM_PID=$!

# 2. Wait for secret key in log
echo -e "${GRAY}       Waiting for secret key...${NC}"
while [[ ! -f "$LOG_FILE" ]]; do
    sleep 2
done
WALLET_KEY=""
while [[ -z "$WALLET_KEY" ]]; do
    sleep 2
    WALLET_KEY=$(grep -oP 'SECRET_KEY=\K.+' "$LOG_FILE" 2>/dev/null | head -1 | tr -d '[:space:]') || true
done
echo -e "${GREEN}       Got wallet key: ${WALLET_KEY:0:10}...${NC}"

# 3. Start local network
echo -e "${YELLOW}[2/4] Starting local Autonomi network...${NC}"

# Delete old bootstrap cache
if [[ -f "$CACHE_FILE" ]]; then
    rm -f "$CACHE_FILE"
    echo -e "${GRAY}       Cleared old bootstrap cache${NC}"
fi

(cd "$AUTONOMI_DIR" && cargo run --release --bin antctl -- local run --build --clean --rewards-address 0xd10A556E6A5111b5D4Dd5Ae06761d41F6CE1D499 2>&1) &
NET_PID=$!

echo -e "${GRAY}       Waiting for network (this may take a while with --build)...${NC}"
PEER_ADDR=""
for i in $(seq 1 120); do
    sleep 3
    if [[ -f "$CACHE_FILE" ]]; then
        # Extract first multiaddr from the bootstrap cache JSON
        PEER_ADDR=$(python3 -c "
import json, sys
try:
    cache = json.load(open('$CACHE_FILE'))
    if cache.get('peers') and len(cache['peers']) > 0:
        print(cache['peers'][0][1][0])
except Exception:
    pass
" 2>/dev/null) || true
        if [[ -n "$PEER_ADDR" ]]; then
            break
        fi
    fi
done

if [[ -z "$PEER_ADDR" ]]; then
    echo -e "${RED}       Could not find local peers in bootstrap cache!${NC}"
    exit 1
fi
echo -e "${GREEN}       Found peer: ${PEER_ADDR:0:40}...${NC}"

# 4. Start antd
echo -e "${YELLOW}[3/4] Starting antd...${NC}"
(cd "$ANTD_DIR" && AUTONOMI_WALLET_KEY="$WALLET_KEY" ANT_PEERS="$PEER_ADDR" cargo run -- --network local 2>&1) &
ANTD_PID=$!

# Save PIDs for kill script
PID_FILE="$LOG_DIR/antd-local-pids"
echo "$EVM_PID $NET_PID $ANTD_PID" > "$PID_FILE"

# 5. Wait for antd health
echo -e "${YELLOW}[4/4] Waiting for antd to be ready...${NC}"
READY=false
for i in $(seq 1 60); do
    sleep 3
    if curl -s http://localhost:8080/health 2>/dev/null | grep -q '"ok"'; then
        READY=true
        break
    fi
done

echo ""
if $READY; then
    echo -e "${GREEN}=== Ready! ===${NC}"
    echo ""
    echo -e "${WHITE}  REST:  http://localhost:8080${NC}"
    echo -e "${WHITE}  gRPC:  localhost:50051${NC}"
    echo -e "${WHITE}  Key:   ${WALLET_KEY:0:10}...${NC}"
    echo ""
    echo -e "${GRAY}Quick test:${NC}"
    echo -e "${GRAY}  curl http://localhost:8080/health${NC}"
    echo ""
    echo -e "${GRAY}To tear down:${NC}"
    echo -e "${GRAY}  ./scripts/kill-local.sh${NC}"
else
    echo -e "${RED}=== antd did not respond within timeout ===${NC}"
    echo -e "${GRAY}Check process output for errors.${NC}"
fi
